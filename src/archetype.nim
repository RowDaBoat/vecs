# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import std/[macros, genasts, hashes, sets]
import tables
import ecsseq
import componentid, archetypeid

const CHECKS_ENABLED = not defined(danger)


type Archetype* = ref object
  id*: ArchetypeId
  componentIds*: seq[ComponentId]
  toIndexMap*: seq[uint16]
  componentLists*: seq[EcsSeqAny]
  deleted*: seq[bool]
  free*: seq[int]
  builders: seq[Builder]


proc hasKey*(archetype: Archetype, comp: ComponentId): bool =
  let id = comp.int
  return id < archetype.toIndexMap.len and archetype.toIndexMap[id] != 0


proc getIndex*(archetype: Archetype, comp: ComponentId): uint16 =
  return archetype.toIndexMap[comp.int] - 1


macro fieldTypes*(tup: typed, body: untyped): untyped =
  result = newStmtList()
  let tup =
    if tup.kind != nnkTupleConstr:
      tup.getTypeInst[^1]
    else:
      tup

  for x in tup:
    let body = body.copyNimTree()
    body.insert 0:
      genast(x):
        type FieldType {.inject.} = x
    result.add nnkIfStmt.newTree(nnkElifBranch.newTree(newLit(true), body))
  result = nnkBlockStmt.newTree(newEmptyNode(), result)


proc makeArchetype*(componentIds: seq[ComponentId], builders: seq[Builder]): Archetype =
  let archetypeId = archetypeIdFrom componentIds
  var toIndexMap: seq[uint16]
  var componentLists: seq[EcsSeqAny]

  for index in 0..<componentIds.len:
    let componentId = componentIds[index]
    if componentId.int >= toIndexMap.len:
      toIndexMap.setLen(componentId.int + 1)

    toIndexMap[componentId.int] = componentLists.len.uint16 + 1
    componentLists.add builders[index]()

  Archetype(
    id: archetypeId,
    toIndexMap: toIndexMap,
    componentIds: componentIds,
    componentLists: componentLists,
    deleted: @[],
    free: @[],
    builders: builders,
  )


proc makeNextAdding*(archetype: Archetype, compIds: seq[ComponentId], builders: seq[Builder]): Archetype =
  let newCompIds = archetype.componentIds & compIds
  let newBuilders = archetype.builders & builders
  makeArchetype(newCompIds, newBuilders)


proc makeNextRemoving*(archetype: Archetype, compIds: seq[ComponentId]): Archetype =
  var newCompIds: seq[ComponentId] = @[]
  var newBuilders: seq[Builder] = @[]
  let toRemove = compIds.toHashSet

  for index in 0..<archetype.componentIds.len:
    let compId = archetype.componentIds[index]
    if not toRemove.contains(compId):
      newCompIds.add compId
      newBuilders.add archetype.builders[index]

  makeArchetype(newCompIds, newBuilders)


proc allocateSlot(archetype: Archetype): int =
  if archetype.free.len > 0:
    result = archetype.free.pop()
    archetype.deleted[result] = false
  else:
    result = archetype.deleted.len
    archetype.deleted.add false


iterator entities*(archetype: Archetype): int =
  if archetype.free.len == 0:
    for index in 0..<archetype.deleted.len:
      yield index
  else:
    for index in 0..<archetype.deleted.len:
      if not archetype.deleted[index]:
        yield index


iterator components*[T](archetype: Archetype, componentId: ComponentId): T =
  let index = archetype.getIndex(componentId)
  let ecsSeq = archetype.componentLists[index]
  for entityId in archetype.entities:
    yield cast[EcsSeq[T]](ecsSeq)[entityId]


template addField[T](ecsSeqAny: EcsSeqAny, slot: int, item: sink T) =
  cast[EcsSeq[T]](ecsSeqAny).addAt(slot, item)


proc add*[T: tuple](archetype: var Archetype, components: T): int =
  let slot = archetype.allocateSlot()

  for name, field in fieldPairs components:
    let componentId = (typeof field).toComponentId
    let index = archetype.getIndex(componentId)
    addField(archetype.componentLists[index], slot, field)

  result = slot


proc add*(archetype: var Archetype, adders: Table[ComponentId, AddItemAny]): int =
  let slot = archetype.allocateSlot()

  for compId, adder in adders.pairs:
    let index = archetype.getIndex(compId)
    archetype.componentLists[index].addAt(slot, cast[ptr byte](adder.raw))

  result = slot


proc remove*(archetype: var Archetype, archetypeEntityId: int) =
  archetype.deleted[archetypeEntityId] = true
  archetype.free.add archetypeEntityId


proc moveAddingTuple*[T: tuple](fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype, components: T): int =
  let toSlot = toArchetype.allocateSlot()
  for index in 0..<fromArchetype.componentIds.len:
    let compId = fromArchetype.componentIds[index]
    let toIndex = toArchetype.getIndex(compId)

    var fromEcsSeq = fromArchetype.componentLists[index]
    var toEcsSeq = toArchetype.componentLists[toIndex]
    moveEcsSeq(fromEcsSeq, fromArchetypeEntityId, toEcsSeq, toSlot)

  for name, value in fieldPairs components:
    let compId = (typeof value).toComponentId
    let toIndex = toArchetype.getIndex(compId)
    var toEcsSeq = toArchetype.componentLists[toIndex]
    var val = value
    toEcsSeq.addAt(toSlot, cast[ptr byte](addr val))
      
  fromArchetype.remove(fromArchetypeEntityId)
  toSlot


proc moveAdding*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype, componentsToAdd: Table[ComponentId, AddItemAny]): int =
  let toSlot = toArchetype.allocateSlot()
  for index in 0..<fromArchetype.componentIds.len:
    let compId = fromArchetype.componentIds[index]
    let toIndex = toArchetype.getIndex(compId)

    var fromEcsSeq = fromArchetype.componentLists[index]
    var toEcsSeq = toArchetype.componentLists[toIndex]
    moveEcsSeq(fromEcsSeq, fromArchetypeEntityId, toEcsSeq, toSlot)

  for compId, item in componentsToAdd.pairs:
    let toIndex = toArchetype.getIndex(compId)
    var toEcsSeq = toArchetype.componentLists[toIndex]
    toEcsSeq.addAt(toSlot, cast[ptr byte](item.raw))
    
  fromArchetype.remove(fromArchetypeEntityId)
  result = toSlot


proc moveRemoving*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype): int =
  let toSlot = toArchetype.allocateSlot()

  for index in 0..<fromArchetype.componentIds.len:
    let compId = fromArchetype.componentIds[index]
    var fromEcsSeq = fromArchetype.componentLists[index]

    if toArchetype.id.contains compId:
      let toIndex = toArchetype.getIndex(compId)
      var toEcsSeq = toArchetype.componentLists[toIndex]
      moveEcsSeq(fromEcsSeq, fromArchetypeEntityId, toEcsSeq, toSlot)
      
  fromArchetype.remove(fromArchetypeEntityId)
  result = toSlot


proc contains*(archetype: Archetype, candidateId: ComponentId): bool =
  candidateId in archetype.id


proc contains*(archetype: Archetype, candidateId: ArchetypeId): bool =
  archetype.id.contains candidateId


proc disjointed*(archetype: Archetype, candidateId: ArchetypeId): bool =
  archetype.id.disjointed candidateId


proc len*(archetype: Archetype): int =
  archetype.deleted.len - archetype.free.len


proc isEmpty*(archetype: Archetype): bool =
  archetype.len == 0
