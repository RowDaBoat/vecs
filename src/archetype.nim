import std/[macros, genasts, hashes, intsets]
import tables
import ecsSeq
import component

type ArchetypeId* = distinct uint64
type ArchetypeId2* = distinct IntSet

proc add*(id: ArchetypeId, compId: ComponentId): ArchetypeId =
  let bitId = 1.uint64 shl compId.int
  let newId = id.uint64 or bitId
  newId.ArchetypeId

proc `$`*(id: ArchetypeId): string =
  $id.uint64

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

proc makeArchetype*(archetypeId: ArchetypeId, builders: Table[ComponentId, proc(): EcsSeqAny]): Archetype =
  var componentIds: seq[ComponentId] = @[]
  var componentLists = initTable[ComponentId, EcsSeqAny]()

  for i in 0..<64: #TODO: change ArchetypeId to a PackedSet? have list of compid?
    if (archetypeId.uint64 and (1.uint64 shl i)) != 0:
      let compId = i.ComponentId
      componentIds.add compId
      componentLists[compId] = builders[compId]()

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
  (candidateId.uint64 and archetype.id.uint64) == candidateId.uint64

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
