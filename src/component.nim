#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
type ComponentId* = distinct int

proc `$`*(id: ComponentId): string =
  $id.int
