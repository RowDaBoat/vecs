import tables, intsets
import entityid, archetype, ecsseq


type OperationKind* = enum
  RemoveEntity
  AddComponents
  RemoveComponents


type Operation* = object
  id*: EntityId
  case kind*: OperationKind:
  of RemoveEntity:
    discard
  of AddComponents:
    addersById*: Table[ComponentId, Adder]
  of RemoveComponents:
    compIdsToRemove*: PackedSet[ComponentId]
