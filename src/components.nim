#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
type Id* = object
  value*: int = -1


type ToRemoveEntity* = object
  id*: Id


type ToRemove*[T] = object
  discard
