# VEP-10 - Wasm Target
**Status:** Open


## Requirement
`vecs` doesn't build for wasm32, where `int` is 4 bytes. Two defects, both found while cross-compiling vexel's web sample.

**The invalid sentinel doesn't fit in an `int`.** `entityid.nim` declares `INVALID_ENTITY_VALUE* = int(ENTITY_ID_MASK)`, and `4294967295` can't be converted to a 32-bit `int`. `isValid`, in both `entityid.nim` and `id.nim`, compares through `value: int`, so the sentinel round-trips through the narrower type.

**The payload data offset assumes `sizeof(int) >= alignof(T)`.** `unsafeseq.nim` reads and writes `UnsafeSeqPayload.data` at `sizeof(int)` bytes into the payload, but the C compiler places it at `align(sizeof(int), alignof(T))`. With a 4-byte `int`, every component aligned to 8 — anything holding an `EntityId`, so `Meta` and most archetypes — has its elements 4 bytes past where `UnsafeSeq` puts them. The static assert `alignof(T) <= sizeof(int)` stops the build instead of corrupting memory, which is how the bug surfaces. The type-erased path can't fix it locally either: `rawSeqGrow`, `rawSeqGet`, `rawSeqAdd` and `EcsSeqAny.stride` only carry a stride, never the offset.


## Solution
- Keep the invalid sentinel in `uint64` space and compare against `e.val and ENTITY_ID_MASK`, so `isValid` never goes through `int`.
- Derive the payload data offset from `alignof(T)` and carry it alongside the stride through the type-erased API. The static assert then only has to guard what the allocator guarantees, `alignof(uint64)`.
- Add a `wasm` target that builds and runs the test suite: `--os:linux --cpu:wasm32 --cc:clang` with `clang.exe` and `clang.linkerexe` pointed at emscripten's `emcc`, plus `--gc:orc -d:useMalloc -o:<test>.js`, run under node.


## Notes
With both defects fixed, all 15 tests pass as wasm32 under node, so nothing else in `vecs` assumes a 64-bit `int`.

Vexel's web build is tracked by its own `VIP-20 - Raytracing on the Web` and `VIP-21 - Restore the Web Build`.
