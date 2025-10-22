#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import ../archetype

type Query*[T: tuple] = object
  matchedArchetypes*: seq[ArchetypeId]
  lastArchetypeCount*: int
