#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import components
import archetype


type OperationKind* = enum AddEntity, RemoveEntity, AddComponent, RemoveComponent


type Operation* = object
  id*: Id
  case kind*: OperationKind
  of AddEntity:
    discard
  of RemoveEntity:
    discard
  of AddComponent:
    discard
  of RemoveComponent:
    componentId*: ComponentId
