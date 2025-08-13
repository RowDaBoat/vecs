import std/[macros, genasts, hashes]
import tables
import ecsSeq
import component

type ArchetypeId* = distinct uint64

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

proc archetypeIdFrom*[T: tuple](desc: typedesc[T]): ArchetypeId =
  var id = 0.uint64
  for name, typ in fieldPairs default T:
    let compId = componentIdFrom typeof typ
    id = id or (1.uint64 shl compId.int)
  id.ArchetypeId

proc makeArchetype*[T: tuple](tup: typedesc[T]): Archetype =
  let archetypeId = archetypeIdFrom T
  var componentLists = initTable[ComponentId, EcsSeqAny]()

  tup.fieldTypes:
    let compId = componentIdFrom FieldType
    componentLists[compId] = EcsSeq[FieldType]()

  Archetype(
    id: archetypeId,
    componentLists: componentLists
  )

proc add*[T: tuple](archetype: var Archetype, components: sink T): int =
  T.fieldTypes:
    let compId = componentIdFrom FieldType
    let ecsSeqAny = archetype.componentLists[compId]
    type Retype = EcsSeq[FieldType]

    for field in components.fields:
      when field is FieldType:
        cast[Retype](ecsSeqAny).add field

    result = cast[Retype](ecsSeqAny).len - 1

  archetype.entityCount = result + 1

proc remove*(archetype: var Archetype, archetypeEntityId: int) =
  for components in archetype.componentLists.values:
    components.del archetypeEntityId

  archetype.entityCount = archetype.entityCount - 1

proc matches*[T: tuple](archetype: Archetype, tup: typedesc[T]): bool =
  let candidateId = archetypeIdFrom tup
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
