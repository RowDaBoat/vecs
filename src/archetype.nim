import std/[macros, genasts, hashes, intsets]
import tables
import ecsSeq
import component

type ArchetypeId* = PackedSet[ComponentId]

proc hash*(id: ComponentId): Hash {.borrow.}
proc `==`*(a, b: ComponentId): bool {.borrow.}

type Archetype* = ref object
  id*: ArchetypeId
  componentIds*: seq[ComponentId]
  entityCount*: int
  componentLists*: Table[ComponentId, EcsSeqAny]

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

proc makeArchetype*(archetypeId: ArchetypeId, compIdsAndBuilders: seq[(ComponentId, proc(): EcsSeqAny)]): Archetype =
  var componentIds: seq[ComponentId] = @[]
  var componentLists = initTable[ComponentId, EcsSeqAny]()

  for (compId, builder) in compIdsAndBuilders:
    componentIds.add compId
    componentLists[compId] = builder()

  Archetype(
    id: archetypeId,
    componentIds: componentIds,
    componentLists: componentLists
  )

proc add*[T: tuple](archetype: var Archetype, components: sink T): int =
  var index = 0
  T.fieldTypes:
    let compId = archetype.componentIds[index]
    let ecsSeqAny = archetype.componentLists[compId]
    type Retype = EcsSeq[FieldType]

    for field in components.fields:
      when field is FieldType:
        cast[Retype](ecsSeqAny).add field

    result = cast[Retype](ecsSeqAny).len - 1
    inc index

  archetype.entityCount = result + 1

proc remove*(archetype: var Archetype, archetypeEntityId: int) =
  for components in archetype.componentLists.values:
    components.del archetypeEntityId

  archetype.entityCount = archetype.entityCount - 1

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
