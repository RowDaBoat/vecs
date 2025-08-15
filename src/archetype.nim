import std/[macros, genasts, hashes, intsets]
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
  entityCount*: int
  componentLists*: Table[ComponentId, EcsSeqAny]
  builders: seq[Builder]
  movers: seq[Mover]

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

proc makeArchetype*(compIds: seq[ComponentId], builders: seq[Builder], movers: seq[Mover]): Archetype =
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
    movers: movers
  )

proc makeNextAdding*(archetype: Archetype, compIds: seq[ComponentId], builders: seq[Builder], movers: seq[Mover]): Archetype =
  let newCompIds = archetype.componentIds & compIds
  let newBuilders = archetype.builders & builders
  let newMovers = archetype.movers & movers
  makeArchetype(newCompIds, newBuilders, newMovers)

proc makeNextRemoving*(archetype: Archetype, compIds: seq[ComponentId]): Archetype =
  var newCompIds: seq[ComponentId] = @[]
  var newBuilders: seq[Builder] = @[]
  var newMovers: seq[Mover] = @[]

  for index in 0..<compIds.len:
    let compId = compIds[index]
    let builder = archetype.builders[index]
    let mover = archetype.movers[index]

    if compId notin archetype.id:
      raise newException(ValueError, "Component " & $compId & " not in archetype")

    newCompIds.add compId
    newBuilders.add builder
    newMovers.add mover

  makeArchetype(newCompIds, newBuilders, newMovers)

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

  inc archetype.entityCount

proc add*(archetype: var Archetype, adders: Table[ComponentId, Adder]): int =
  for compId, adder in adders.pairs:
    result = adder(archetype.componentLists[compId])

  inc archetype.entityCount

proc remove*(archetype: var Archetype, archetypeEntityId: int) =
  for components in archetype.componentLists.values:
    components.del archetypeEntityId

  dec archetype.entityCount

proc move*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype, adders: Table[ComponentId, Adder]): int =
  for index in 0..<fromArchetype.componentIds.len:
    let compId = fromArchetype.componentIds[index]
    let mover = fromArchetype.movers[index]
    var fromEcsSeq = fromArchetype.componentLists[compId]
    var toEcsSeq = toArchetype.componentLists[compId]
    result = mover(fromEcsSeq, fromArchetypeEntityId, toEcsSeq)

  for compId, adder in adders.pairs:
    assert result == adder(toArchetype.componentLists[compId])

  dec fromArchetype.entityCount
  inc toArchetype.entityCount

proc matches*(archetype: Archetype, candidateId: ArchetypeId): bool =
  candidateId <= archetype.id

proc `$`*(componentLists: Table[ComponentId, EcsSeqAny]): string =
  result &= "@{\n"
  for (compId, ecsSeqAny) in componentLists.pairs:
    result &= "        " & $compId & ": components" & "\n"
  result &= "      }"

proc `$`*(archetype: Archetype): string =
  "(\n" &
  "      id: " & $archetype.id & "\n" &
  "      entityCount: " & $archetype.entityCount & "\n" &
  "      componentLists: " & $archetype.componentLists & "\n" &
  "    )"
