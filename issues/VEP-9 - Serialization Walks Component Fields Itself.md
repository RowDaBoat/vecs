# VEP-9 - Serialization Walks Component Fields Itself
**Status:** Closed


## Problem
Components holding anything beyond flat scalar fields did not round-trip through binary serialization. Three shapes failed, for two different reasons:
- **`Id[T]` and `EntityId`** carry a private `value: int`. Serializing them as plain objects leaks an implementation detail into the format, and the type parameter on `Id[T]` is a compile time constraint with no runtime data to store.
- **Fixed size arrays** (e.g. a `Vec3` or `Quat` field) packed correctly, since they coerce to `openArray`, but `cborious` had no terminal case to unpack one. Its catch-all generic recursed into itself until the call depth limit. This compiled cleanly and only failed at runtime.
- **Objects nested two or more levels deep** matched no overload at all. `cborious`'s `cborPackObjectMap`/`cborPackObjectArray` call `cborPack(field)` resolved against the overload set frozen at *their* definition point, and its own generic `cborPack*[T: tuple|object]` is declared further down the file with no forward declaration. The nested case therefore cannot see the very proc that would handle it. Unpacking has the same shape.

Adding `cborPack`/`cborUnpack` overloads for the leaf types is not sufficient. Overloads fix the leaves, but the traversal in between still runs inside `cborious`, so the frozen overload set keeps the deep nesting broken.


## Solution
`serialization.nim` owns the traversal for binary serialization: `packValue`/`unpackValue` recurse over component fields directly and only call into `cborious` for terminal scalars, strings and byte sequences. `cborious`'s object walkers are never entered, so the frozen overload set never applies.

The walkers dispatch on shape:
- `Id[T]` and `EntityId` pack as the bare `int` they wrap.
- `seq` and `array` pack as a CBOR array, recursing per item. `unpackArray` fills up to the destination's fixed length and `skipCborMsg`s any surplus, so a length change does not corrupt the stream.
- `object` and `tuple` pack as a CBOR map of field name to value, recursing per field. `unpackFields` matches incoming names against the destination's fields and skips unknown ones, so an unrecognised field does not corrupt the stream either.
- Anything else falls through to `cborious`.

Text serialization needs no equivalent, because `std/jsonutils` dispatches through `when compiles(toJsonHook(...))`, which resolves openly at instantiation. Defining `toJsonHook`/`fromJsonHook` for `Id[T]` is enough there, and arrays and nested objects come for free.


## Notes
- The upstream fix in `cborious` is two forward declarations of the generic `cborPack`/`cborUnpack` above its object walkers. Patching it was out of scope; the walker is not a workaround waiting on that, since owning the traversal is also what lets `Id[T]` serialize as an `EntityId` in the first place.
- These are two of three field walkers in `vecs`, the third being [VEP-8](VEP-8%20-%20Adding%20Worlds.md)'s `remapIds`. They visit the same shapes but act differently at the leaves, and only this pair has to agree with the other on a wire format. Sharing one walker would mean parameterising the leaf action across three unrelated purposes for no gain.
- `unpackValue` needs a forward declaration for mutual recursion with `unpackMatchingField`.


## References
[VEP-8 - Adding Worlds](VEP-8%20-%20Adding%20Worlds.md)
