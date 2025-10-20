import std/[packedsets, hashes, macros, intsets]
import typetraits
import tables
import archetype
import entity
import component
import ecsSeq
import queries/query
import queries/opNot
import queries/opWrite
import queries/opOpt

export Not, Write, Opt
export query.Query

type Id* = object
  id: int = -1

type World* = object
  entities: EcsSeq[Entity] = EcsSeq[Entity]()
  archetypeIds: seq[ArchetypeId] = @[]
  archetypes: Table[ArchetypeId, Archetype]
  builders: Table[ComponentId, Builder]
  movers: Table[ComponentId, Mover]
  showers: Table[ComponentId, Shower]
  nextComponentId: int

proc hash*(id: ArchetypeId): Hash =
  for compId in id.items:
    result = result xor (compId.int mod 32)

proc `==`*(a, b: ComponentId): bool {.borrow.}

proc nextArchetypeAddingFrom(world: var World, previousArchetype: Archetype, componentIdToAdd: ComponentId): var Archetype =
  let previousArchetypeId = previousArchetype.id
  var nextArchetypeId = previousArchetypeId
  nextArchetypeId.incl componentIdToAdd

  if not world.archetypes.hasKey(nextArchetypeId):
    let builder = world.builders[componentIdToAdd]
    let mover = world.movers[componentIdToAdd]
    let shower = world.showers[componentIdToAdd]

    world.archetypes[nextArchetypeId] = previousArchetype.makeNextAdding(@[componentIdToAdd], @[builder], @[mover], @[shower])
    world.archetypeIds.add nextArchetypeId

  world.archetypes[nextArchetypeId]

proc nextArchetypeRemovingFrom(world: var World, previousArchetype: Archetype, componentIdToRemove: ComponentId): var Archetype =
  let previousArchetypeId = previousArchetype.id
  var nextArchetypeId = previousArchetypeId
  nextArchetypeId.excl componentIdToRemove

  if not world.archetypes.hasKey(nextArchetypeId):
    world.archetypes[nextArchetypeId] = previousArchetype.makeNextRemoving(@[componentIdToRemove])
    world.archetypeIds.add nextArchetypeId

  world.archetypes[nextArchetypeId]

proc archetypeIdFrom[T: tuple](world: var World, desc: typedesc[T]): ArchetypeId =
  for name, typ in fieldPairs default T:
    let compId = world.componentIdFrom typeof typ
    result.incl compId

proc archetypeFrom[T: tuple](world: var World, tupleDesc: typedesc[T]): var Archetype =
  let archetypeId = world.archetypeIdFrom T

  if not world.archetypes.hasKey(archetypeId):
    var componentIds: seq[ComponentId] = @[]
    var builders: seq[Builder] = @[]
    var movers: seq[Mover] = @[]
    var showers: seq[Shower] = @[]

    for name, typ in fieldPairs default T:
      let compId = world.componentIdFrom typeof typ
      componentIds.add compId
      builders.add world.builders[compId]
      movers.add world.movers[compId]
      showers.add world.showers[compId]

    world.archetypes[archetypeId] = makeArchetype(componentIds, builders, movers, showers)
    world.archetypeIds.add archetypeId

  world.archetypes[archetypeId]


proc requireWrite[T](world: var World, write: Write[T]): ComponentId =
  world.componentIdFrom typeof T

proc excludeNot[T](world: var World, notOp: Not[T]): ComponentId =
  world.componentIdFrom typeof T

proc requiredArchetypeIdsFrom[T: tuple](world: var World, desc: typedesc[T]): ArchetypeId =
  for name, typ in fieldPairs default T:
    when typ is Not or typ is Opt:
      discard
    elif typ is Write:
      let compId = requireWrite(world, typ)
      result.incl compId
    else:
      let compId = world.componentIdFrom typeof typ
      result.incl compId

proc excludedArchetypeIdsFrom[T: tuple](world: var World, desc: typedesc[T]): ArchetypeId =
  for name, typ in fieldPairs default T:
    when typ is Not:
      let compId = excludeNot(world, typ)
      result.incl compId

proc updateQuery[T: tuple](world: var World, query: var Query[T]) =
  if world.archetypes.len == query.lastArchetypeCount:
    return

  let requiredArchetypeIds = world.requiredArchetypeIdsFrom T
  let excludedArchetypeIds = world.excludedArchetypeIdsFrom T

  for index in query.lastArchetypeCount ..< world.archetypeIds.len:
    let archetypeId = world.archetypeIds[index]
    let archetype = world.archetypes[archetypeId]

    if archetype.contains(requiredArchetypeIds) and archetype.disjointed(excludedArchetypeIds):
      query.matchedArchetypes.add archetypeId

  query.lastArchetypeCount = world.archetypes.len

proc isOp(typ: NimNode, name: string): bool =
  typ.kind == nnkBracketExpr and $typ[0] == name

macro accessTuple(t: typedesc): untyped =
  result = t.getTypeInst[^1].copyNimTree

  for i in countDown(result.len - 1, 0):
    if result[i].kind == nnkBracketExpr and result[i][0] == bindSym"Not":
      result.del(i)

  for i, x in result:
    if x.kind == nnkBracketExpr and result[i][0] == bindSym"Write":
      echo "write: ", repr x[1]
      result[i] = nnkVarTy.newTree(x[1])
      echo "res i: ", repr result[i]
  result = newCall("typeof", result)

template accessor[T](world: var World, archetype: Archetype, archetypeEntityId: int): T =
  cast[EcsSeq[T]](
    archetype.componentLists[world.componentIdFrom typeof T]
  )[archetypeEntityId]

