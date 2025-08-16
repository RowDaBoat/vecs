import std/[macros, genasts, hashes, intsets, sets]
import tables
import ecsSeq
import component

type ArchetypeId* = PackedSet[ComponentId]

proc archetypeIdFrom*(compIds: seq[ComponentId]): ArchetypeId =
  for compId in compIds:
    result.incl compId

proc hash*(id: ComponentId): Hash {.borrow.}
proc `==`*(a, b: ComponentId): bool {.borrow.}

type Archetype* = ref object
  id*: ArchetypeId
  componentIds*: seq[ComponentId]
  #entityCount*: int
  componentLists*: Table[ComponentId, EcsSeqAny]
  builders: seq[Builder]
  movers: seq[Mover]
  showers: seq[Shower]

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

proc makeArchetype*(compIds: seq[ComponentId], builders: seq[Builder], movers: seq[Mover], showers: seq[Shower]): Archetype =
  let archetypeId = archetypeIdFrom compIds
  var componentIds: seq[ComponentId] = @[]
  var componentLists = initTable[ComponentId, EcsSeqAny]()

  for index in 0..<compIds.len:
    let compId = compIds[index]
    componentIds.add compId
    componentLists[compId] = builders[index]()

  Archetype(
    id: archetypeId,
    componentIds: componentIds,
    componentLists: componentLists,
    builders: builders,
    movers: movers,
    showers: showers
  )

proc makeNextAdding*(archetype: Archetype, compIds: seq[ComponentId], builders: seq[Builder], movers: seq[Mover], showers: seq[Shower]): Archetype =
  let newCompIds = archetype.componentIds & compIds
  let newBuilders = archetype.builders & builders
  let newMovers = archetype.movers & movers
  let newShowers = archetype.showers & showers
  makeArchetype(newCompIds, newBuilders, newMovers, newShowers)

proc makeNextRemoving*(archetype: Archetype, compIds: seq[ComponentId]): Archetype =
  var newCompIds: seq[ComponentId] = @[]
  var newBuilders: seq[Builder] = @[]
  var newMovers: seq[Mover] = @[]
  var newShowers: seq[Shower] = @[]
  let toRemove = compIds.toHashSet

  for index in 0..<archetype.componentIds.len:
    let compId = archetype.componentIds[index]
    if (not toRemove.contains(compId)):
      newCompIds.add compId
      newBuilders.add archetype.builders[index]
      newMovers.add archetype.movers[index]
      newShowers.add archetype.showers[index]

  makeArchetype(newCompIds, newBuilders, newMovers, newShowers)

iterator entities*(archetype: Archetype): int =
  let firstCompId = archetype.componentIds[0]
  let firstComponentList = archetype.componentLists[firstCompId]
  for index in firstComponentList.ids:
    yield index

proc add*[T: tuple](archetype: var Archetype, components: sink T): int =
  var index = 0
  T.fieldTypes:
    let compId = archetype.componentIds[index]
    let ecsSeqAny = archetype.componentLists[compId]
    type Retype = EcsSeq[FieldType]

    for field in components.fields:
      when field is FieldType:
        result = cast[Retype](ecsSeqAny).add field

    inc index

  #inc archetype.entityCount

proc add*(archetype: var Archetype, adders: Table[ComponentId, Adder]): int =
  for compId, adder in adders.pairs:
    result = adder(archetype.componentLists[compId])

  #inc archetype.entityCount

proc remove*(archetype: var Archetype, archetypeEntityId: int) =
  for components in archetype.componentLists.values:
    components.del archetypeEntityId

  #dec archetype.entityCount

proc moveAdding*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype, adders: Table[ComponentId, Adder]): int =
  for index in 0..<fromArchetype.componentIds.len:
    let compId = fromArchetype.componentIds[index]
    let mover = fromArchetype.movers[index]
    var fromEcsSeq = fromArchetype.componentLists[compId]
    var toEcsSeq = toArchetype.componentLists[compId]
    result = mover(fromEcsSeq, fromArchetypeEntityId, toEcsSeq)

  for compId, adder in adders.pairs:
    assert result == adder(toArchetype.componentLists[compId])

  #dec fromArchetype.entityCount
  #inc toArchetype.entityCount

proc moveRemoving*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype): int =
  for index in 0..<fromArchetype.componentIds.len:
    let compId = fromArchetype.componentIds[index]
    var fromEcsSeq = fromArchetype.componentLists[compId]

    if (toArchetype.id.contains compId):
      let mover = fromArchetype.movers[index]
      var toEcsSeq = toArchetype.componentLists[compId]
      result = mover(fromEcsSeq, fromArchetypeEntityId, toEcsSeq)
    else:
      fromEcsSeq.del fromArchetypeEntityId

  #dec fromArchetype.entityCount
  #inc toArchetype.entityCount

proc matches*(archetype: Archetype, candidateId: ArchetypeId): bool =
  candidateId <= archetype.id

proc show*(archetype: Archetype, componentLists: Table[ComponentId, EcsSeqAny]): string =
  result &= "@{\n"
  var index = 0
  for (compId, ecsSeqAny) in componentLists.pairs:
    result &= "        " & $compId & ": components" & "\n"
    inc index

  result &= "      }"

proc `$`*(archetype: Archetype): string =
  "(\n" &
  "      id: " & $archetype.id & "\n" &
  "      componentIds: " & $archetype.componentIds & "\n" &
  #"      entityCount: " & $archetype.entityCount & "\n" &
  "      componentLists: " & archetype.show(archetype.componentLists) & "\n" &
  "    )"
