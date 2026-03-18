# ANE Chaining v2 — Activation Attempt

> Follow-up research: constructing `_ANEOutputSetEnqueue` correctly and getting
> `prepareChainingWithModel` to succeed.
> Tested on M3 Pro (h15g), macOS 26.3.1, Build 25D2128.

---

## Key Findings Summary

| Finding | Impact |
|:---|:---|
| **`prepareChainingWithModel` → SUCCESS** | First successful chaining prepare call |
| **5 undocumented requirements solved** | Dynamic method patching, NSSecureCoding, type corrections |
| **`enqueueSetsWithModel` still fails** | Model needs CoreML pipeline path, not in-memory |
| **Not usable with Dynamic Spatial Packing** | Chaining requires `_ANEModel` (file-based), not `_ANEInMemoryModel` |

---

## What Was Required for `prepareChainingWithModel` Success

### 1. `_ANEOutputSetEnqueue` needs `-outputBuffer` method
The framework calls `-[_ANEOutputSetEnqueue outputBuffer]` during validation and XPC serialization,
but the class doesn't implement it. Fixed by dynamically adding the method via `class_addMethod`.

### 2. `lbInputSymbolId` / `lbOutputSymbolId` are NSArray, not NSNumber
Property type is `NSArray`. Passing `@0` (NSNumber) caused `-[NSConstantIntegerNumber count]` crash.
Must pass `@[@0]` instead.

### 3. `inputBuffer` must contain `_ANEBuffer` objects
Not `_ANEIOSurfaceObject`. The framework calls `-[element symbolIndex]` which only `_ANEBuffer` has.

### 4. Model must be `_ANEModel` (not `_ANEInMemoryModel`)
`prepareChainingWithModel:` serializes the model via XPC (NSSecureCoding).
`_ANEInMemoryModel` doesn't support NSSecureCoding. `_ANEModel` does.

### 5. `_ANEOutputSetEnqueue` needs NSSecureCoding conformance
Serialized as part of `_ANEChainingRequest` via XPC. Added dynamically:
`+supportsSecureCoding`, `-encodeWithCoder:`, `-initWithCoder:`, and protocol conformance.

---

## XPC Architecture

```
prepareChainingWithModel (client)
  → doPrepareChainingWithModel (client)
    → prepareChainingWithModel:options:chainingReq:qos:withReply: (daemon XPC)
      → Serializes: _ANEModel (NSSecureCoding) + _ANEChainingRequest (NSSecureCoding)
        → _ANEChainingRequest encodes outputSets array
          → Each _ANEOutputSetEnqueue must be NSSecureCoding
            → Each needs -outputBuffer (NSArray of _ANEBuffer)
```

---

## Why `enqueueSetsWithModel` Fails

`enqueueSetsWithModel:outputSet:options:qos:error:` returns NO silently because:

1. `_ANEModel` created via `modelAtURL:key:` has `programHandle = 0` (state=1, not loaded)
2. The daemon `loadModel` call fails with "file access failure"
3. `_ANEInMemoryModel` compiles to a daemon-side cache invisible to `_ANEModel`
4. The daemon expects models via the CoreML pipeline for proper sandbox extension handling

### To Fully Activate

Would need to:
1. Compile a `.mlmodelc` package through CoreML
2. Load it with `_ANEModel` via the standard file-based path
3. The daemon then has sandbox access to the compiled model
4. Then `enqueueSetsWithModel` should work

This is fundamentally incompatible with our Dynamic Spatial Packing approach (which uses
`_ANEInMemoryModel` for zero-recompilation training).

---

## Practical Conclusion

**Chaining is not useful for our training pipeline.** It requires:
- File-based models (`_ANEModel`) — we use in-memory models
- CoreML compilation pipeline — we bypass CoreML entirely
- Static weights — we need dynamic weight updates

**For text generation** (autoregressive, same model repeated), chaining could work if we:
- Compile the inference model via CoreML once
- Load as `_ANEModel`
- Use chaining for token-by-token generation

But at QoS=9, sequential eval already has ~0 dispatch overhead, so the benefit would be
eliminating the CPU round-trip between iterations — potentially useful for latency-critical
inference but not a priority for training.

---

*Last updated: 2026-03-18 | M3 Pro (h15g), macOS 26.3.1 (25D2128)*
*Source: `repo/training/test_chaining_v2.m`*
