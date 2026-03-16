# libane — C API for Apple Neural Engine

Standalone C library that wraps Apple's private Neural Engine framework into a clean, stable API. With automatic version detection — survives API changes in future macOS versions.

## Build

```bash
make test        # Compile + run tests
make libane.dylib  # Build shared library
```

## API

### Initialization

```c
#include "ane.h"

// Load framework, resolve classes, detect version
int rc = ane_init();  // 0=OK, -1=framework not found, -2=classes missing

// Hardware info
ANEDeviceInfo info = ane_device_info();
// info.arch = "h15g", info.num_cores = 16, info.has_ane = true, ...

// API diagnostics (prints to stderr)
ane_print_diagnostics();

// What was detected?
ANEAPIInfo api = ane_api_info();
// api.api_version = 1, api.classes_found = 35, api.has_chaining = true, ...
```

### Compilation & Evaluation

**Note:** `@model_path/weights/...` is a symbolic name, not a file path. It connects weight blobs in the MIL program with the actual data in memory. The name must match between the MIL code and the `ane_weight_*` call — the ANE compiler resolves the mapping.

```c
// Build weight blob (float32 → ANE FP16 format)
ANEWeight w = ane_weight_fp16("@model_path/weights/w.bin", float_data, rows, cols);

// Generate MIL code (linear layer as 1x1 conv)
char *mil = ane_mil_linear(in_ch, out_ch, seq, "@model_path/weights/w.bin");

// Compile
size_t in_sz = in_ch * seq * 4;   // fp32
size_t out_sz = out_ch * seq * 4;
ANEKernel *k = ane_compile(mil, strlen(mil), &w, 1,
                           1, &in_sz, 1, &out_sz,
                           ANE_QOS_BACKGROUND);

// Write data → run ANE → read result
ane_write(k, 0, input_data, in_sz);
ane_eval(k, ANE_QOS_BACKGROUND);
ane_read(k, 0, output_data, out_sz);

// Clean up
ane_free(k);
free(mil);
ane_weight_free(&w);
```

### Dynamic Weights (Training)

