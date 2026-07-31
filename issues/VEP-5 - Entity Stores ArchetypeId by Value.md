# VEP-5 - Storing ArchetypeId by Value causes heap allocations
**Status:** Closed


## Bug
`Entity` holds `archetypeId: ArchetypeId` inline, where `ArchetypeId = PackedSet[ComponentId]`.
`PackedSet` is a value type with internal heap allocations (`seq[Trunk[A]]`). Every entity in `EcsSeq[Entity]` materializes its own heap allocation for the set's trunk data, even when all entities in an archetype share an identical set.
This causes unbounded memory growth proportional to entity count rather than archetype count.


## Fix
Replace `PackedSet[ComponentId]` with a stack-allocated `array[N, uint64]` bitset where `N = 1 + ArchetypeWords` and `ArchetypeWords` is an `{.intdefine.}` compile-time constant (default `1`, i.e. 64 components). Bitwise ops replace set ops. Multi-word `contains` and `disjointed` are unrolled via a local `unroll` macro.
