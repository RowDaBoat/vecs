# VEP-8 - Adding Worlds
**Status:** Closed


## Problem
Entities cannot be moved between `World`s. `Id[T]` and `EntityId` are indices into one specific world's storage, so a component copied verbatim into another world keeps references that dangle, or worse, resolve to unrelated entities once the destination hands out its own ids.

Serialization does not help: it round-trips faithfully, but `deserializeFromBinary` always builds a fresh `World`. A deserialized world cannot be merged into an existing one, and part of a world cannot be lifted out into a world of its own.

Both directions are needed:
- merging a whole world into a populated one, e.g. after deserializing it.
- copying a subset of a world into another, e.g. to serialize that subset on its own.


## Solution
`add` copies entities from one world into another, remapping references as it goes.

```nim
proc add*[T: tuple](
  world: var World,
  other: var World,
  components: typedesc[T]
): Table[EntityId, EntityId] {.discardable.}

proc add*[T: tuple](
  world: var World,
  other: var World,
  ids: seq[EntityId],
  components: typedesc[T]
): Table[EntityId, EntityId] {.discardable.}
```

The first form adds every entity in `other`, the second only the given `ids`.

1. Select the source entities.
2. Create an empty entity in `world` for each one, recording `other`'s id -> `world`'s new id.
3. Copy the components listed in `components` onto each counterpart.
4. Walk every copied component and rewrite its `EntityId` and `Id[T]` fields: ids found in the map become the mapped id, ids not in the map become invalid.

Steps 2 and 3 must not be interleaved: the map has to be complete before anything is rewritten, or forward references break.

The id map is returned so callers can find what was just added.

`other` is left unchanged. It is `var` only because reading components requires it.


## Explicit Components
The caller lists the components to copy instead of the whole set being copied automatically.

Not every component is authored data. Some are derived: systems build them from other components, and they can hold resources owned by the world that created them. Copying those would duplicate state the destination was supposed to rebuild for itself, and hand it a resource it does not own.

The caller knows which components are authoring data and which are derived, so it names them. A whitelist also fails closed: a missing component is visible and recoverable, whereas copying everything silently duplicates state that was never meant to be shared.


## Id Rewriting
Rewriting needs the same traversal serialization uses: walk each whitelisted component's fields, descending into nested objects, `seq`s and fixed size arrays, rewriting every `EntityId` and `Id[T]` found.

`Meta` is never copied or rewritten. `Meta.id` is the counterpart's own new id, not a remapped one.


## Notes
- Entities whose components are all outside the whitelist arrive holding only `Meta`. They are not pruned: doing so would add a special case and change which ids stay valid, in exchange for nothing.
- Component types are named explicitly by the caller for now. Marking them at their declaration, so the set cannot drift out of sync, is left for a later VEP.


## Implementation
`src/addworld.nim`. Two details turned out simpler than this document originally anticipated:
- **No `Builder`/`Mover`/`Getter` transfer is needed.** The concern was that a component type the destination has never seen would have no registered procs, so copying it would index past the end of those seqs. It never arises: `copyComponents` walks the whitelist tuple and reads and writes each component *typed*, so `destination.add(destinationId, component, Immediate)` registers the type on the destination itself, the same way any first use of a component type does.
- **[VEP-7](VEP-7%20-%20Entity%20Snapshots.md)'s machinery is not reused.** A `Snapshot` is opaque and type erased, which is exactly wrong here: `remapIds` needs the concrete type to find the `EntityId`/`Id[T]` fields. Copying through typed reads and writes keeps the type available where the rewriting happens.

It lives in its own module rather than in `world.nim` or `id.nim`, because `remapIds` needs `Id` while `id.nim` already imports `world.nim`, so either placement would cycle.

`remapIds` is a third field walker, alongside the two in `serialization.nim`. They were kept separate deliberately: each visits the same shapes but does something different at the leaves, and only serialization's pair has to agree with each other on a wire format.


## References
[VEP-7 - Entity Snapshots](VEP-7%20-%20Entity%20Snapshots.md)