macro buildAccessTuple(world: var World, t: typedesc, archetype: untyped, archetypeEntityId: untyped): untyped =
  let tupleType = t.getTypeInst[^1]
  var tupleExprs = nnkTupleConstr.newTree()

  for i in countDown(tupleType.len - 1, 0):
    if isOp(tupleType[i], "Not"):
      tupleType.del(i)

  for i in 0..<tupleType.len:
    let fieldType = tupleType[i]
    let fieldExpr =
      if isOp(fieldType, "Write"):
        let componentType = fieldType[1]
        quote do:
          accessor[`componentType`](world, `archetype`, `archetypeEntityId`)
      elif isOp(fieldType, "Opt"):
        let componentType = fieldType[1]
        quote do:
          if `archetype`.contains(world.componentIdFrom typeof `componentType`):
            some(accessor[`componentType`](world, `archetype`, `archetypeEntityId`))
          else:
            none[`componentType`]()
      else:
        let componentType = fieldType
        quote do:
          accessor[`componentType`](world, `archetype`, `archetypeEntityId`)

    tupleExprs.add(fieldExpr)

  result = tupleExprs

iterator archetypes*(world: var World): Archetype =
  for archetypeId in world.archetypeIds:
    yield world.archetypes[archetypeId]

proc componentIdFrom*[T](world: var World, desc: typedesc[T]): ComponentId =
  var id {.global.}: int
  once:
    id = world.nextComponentId
    inc world.nextComponentId

  if not world.builders.hasKey(id.ComponentId):
    world.builders[id.ComponentId] = ecsSeqBuilder[T]()
    world.movers[id.ComponentId] = ecsSeqMover[T]()
    world.showers[id.ComponentId] = ecsSeqShower[T]()

  id.ComponentId

proc hasComponent*[T](world: var World, id: Id, compDesc: typedesc[T]): bool =
  let entity = world.entities[id.id]
  let compId = world.componentIdFrom typeof compDesc
  compId in entity.archetypeId

iterator component*[T](world: var World, id: Id, compDesc: typedesc[T]): var T =
  let entity = world.entities[id.id]
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId
  let compId = world.componentIdFrom typeof compDesc

  if archetype.componentLists.hasKey(compId):
    let ecsSeqAny = archetype.componentLists[compId]
    type Retype = EcsSeq[T]
    yield cast[Retype](ecsSeqAny)[archetypeEntityId]

iterator components*[T: tuple](world: var World, id: Id, tup: typedesc[T]): tup.accessTuple =
  let entity = world.entities[id.id]
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId

  var found = true

  tup.fieldTypes:
    let compId = world.componentIdFrom typeof FieldType
    found = found and archetype.componentLists.hasKey(compId)

  if found:
    yield world.buildAccessTuple(tup, archetype, archetypeEntityId)

proc addEntity*[T: tuple](world: var World, components: T): Id {.discardable.} =
  var archetype = world.archetypeFrom T
  let archetypeEntityId = archetype.add components
  let id = world.entities.add Entity(archetypeId: archetype.id, archetypeEntityId: archetypeEntityId)
  result = Id(id: id)

  for idComponent in world.component(result, Id):
    idComponent.id = id

proc removeEntity*(world: var World, id: Id) =
  let entity = world.entities[id.id]
  var archetype = world.archetypes[entity.archetypeId]
  archetype.remove entity.archetypeEntityId
  world.entities.del id.id

proc addComponent*[T](world: var World, id: Id, component: T) =
  var entity = world.entities[id.id]
  let componentId = world.componentIdFrom typeof T

  if entity.archetypeId.contains(componentId):
    raise newException(ValueError, "Component " & $T & " already exists in Entity " & $id)

  var previousArchetype = world.archetypes[entity.archetypeId]
  var nextArchetype = world.nextArchetypeAddingFrom(previousArchetype, componentId)

  let idAdder = proc(ecsSeq: var EcsSeqAny): int =
    cast[EcsSeq[Id]](ecsSeq).add id

  let adder = proc(ecsSeq: var EcsSeqAny): int =
    cast[EcsSeq[T]](ecsSeq).add component

  var adders = initTable[ComponentId, Adder]()
  adders[componentId] = if T is Id: idAdder else: adder

  entity.archetypeId = nextArchetype.id
  entity.archetypeEntityId = previousArchetype.moveAdding(entity.archetypeEntityId, nextArchetype, adders)

proc removeComponent*[T](world: var World, id: Id, compDesc: typedesc[T]) =
  var entity = world.entities[id.id]
  let componentId = world.componentIdFrom typeof T

  if not entity.archetypeId.contains(componentId):
    raise newException(ValueError, "Component " & $T & " not found in Entity " & $id)

  var previousArchetype = world.archetypes[entity.archetypeId]
  var nextArchetype = world.nextArchetypeRemovingFrom(previousArchetype, componentId)

  entity.archetypeId = nextArchetype.id
  entity.archetypeEntityId = previousArchetype.moveRemoving(entity.archetypeEntityId, nextArchetype)
  world.entities[id.id] = entity

iterator query*[T: tuple](world: var World, query: var Query[T]): T.accessTuple =
  world.updateQuery(query)

  for archetypeId in query.matchedArchetypes:
    let archetype = world.archetypes[archetypeId]
    for archetypeEntityId in archetype.entities:
      yield world.buildAccessTuple(typeof T, archetype, archetypeEntityId)
