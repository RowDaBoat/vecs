# VEP-7 - Entity Snapshots
**Status:** Closed


## Problem
There is no way to capture and restore the component state of a single entity — e.g. for undo, rollback, or trial moves. The snapshot must be fully opaque: callers never deal with component types after creation, and `restore` takes no type parameters at all.


## Solution
Extend the `Builder`/`Mover` registration pattern in `componentIdFrom` with a `Getter` — a proc registered per component type that captures a component value from an `EcsSeqAny` slot into an opaque single-element `EcsSeqAny`.

`Snapshot` is an opaque `ref object`. It captures all components of an entity (except `Meta`) at a point in time by iterating the entity's archetype and calling each component's snapper.

`restore` removes the target entity, recreates it with the same id, then adds all captured components back using the existing mover machinery.

```nim
proc snapshot*(world: var World, id: EntityId): Snapshot
proc restore*(world: var World, snapshot: Snapshot, id: EntityId = EntityId())
```


## Notes
- `Meta` is excluded; restoring it would corrupt entity identity and pending operations.
- Restoring a snapshot for a deleted entity is undefined behaviour.
- Passing an `id` to `restore` applies the snapshot onto a different entity — useful for copy/duplicate.
