# ANE Compiler Analytics — Deep Findings

> Research results from probing `_ANECompilerAnalytics` and its sub-structures for
> per-layer SRAM usage and spill data.
> Tested on M3 Pro (h15g), macOS 26.3.1, Build 25D2128.

---

## Key Findings Summary

| Finding | Impact |
|:---|:---|
| **17 analytics metric types discovered** | DRAM/L2 traffic, NE/DRAM domain time, spill flags |
| **Per-layer cost data exists** | `_AnalyticsLayerInfo` has `float value` per layer |
| **`ViolatesMaxLatency` flag** | Would indicate SRAM spills — exactly what we need |
| **Buffer is daemon-side only** | `aned` generates it but doesn't return it to client |
| **`EspressoProfilingANEcompilerAnalytics`** | May write analytics to disk when profiling enabled |

---

## Analytics Metric Types

`_ANECompilerAnalytics +stringForAnalyticsType:` reveals 17 named metrics:

| ID | Name | Purpose |
|:---|:---|:---|
| 0 | Unsupported | |
| 1 | Start Time Stamp | Compilation start |
| 2 | End Time Stamp | Compilation end |
| 3 | **DRAMTraffic** | DRAM bandwidth consumed |
| 4 | **L2Traffic** | L2 cache traffic |
| 5 | **Static Analytics - NE domain time** | Neural Engine compute time |
| 6 | **Static Analytics - L2 domain time** | L2 cache domain time |
| 7 | **Static Analytics - DRAM domain time** | DRAM access time |
| 8 | **Static Analytics - Total elapsed time** | End-to-end latency |
| 9 | **Static Analytics - Procedure Latency** | Per-procedure latency |
| 10 | TaskId | Task identifier |
| 11 | **ViolatesMaxLatency** | **Spill/latency violation flag** |
| 12 | **Static Analytics - NE Frequency** | ANE clock frequency |
| 13 | **Static Analytics - L2 Frequency** | L2 cache frequency |
| 14 | **Static Analytics - DRAM Bandwidth** | DRAM bandwidth spec |
| 15 | Ident String | Model identifier |
| 16 | **MAX TD Latency** | Max task dispatch latency |

## Class Hierarchy

```
_ANECompilerAnalytics
  ├─ analyticsBuffer (NSData)          — raw binary from compiler
  ├─ populateAnalytics                 — parses buffer → procedureAnalytics
  └─ procedureAnalytics                — NSArray<_ANEAnalyticsProcedure>
      └─ _ANEAnalyticsProcedure
          ├─ identifier (NSString)
          ├─ procedureMetrics (NSDictionary)
          └─ groupInfo                 — NSArray<_ANEAnalyticsGroup>
              └─ _ANEAnalyticsGroup
                  ├─ groupID (NSNumber)
                  ├─ layerInfo         — NSArray<_ANEAnalyticsLayer>
                  │   └─ _ANEAnalyticsLayer
                  │       ├─ layerName (NSString)
                  │       └─ weight (float)   ← PER-LAYER COST
                  └─ taskInfo          — NSArray<_ANEAnalyticsTask>
                      └─ _ANEAnalyticsTask
                          └─ metrics (NSDictionary)
```

## Struct Layouts (from type encodings)

```c
// Per-layer info: 132 bytes
struct _AnalyticsLayerInfo {
    char name[64];     // layer name
    char type[64];     // layer type
    float value;       // cost/weight metric
};

// Per-procedure info: 48 bytes
struct _AnalyticsProcedureInfo {
    uint32_t field0;   // procedure index?
    uint32_t field1;   // layer count?
    uint32_t field2;   // group count?
    uint32_t field3;   // task count?
    uint32_t field4;
    uint64_t field5;
    uint32_t field6;
    uint64_t field7;
};

// Per-task info: 16 bytes
struct _AnalyticsTaskInfo {
    uint32_t taskId;
    uint64_t metric;   // likely latency or traffic
};

// Per-group info: 32 bytes
struct _AnalyticsGroupInfo {
    uint32_t groupId;
    uint64_t field1;
    uint32_t field2;
    uint64_t field3;
};
```

## The Problem: Buffer is Daemon-Side

`_ANECompilerAnalytics` is a **parser**, not a producer. It takes an `NSData` buffer via
`+objectWithBuffer:` and parses it into the hierarchy above.

The buffer is generated inside `aned` daemon during `compileModel:sandboxExtension:options:qos:withReply:`
on `_ANEDaemonConnection`. The daemon's XPC reply does **not** pass the analytics buffer back to
the client in the normal compilation flow.

## How to Get the Analytics Buffer

### Option 1: XPC Reply Interception
Swizzle `_ANEDaemonConnection`'s compile reply handler to capture the raw analytics buffer
before it's discarded. Requires method swizzling at runtime.

### Option 2: CoreML Profiling Environment
`EspressoProfilingANEcompilerAnalytics` has a `compiler_analytics_file_names` property (NSArray),
suggesting analytics are written to disk files when profiling is enabled.
Try: `COREML_PROFILING=1 ./ane bench` or similar environment variables.

### Option 3: Construct Buffer Manually
If we can determine the binary format of the analytics buffer (header + array of structs),
we could potentially request it via compile options. The `kANEFPerformanceStatsMask` option
might trigger analytics buffer generation on the client side.

## What We CAN See Without the Buffer

From `modelAttributes.NetworkStatusList` after compile+load:

```
Per tensor: BatchStride, PlaneStride, RowStride,
            Channels, Width, Height, Depth,
            Interleave, Symbol, Type
```

`intermediateBufferHandle = 0` for all tested kernel sizes (256-2048), indicating no
intermediate SRAM spill for single-conv models. Multi-layer models would likely show
non-zero handles when spilling occurs.

---

*Last updated: 2026-03-18 | M3 Pro (h15g), macOS 26.3.1 (25D2128)*
*Source: `repo/training/test_compiler_analytics.m`*
