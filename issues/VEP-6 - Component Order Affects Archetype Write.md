# VEP-6 - Component Order Affects Archetype Write
**Status:** Closed


## Bug
Adding an entity with components in a different order than the archetype's `componentIds` stores values in the wrong slots.

`(A(1), B(2))` and `(B(2), A(1))` produce the same `ArchetypeId` (it's a bitset), so they land in the same archetype. But `archetype.add[T: tuple]` writes each tuple field to `componentIds[index]` by tuple position, not by component identity. When the tuple order differs from `componentIds` order, values are crossed.

```nim
# archetype.componentIds = [idA, idB]
# tuple = (B(2), A(1))
# index=0 → writes B(2) into idA's slot
# index=1 → writes A(1) into idB's slot
```

Reproducer: [test/order.nim](../test/order.nim) — "be irrelevant for component values" fails with swapped values.


## Fix
In `archetype.add[T: tuple]`, look up each field's slot by component ID rather than by tuple index. Each field should be dispatched to `componentLists[componentIdOf(FieldType)]` directly, making write order independent of tuple order.