For training you need weights that can be changed **without recompilation**. The ANE has a hard compilation limit (see [Compile Budget](#compile-budget)) — every `ane_compile()` call counts and after ~119 compilations per process the ANE fails silently.

**Dynamic Spatial Packing** solves this problem: weights are encoded as input channels instead of being baked in at compile time. Compile once, change weights as many times as you want via IOSurface write.

#### `ane_mil_linear_dynamic(in_ch, out_ch, seq)`

Generates MIL for a **dynamic** linear layer. Unlike `ane_mil_linear()`, the weights are not baked in at compile time but passed as additional input channels.

- **Input tensor:** `[1, in_ch + in_ch*out_ch, 1, seq]` fp32
  - Channels `[0..in_ch)` = activations (input data)
  - Channels `[in_ch..in_ch+in_ch*out_ch)` = weight matrix, flat-encoded
  - Weight layout: `W[i][j]` is in channel `(in_ch + i*in_ch + j)`, spatial position 0
- **Output tensor:** `[1, out_ch, 1, seq]` fp32
- **No weight name needed** — there is no `@model_path/weights/...` parameter
- **When to use:** Whenever weights change (training, fine-tuning, online learning). `ane_mil_linear()` is only intended for static inference with fixed weights.

#### `ane_write_dynamic_weights(k, idx, W, in_ch, out_ch, seq)`

Packs a weight matrix `W[out_ch][in_ch]` into the correct channel/spatial layout of the input IOSurface. Must be called after every weight update, **before** `ane_eval()`.

- `k` — Compiled kernel (from `ane_compile()`)
- `idx` — Input tensor index (usually 0)
- `W` — Weight data as `float[out_ch * in_ch]` (row-major)
- `in_ch, out_ch, seq` — Same dimensions as in `ane_mil_linear_dynamic()`

#### Complete Example: Compile-Once Pattern

```c
#include "ane.h"
#include <string.h>
#include <stdlib.h>

int in_ch = 8, out_ch = 4, seq = 1;

// 1) Generate MIL — no weights at compile time
char *mil = ane_mil_linear_dynamic(in_ch, out_ch, seq);

// 2) Input = activations + weights together, no ANEWeight needed
size_t in_sz = (in_ch + in_ch * out_ch) * seq * sizeof(float);
size_t out_sz = out_ch * seq * sizeof(float);

// 3) Compile ONCE — this kernel lives for the entire training session
ANEKernel *k = ane_compile(mil, strlen(mil), NULL, 0,
                           1, &in_sz, 1, &out_sz,
                           ANE_QOS_BACKGROUND);
free(mil);

// 4) Training loop: change weights without recompilation
float W[4 * 8];  // out_ch × in_ch
float input[8];   // activations
float output[4];  // result

for (int step = 0; step < 10000; step++) {
    // ... update W and input (gradient descent etc.) ...

    // Pack weights into IOSurface (correct layout)
    ane_write_dynamic_weights(k, 0, W, in_ch, out_ch, seq);

    // Write activations into the first in_ch channels
    ane_lock_input(k, 0);
    float *ptr = (float *)ane_input_ptr(k, 0);
    memcpy(ptr, input, in_ch * sizeof(float));
    ane_unlock_input(k, 0);

    // Run ANE
    ane_eval(k, ANE_QOS_BACKGROUND);

    // Read result
    ane_read(k, 0, output, out_sz);
}

ane_free(k);
```

### Zero-Copy I/O

```c
// Write directly to IOSurface (no memcpy)
ane_lock_input(k, 0);
float *ptr = (float *)ane_input_ptr(k, 0);
for (int i = 0; i < n; i++) ptr[i] = data[i];
ane_unlock_input(k, 0);

ane_eval(k, ANE_QOS_BACKGROUND);

// Read directly from IOSurface
ane_lock_output(k, 0);
float *out = (float *)ane_output_ptr(k, 0);
// ... use out[i] ...
ane_unlock_output(k, 0);
```

### Weight Builder

```c
// FP16 (standard)
ANEWeight w = ane_weight_fp16(name, float_data, rows, cols);

// FP16 transposed
ANEWeight wt = ane_weight_fp16_transposed(name, float_data, rows, cols);

// INT8 quantized (symmetric, scale = max(|w|)/127)
float scale;
ANEWeight wq = ane_weight_int8(name, float_data, rows, cols, &scale);
```

### QoS Levels

```c
ANE_QOS_BACKGROUND        // 9  — Fastest! For training.
ANE_QOS_UTILITY           // 17
ANE_QOS_DEFAULT           // 21 — Default
ANE_QOS_USER_INITIATED    // 25
ANE_QOS_USER_INTERACTIVE  // 33
ANE_QOS_REALTIME          // 0  — Special mode
```

### Compile Budget

The ANE has a **hard compilation limit per process**. After ~119 `ane_compile()` calls the ANE fails silently — no error message, just crashes or incorrect results.

```c
#define ANE_COMPILE_BUDGET     119  // Absolute limit
#define ANE_COMPILE_SAFE_LIMIT 110  // Safety margin

// Query current counter
int count = ane_compile_count();

if (count >= ANE_COMPILE_SAFE_LIMIT) {
    // Restart process (exec()) before the budget is exhausted
    // The counter only resets on process restart
}
```

**Consequence for training:** This is why [Dynamic Spatial Packing](#dynamic-weights-training) is the recommended approach — compile once, change weights as many times as you want, budget stays at 1.

### Weight Reload (EXPERIMENTAL)

> **EXPERIMENTAL — Not recommended.** `ane_reload_weights()` uses delta compilation (unload model, patch weight files on disk, reload model). This works but is **fragile and slower** than Dynamic Spatial Packing. For training the [Dynamic Weights](#dynamic-weights-training) approach is recommended.

```c
// Build new weights
ANEWeight w_new = ane_weight_fp16("@model_path/weights/w.bin", new_data, rows, cols);

// Hot-swap weights without ane_compile() — does NOT count toward compile budget
bool ok = ane_reload_weights(k, &w_new, 1, ANE_QOS_BACKGROUND);
if (!ok) {
    // Fallback: recompile (consumes compile budget!)
    k = ane_compile(...);
}

ane_weight_free(&w_new);
```

## Version Detection

If Apple renames private classes in a future macOS:

1. `ane_init()` automatically tries known alternatives
2. If nothing matches: returns `-2` and lists ALL found ANE classes on stderr
3. Add new names to `ane.m`, recompile — done
4. `ane.h` stays unchanged — your code never breaks

```
# Diagnostic output when everything works:
=== libane diagnostics ===
API version:     1 (current)
macOS build:     25D2128
Classes found:   35
Descriptor:      OK (_ANEInMemoryModelDescriptor)
Model:           OK (_ANEInMemoryModel)
Request:         OK
IOSurface:       OK
...
```

## Tested on

- MacBook Pro M3 Pro, 18GB RAM, macOS 26.3.1 (Build 25D2128)
- ANE Architecture: h15g, 16 Cores
