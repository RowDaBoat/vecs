# VEP-1 - vec's queryForRemoval Copies All Components
**Status:** Closed


## Bug
`queryForRemoval[T]` calls `world.query((Meta, T))` internally, yielding full value copies of every matching `T` component to filter by `meta.operations`. This causes O(n) component copies per frame regardless of pending removals. For large components like `Texture` (~13ms per 960×540 entity per frame).


## Fix
Inspect `meta.operations` without fetching `T`. Only retrieve component data for entities that actually have a pending removal operation.
