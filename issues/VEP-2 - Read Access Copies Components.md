# VEP-2 - Read Access Copies Components
**Status:** Open


## Bug
Plain `T` in a query tuple yields a value copy of each component. `accessTuple` leaves `T` unchanged, so `buildAccessTuple` copies the component out of the heap-allocated `EcsSeq[T]` into the yielded tuple.


## Fix
Change `accessTuple` to map plain `T` → `lent T`. Since `EcsSeq[T].[]` already returns `var T`, the compiler can borrow directly from archetype storage with no copy. Callers that need to store a value still can — they just copy explicitly.


## Notes
Verify that Nim supports `lent T` as a tuple field in an inline iterator yield, as `var T` is well-established for this pattern but `lent T` is less common.
