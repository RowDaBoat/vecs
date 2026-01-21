#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import macros, tables, intsets
import archetype, ecsSeq


type Id* = object
  id*: int = -1


type OperationKind* = enum
  RemoveEntity
  AddComponents
  RemoveComponents


type Operation* = object
  case kind*: OperationKind:
  of RemoveEntity:
    discard
  of AddComponents:
    addersById*: Table[ComponentId, Adder]
  of RemoveComponents:
    compIdsToRemove*: PackedSet[ComponentId]


type OperationMode* = enum
  Immediate
  Deferred


type Meta* = object
  id*: Id
  operations: seq[Operation]


proc id*(meta: Meta): Id =
  meta.id


macro WithMeta*[T: tuple](t: typedesc[T]): typedesc =
  let tupleType = t.getTypeInst[^1]
  result = tupleType.copyNimTree
  result.insert(0, ident"Meta")


macro withMeta*[T: tuple](t: T): untyped =
  result = newNimNode(nnkTupleConstr)
  result.add newCall(ident"Meta")

  let typ = t.getTypeInst()

  for i in 0..<typ.len:
    result.add newTree(nnkBracketExpr, t, newLit(i))


proc enqueueOperation*(self: var Meta, operation: Operation) =
  self.operations.add operation


proc operations*(self: Meta): seq[Operation] =
  self.operations


proc clearOperations*(self: var Meta) =
  self.operations.setLen(0)
