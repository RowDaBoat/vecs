#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import archetype

type Entity* = object
  archetypeId*: ArchetypeId
  archetypeEntityId*: int
