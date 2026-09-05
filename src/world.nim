# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import std/[packedsets, hashes, macros, intsets, options]
import typetraits, tables, sets
import entityid, componentid, archetypeid, archetype, entity, ecsseq, queries, components, operations, operationmodes, events
export entityid, components.Meta, operationmodes
export components
export events

const CHECKS_ENABLED = not defined(danger)

type World* = object
  entities: seq[Entity] = @[]
  generations: seq[int] = @[]
  entityFree: seq[int] = @[]
  archIdToIndex: Table[ArchetypeId, int]
  freeArchetype: seq[int]
  archetypes: seq[Archetype]
  builders: seq[Builder] = newSeq[Builder](componentid.ArchetypeWords*sizeof(uint64)*8)
  getters: seq[Getter] = newSeq[Getter](componentid.ArchetypeWords*sizeof(uint64)*8)
  toConsolidate: HashSet[EntityId]
  version: int = 0
  eventQueues: Table[EventKind, EventQueueBase]


type Snapshot* = ref object
  entityId: EntityId
  componentData: Table[ComponentId, EcsSeqAny]


type DoubleAddDefect* = object of Defect


proc `==`*(a, b: ComponentId): bool {.borrow.}


# Errors
proc idIsInvalid(id: EntityId): ref Exception =
  newException(Exception, "Id is invalid: " & $id)


proc entityDoesNotExist(id: EntityId): ref Exception =
  newException(Exception, "Entity with id " & $id & " does not exist.")


proc componentDoesNotExist[T](id: EntityId, comp: typedesc[T]): ref Exception =
  newException(Exception, "Component " & $comp & " does not exist in the entity with id " & $id)


proc componentsDoNotExist[T: tuple](id: EntityId, tup: typedesc[T]): ref Exception =
  newException(Exception, "One or more components of " & $tup & " do not exist in the entity with id " & $id)


proc entityAlreadyExists(id: EntityId): ref Exception =
  newException(Exception, "Entity with id " & $id & " already exists.")


# Checks
proc checkIdIsValid(id: EntityId) =
  when CHECKS_ENABLED:
    if not id.isValid:
      raise idIsInvalid(id)


template checkNotATuple[T](tup: typedesc[T]) =
  when T is tuple:
    {.error: "Component type expected, got a tuple: " & $T.}


proc has*(world: var World, id: EntityId): bool =
  ## Check if an entity exists.
  id.isValid and
  id.value < world.generations.len and
  world.generations[id.value] == id.generation


proc allocateEntity(world: var World, entity: Entity): EntityId =
  if world.entityFree.len > 0:
    let id = world.entityFree.pop()
    world.entities[id] = entity
    result = newEntityId(world.generations[id], id)
  else:
    let id = world.entities.len
    world.generations.add 0
    world.entities.add entity
    result = newEntityId(0, id)


proc deleteEntity(world: var World, id: EntityId) =
  inc world.generations[id.value]
  world.entityFree.add id.value


proc setEntityAt(world: var World, id: EntityId, entity: Entity) =
  if id.value >= world.entities.len:
    let oldLen = world.entities.len
    world.entities.setLen(id.value + 1)
    world.generations.setLen(id.value + 1)

    for i in oldLen ..< id.value:
      world.generations[i] = 1
      world.entityFree.add i

  let freeIndex = world.entityFree.find(id.value)
  if freeIndex >= 0:
    world.entityFree.del(freeIndex)

  world.entities[id.value] = entity
  world.generations[id.value] = id.generation


proc checkEntityExists(world: var World, id: EntityId) =
  when CHECKS_ENABLED:
    if not world.has(id):
      raise entityDoesNotExist(id)


proc checkEntityDoesNotExist(world: var World, id: EntityId) =
  when CHECKS_ENABLED:
    if world.has(id):
      raise entityAlreadyExists(id)


# Archetype creation and book-keeping
proc registerArchetype(world: var World, archetypeId: ArchetypeId, archetype: Archetype) =
  if world.freeArchetype.len > 0:
    let recycledIndex = world.freeArchetype.pop

    world.archIdToIndex[archetypeId] = recycledIndex
    world.archetypes[recycledIndex] = archetype
    inc world.version
  else:
    world.archIdToIndex[archetypeId] = world.archetypes.len
    world.archetypes.add archetype


proc nextArchetypeAddingFrom(world: var World, previousArchetype: Archetype, componentIdsToAdd: seq[ComponentId]): int =
  let previousArchetypeId = previousArchetype.id
  var nextArchetypeId = previousArchetypeId

  for componentId in componentIdsToAdd:
    nextArchetypeId.incl componentId

  result = world.archIdToIndex.getOrDefault(nextArchetypeId, -1)

  if result < 0:
    var builders: seq[Builder] = @[]

    for componentId in componentIdsToAdd:
      builders.add world.builders[componentId.uint]

    let newArchetype = previousArchetype.makeNextAdding(componentIdsToAdd, builders)
    world.registerArchetype(nextArchetypeId, newArchetype)

    result = world.archIdToIndex[nextArchetypeId]


proc nextArchetypeRemovingFrom(world: var World, previousArchetype: Archetype, componentIdsToRemove: seq[ComponentId]): int =
  let previousArchetypeId = previousArchetype.id
  var nextArchetypeId = previousArchetypeId

  for componentId in componentIdsToRemove:
    nextArchetypeId.excl componentId

  result = world.archIdToIndex.getOrDefault(nextArchetypeId, -1)

  if result < 0:
    let newArchetype = previousArchetype.makeNextRemoving(componentIdsToRemove)
    world.registerArchetype(nextArchetypeId, newArchetype)

    result = world.archIdToIndex[nextArchetypeId]

proc archetypeIdFrom[T: tuple](world: var World, desc: typedesc[T]): ArchetypeId =
  for name, typ in fieldPairs default T:
    let compId = world.componentIdFrom typeof typ
    result.incl compId


proc archetypeFrom[T: tuple](world: var World, tupleDesc: typedesc[T]): int =
  let archetypeId = world.archetypeIdFrom T
  result = world.archIdToIndex.getOrDefault(archetypeId, -1)

  if result < 0:
    var componentIds: seq[ComponentId] = @[]
    var builders: seq[Builder] = @[]

    for name, typ in fieldPairs default T:
      let componentId = world.componentIdFrom typeof typ
      componentIds.add componentId
      builders.add world.builders[componentId.int]

    let newArchetype = makeArchetype(componentIds, builders)
    world.registerArchetype(archetypeId, newArchetype)

    result = world.archIdToIndex[archetypeId]


# Query creation and book-keeping
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


proc matchArchetypeAt[T: tuple](
    world: var World,
    query: var Query[T],
    index: int,
    requiredArchetypeIds: ArchetypeId,
    excludedArchetypeIds: ArchetypeId
) =
  let archetype = world.archetypes[index]

  if archetype.isNil:
    return

  if not archetype.contains(requiredArchetypeIds):
    return

  if not archetype.disjointed(excludedArchetypeIds):
    return

  query.matchedArchetypes.add index


proc updateQuery[T: tuple](world: var World, query: var Query[T]) =
  if world.version > query.lastVersion:
    query.reset(world.version)
  elif world.archetypes.len == query.lastArchetypeCount:
    return

  let requiredArchetypeIds = world.requiredArchetypeIdsFrom T
  let excludedArchetypeIds = world.excludedArchetypeIdsFrom T

  for index in query.lastArchetypeCount ..< world.archetypes.len:
    world.matchArchetypeAt(query, index, requiredArchetypeIds, excludedArchetypeIds)

  query.lastArchetypeCount = world.archetypes.len


proc isOp(typ: NimNode, name: string): bool =
  typ.kind == nnkBracketExpr and $typ[0] == name


macro accessTuple(t: typedesc): untyped =
  result = t.getTypeInst[^1].copyNimTree

  for i in countDown(result.len - 1, 0):
    if result[i].kind == nnkBracketExpr and result[i][0] == bindSym"Not":
      result.del(i)

  for i in 0..<result.len:
    let fieldType = result[i]

    if isOp(fieldType, "Write"):
      result[i] = nnkVarTy.newTree(fieldType[1])
  result = newCall("typeof", result)


template accessor[T](world: var World, archetype: Archetype, archetypeEntityId: int): T =
  let ind = archetype.getIndex(world.componentIdFrom typeof T)
  cast[EcsSeq[T]](
    archetype.componentLists[ind]
  )[archetypeEntityId]


proc componentData[T](componentList: EcsSeq[T]): ptr UncheckedArray[T] {.inline.} =
  if componentList.len == 0:
    return nil

  cast[ptr UncheckedArray[T]](unsafeAddr componentList[0])


macro buildReadTuple(world: var World, t: typedesc, archetype: untyped, archetypeEntityId: untyped): untyped =
  let tupleType = t.getTypeInst[^1]
  var tupleExprs = nnkTupleConstr.newTree()

  for i in 0..<tupleType.len:
    let fieldType = tupleType[i]
    let fieldExpr = quote do: accessor[`fieldType`](world, `archetype`, `archetypeEntityId`)
    tupleExprs.add(fieldExpr)

  result = tupleExprs


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


macro buildComponentColumns(world: var World, t: typedesc, archetype: untyped): untyped =
  let tupleType = t.getTypeInst[^1]
  var tupleExprs = nnkTupleConstr.newTree()

  for fieldType in tupleType:
    if not isOp(fieldType, "Not"):
      let componentType =
        if isOp(fieldType, "Write") or isOp(fieldType, "Opt"):
          fieldType[1]
        else:
          fieldType

      let fieldExpr =
        if isOp(fieldType, "Opt"):
          quote do:
            block:
              let componentId = `world`.componentIdFrom typeof `componentType`

              if `archetype`.contains(componentId):
                let ind = `archetype`.getIndex(componentId)
                let componentList = cast[EcsSeq[`componentType`]](`archetype`.componentLists[ind])
                componentData(componentList)
              else:
                cast[ptr UncheckedArray[`componentType`]](nil)
        else:
          quote do:
            block:
              let componentId = `world`.componentIdFrom typeof `componentType`
              let ind = `archetype`.getIndex(componentId)
              let componentList = cast[EcsSeq[`componentType`]](`archetype`.componentLists[ind])
              componentData(componentList)

      tupleExprs.add(fieldExpr)

  result = tupleExprs


macro buildColumnAccessTuple(t: typedesc, componentColumns: untyped, archetypeEntityId: untyped): untyped =
  let tupleType = t.getTypeInst[^1]
  var tupleExprs = nnkTupleConstr.newTree()
  var componentColumnIndex = 0

  for fieldType in tupleType:
    if not isOp(fieldType, "Not"):
      let componentColumn = nnkBracketExpr.newTree(componentColumns, newLit(componentColumnIndex))
      let fieldAccess = nnkBracketExpr.newTree(componentColumn, archetypeEntityId)
      let fieldExpr =
        if isOp(fieldType, "Opt"):
          let componentType = fieldType[1]
          quote do:
            if `componentColumn` != nil:
              some(`fieldAccess`)
            else:
              none[`componentType`]()
        else:
          fieldAccess

      tupleExprs.add(fieldExpr)
      inc componentColumnIndex

  result = tupleExprs


proc consolidateRemoveEntity(world: var World, id: EntityId) =
  let entity = world.entities[id.value]
  var archetype = world.archetypes[entity.archetypeIndex]

  archetype.remove entity.archetypeEntityId
  world.deleteEntity id


proc consolidateAddComponents(world: var World, id: EntityId, componentsToAdd: Table[ComponentId, AddItemAny]) =
  var entity = world.entities[id.value]
  var previousArchetype = world.archetypes[entity.archetypeIndex]
  var componentIds: seq[ComponentId] = @[]

  for componentId in componentsToAdd.keys:
    when CHECKS_ENABLED: 
      if componentId in previousArchetype.id:
        let message = "Component " & $componentId & " already exists in Entity " & $id & "."
        raise newException(DoubleAddDefect, message)

    componentIds.add componentId

  let nextIndex = world.nextArchetypeAddingFrom(previousArchetype, componentIds)
  var nextArchetype = world.archetypes[nextIndex]

  entity.archetypeIndex = nextIndex
  entity.archetypeEntityId = previousArchetype.moveAdding(entity.archetypeEntityId, nextArchetype, componentsToAdd)
  world.entities[id.value] = entity


proc consolidateRemoveComponents(world: var World, id: EntityId, compIdsToRemove: PackedSet[ComponentId]) =
  var entity = world.entities[id.value]
  var previousArchetype = world.archetypes[entity.archetypeIndex]
  var componentIds: seq[ComponentId]

  for compId in compIdsToRemove.items:
    componentIds.add compId

  let nextIndex = world.nextArchetypeRemovingFrom(previousArchetype, componentIds)
  var nextArchetype = world.archetypes[nextIndex]

  entity.archetypeIndex = nextIndex
  entity.archetypeEntityId = previousArchetype.moveRemoving(entity.archetypeEntityId, nextArchetype)
  world.entities[id.value] = entity


iterator archetypes*(world: var World): Archetype =
  ## Iterate through all the world's archetypes.
  ##
  ## This is mostly useful just to implement custom queries.
  ## To use Archetypes, the archetype module must be imported.
  for archetype in world.archetypes:
    if not archetype.isNil:
      yield archetype


proc componentIdFrom*[T](world: var World, desc: typedesc[T]): ComponentId =
  ## Get the ComponentId for a given component type.
  ## This is mostly useful to identify the components of an archetype.
  result = T.toComponentId
  let id = result.int

  if world.builders[id] == nil:
    world.builders[id] = ecsSeqBuilder[T]()
    world.getters[id] = ecsSeqGetter[T]()


proc has*[T](world: var World, id: EntityId, compDesc: typedesc[T]): bool =
  ## Check if an entity has a given component.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"),), Immediate)
    assert w.has(marcus, Character)
    assert not w.has(marcus, Health)

  checkNotATuple(T)
  world.checkEntityExists(id)

  let entity = world.entities[id.value]
  let compId = world.componentIdFrom typeof compDesc
  let archetype = world.archetypes[entity.archetypeIndex]
  compId in archetype.id


template read*[T](world: var World, id: EntityId, compDesc: typedesc[T]): T =
  ## Directly read a single component of an entity.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"),), Immediate)
    let character = w.read(marcus, Character)
    assert character.name == "Marcus"

  checkNotATuple(T)

  when CHECKS_ENABLED:
    if not world.has(id, compDesc):
      raise componentDoesNotExist(id, compDesc)

  let entity = world.entities[id.value]
  let archetype = world.archetypes[entity.archetypeIndex]
  let archetypeEntityId = entity.archetypeEntityId
  let compId = compDesc.toComponentId
  let ind = archetype.getIndex(compId)
  let ecsSeqAny = archetype.componentLists[ind]

  type Retype = EcsSeq[T]
  cast[Retype](ecsSeqAny)[archetypeEntityId]


iterator write*[T](world: var World, id: EntityId, compDesc: typedesc[T]): var T =
  ## Write access to a single component of an entity.
  ## An iterator is used to ensure fast and safe access to the component.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"),), Immediate)

    for character in w.write(marcus, Character):
      character.name = "Mark"

    assert w.read(marcus, Character).name == "Mark"

  checkNotATuple(T)
  world.checkEntityExists(id)

  let entity = world.entities[id.value]
  let archetype = world.archetypes[entity.archetypeIndex]
  let archetypeEntityId = entity.archetypeEntityId
  let compId = compDesc.toComponentId

  if archetype.hasKey(compId):
    let index = archetype.getIndex(compId)
    let ecsSeqAny = archetype.componentLists[index]
    type Retype = EcsSeq[T]
    yield cast[Retype](ecsSeqAny)[archetypeEntityId]


template read*[T: tuple](world: var World, id: EntityId, tup: typedesc[T]): T =
  ## Direct read access to multiple components of an entity.
  ## The `T` tuple must contain no `Write`, `Opt`, or `Not` accessors.
  runnableExamples:
    import examples

    var w = World()
    let character = Character(name: "Marcus")
    let sword = Weapon(name: "Sword")
    let elements = Spellbook(spells: @["Fireball", "Ice Storm", "Lightning"])
    let marcus = w.add((character, sword, elements), Immediate)

    let (weapon, spellbook) = w.read(marcus, (Weapon, Spellbook))

    assert weapon.name == "Sword"
    assert spellbook.spells == @["Fireball", "Ice Storm", "Lightning"]

  world.checkEntityExists(id)

  let entity = world.entities[id.value]
  let archetype = world.archetypes[entity.archetypeIndex]
  let archetypeEntityId = entity.archetypeEntityId

  when CHECKS_ENABLED:
    tup.fieldTypes:
      if not world.has(id, typeof FieldType):
        raise componentsDoNotExist(id, tup)

  world.buildReadTuple(tup, archetype, archetypeEntityId)


iterator components*[T: tuple](world: var World, id: EntityId, tup: typedesc[T]): accessTuple(tup) =
  ## Read, write, and optional access to components of an entity.
  ## An iterator is used to ensure fast and safe access to the components.
  ## **Accessors:**
  ## - **Read access**: just use the component's type
  ## - **Write access**: use `Write[Component]`
  ## - **Optional access**: use `Opt[Component]`, availability can be checked with `isSomething` or `isNothing`
  ## - **Not access**: use `Not[Component]`, to avoid access if the entity contains `Component`
  runnableExamples:
    import examples

    var w = World()
    let character = Character(name: "Marcus")
    let weapon = Weapon(name: "Sword")
    let spellbook = Spellbook(spells: @["Fireball", "Ice Storm", "Lightning"])
    let marcus = w.add((character, weapon, spellbook), Immediate)

    for (character, weapon, armor, spellbook) in w.components(marcus, (Character, Write[Weapon], Opt[Armor], Opt[Spellbook])):
      echo character.name
      weapon.attack = 10

      armor.isSomething:
        raiseAssert "Marcus should have no armor."
      armor.isNothing:
        echo "Marcus has no armor."

      spellbook.isSomething:
        echo "Marcus's spellbook contains: ", value.spells
      spellbook.isNothing:
        raiseAssert "Marcus should have a spellbook."

    assert w.read(marcus, Weapon).attack == 10

  world.checkEntityExists(id)

  let entity = world.entities[id.value]
  let archetype = world.archetypes[entity.archetypeIndex]
  let archetypeEntityId = entity.archetypeEntityId
  let requiredArchetypeIds = world.requiredArchetypeIdsFrom T
  let excludedArchetypeIds = world.excludedArchetypeIdsFrom T

  if archetype.contains(requiredArchetypeIds) and archetype.disjointed(excludedArchetypeIds):
    yield world.buildAccessTuple(tup, archetype, archetypeEntityId)


proc add*[T: tuple](world: var World, id: EntityId, components: T, mode: OperationMode = Deferred) =
  ## Add components to an entity.
  ## If `mode` is `Deferred`, the components will be added when `consolidate()` is called, `Deferred` is the default mode.
  ## If `mode` is `after(query)`, the components will be added after `query` is iterated.
  ## If `mode` is `Immediate`, the components will be added immediately.
  ## **Note:** Adding components immediately during query iteration leads to undefined behaviour.
  runnableExamples:
    import examples
    import show

    var w = World()
    let marcus = w.add (Character(name: "Marcus"),)
    w.add(marcus, (Health(health: 100, maxHealth: 100), Weapon(name: "Sword", attack: 10)))
    w.consolidate()

    assert w.has(marcus, Health)
    assert w.has(marcus, Weapon)

  world.checkEntityExists(id)

  var entity = world.entities[id.value]
  let entityArchetype = world.archetypes[entity.archetypeIndex]
  
  when CHECKS_ENABLED:
    for name, value in fieldPairs components:
      let componentId = world.componentIdFrom typeof value

      if entityArchetype.id.contains(componentId):
        raise newException(ValueError, "Component " & $(typeof value) & " already exists in Entity " & $id)

  if mode.kind == ImmediateMode:
    var previousArchetype = world.archetypes[entity.archetypeIndex]
    var componentIdsToAdd: seq[ComponentId]
    for name, value in fieldPairs components:
      componentIdsToAdd.add world.componentIdFrom typeof value

    var nextArchetype = world.nextArchetypeAddingFrom(previousArchetype, componentIdsToAdd)
    entity.archetypeIndex = nextArchetype
    entity.archetypeEntityId = previousArchetype.moveAddingTuple(entity.archetypeEntityId, world.archetypes[nextArchetype], components)
    world.entities[id.value] = entity
  else:
    var componentsToAdd = initTable[ComponentId, AddItemAny]()
    for name, value in fieldPairs components:
      let componentId = world.componentIdFrom typeof value
      componentsToAdd[componentId] = newAddItem(value)

    if mode.kind == AfterMode:
      for meta in world.write(id, Meta):
        let operation = Operation(id: meta.id, kind: AddComponents, componentsToAdd: componentsToAdd)
        mode.query[].operations.add operation
    else:
      
      for meta in world.write(id, Meta):
        let operation = Operation(id: meta.id, kind: AddComponents, componentsToAdd: componentsToAdd)
        meta.enqueueOperation(operation)

      world.toConsolidate.incl id


proc add*[T](world: var World, id: EntityId, component: T, mode: OperationMode = Deferred) =
  ## Add a component to an entity.
  ## If `mode` is `Deferred`, the component will be added when `consolidate()` is called, `Deferred` is the default mode.
  ## If `mode` is `after(query)`, the component will be added after `query` is iterated.
  ## If `mode` is `Immediate`, the component will be added immediately.
  ## **Note:** Adding components immediately during query iteration leads to undefined behaviour.
  runnableExamples:
    import examples
    import show

    var w = World()
    let marcus = w.add (Character(name: "Marcus"),)
    w.add(marcus, Health(health: 100, maxHealth: 100))
    w.consolidate()

    assert w.has(marcus, Health)

  checkNotATuple(T)
  world.add(id, (component,), mode)


proc remove*[T: tuple](world: var World, id: EntityId, descriptions: typedesc[T], mode: OperationMode = Deferred) =
  ## Remove multiple components from an entity.
  ## If `mode` is `Deferred`, the components will be removed when `consolidate()` is called, `Deferred` is the default mode.
  ## If `mode` is `after(query)`, the components will be removed after `query` is iterated.
  ## If `mode` is `Immediate`, the components will be removed immediately.
  ## **Note:** Removing components immediately during query iteration leads to undefined behaviour.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"), Weapon(name: "Sword")), Immediate)
    w.remove(marcus, (Weapon, Character))
    w.consolidate()

    assert not w.has(marcus, Character)
    assert not w.has(marcus, Weapon)

  world.checkEntityExists(id)

  var entity = world.entities[id.value]
  var compIdsToRemove: PackedSet[ComponentId]

  for name, typ in fieldPairs default T:
    let componentId = world.componentIdFrom typeof typ

    when CHECKS_ENABLED:
      let prevArchetype = world.archetypes[entity.archetypeIndex]
      if not prevArchetype.id.contains(componentId):
        raise newException(ValueError, "Component " & $typ & " not found in Entity " & $id)

    compIdsToRemove.incl componentId

  if mode.kind == ImmediateMode:
    world.consolidateRemoveComponents(id, compIdsToRemove)
  elif mode.kind == AfterMode:
    for meta in world.write(id, Meta):
      let operation = Operation(id: meta.id, kind: RemoveComponents, compIdsToRemove: compIdsToRemove)
      mode.query[].operations.add operation
  else:
    for meta in world.write(id, Meta):
      let operation = Operation(id: meta.id, kind: RemoveComponents, compIdsToRemove: compIdsToRemove)
      meta.enqueueOperation(operation)

    world.toConsolidate.incl id


proc remove*[T](world: var World, id: EntityId, compDesc: typedesc[T], mode: OperationMode = Deferred) =
  ## Remove a component from an entity.
  ## If `mode` is `Deferred`, the component will be removed when `consolidate()` is called, `Deferred` is the default mode.
  ## If `mode` is `after(query)`, the component will be removed after `query` is iterated.
  ## If `mode` is `Immediate`, the component will be removed immediately.
  ## **Note:** Removing a component immediately during query iteration leads to undefined behaviour.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"), Weapon(name: "Sword")), Immediate)
    w.remove(marcus, Weapon)
    w.consolidate()

    assert w.has(marcus, Weapon) == false

  checkNotATuple(T)
  remove(world, id, (T,), mode)


proc add*[T: tuple](world: var World, components: T, mode: OperationMode = Deferred): EntityId {.discardable.} =
  ## Add an entity with components. Automatically adds the special `Meta` component, so queries can access metadata like the entity's `Id`.
  ## If `mode` is `Deferred`, the entity with a `Meta` component is created immediately, but the components will be added when `consolidate()` is called, `Deferred` is the default mode.
  ## If `mode` is `after(query)`, the entity with a `Meta` component is created immediately, but the components will be added after `query` is iterated.
  ## If `mode` is `Immediate`, the entity and components will be added immediately.
  ## **Note:** Adding entities immediately during query iteration leads to undefined behaviour.
  ## Returns the new entity's `Id`.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"),), Immediate)

    assert w.read(marcus, Meta).id == marcus
    assert w.read(marcus, Character).name == "Marcus"

  if mode.kind == ImmediateMode:
    let archetypeIndex = world.archetypeFrom WithMeta(T)
    let archetypeEntityId = world.archetypes[archetypeIndex].add withMeta(components)
    let entity = Entity(archetypeIndex: archetypeIndex, archetypeEntityId: archetypeEntityId)
    result = world.allocateEntity(entity)

    for meta in world.write(result, Meta):
      meta.id = result
  else:
    let archetypeIndex = world.archetypeFrom (Meta,)
    let archetypeEntityId = world.archetypes[archetypeIndex].add (Meta(),)
    let entity = Entity(archetypeIndex: archetypeIndex, archetypeEntityId: archetypeEntityId)
    result = world.allocateEntity(entity)

    for meta in world.write(result, Meta):
      meta.id = result

    world.add(result, components, mode)


proc addEmpty*(world: var World): EntityId {.discardable.} =
  ## Add an empty entity immediately.
  ## The entity will have a single Meta component.
  ## Returns the new entity's `Id`.
  runnableExamples:
    import examples

    var w = World()
    let id = w.addEmpty()

    assert w.read(id, Meta).id == id

  let archetypeIndex = world.archetypeFrom (Meta,)
  let archetypeEntityId = world.archetypes[archetypeIndex].add (Meta(),)
  let entity = Entity(archetypeIndex: archetypeIndex, archetypeEntityId: archetypeEntityId)
  result = world.allocateEntity(entity)

  for meta in world.write(result, Meta):
    meta.id = result


proc addWithSpecificId*(world: var World, id: EntityId) =
  ## Add an entity with a given id immediately.
  ## The entity will have a single Meta component.
  ## This is useful mostly for deserialization.
  ## **Note:** Any id above 0 is valid, however a greater id will allocate more memory.
  runnableExamples:
    import examples

    var w = World()
    w.addWithSpecificId(newEntityId(0, 10))

  checkIdIsValid(id)
  world.checkEntityDoesNotExist(id)

  let archetypeIndex = world.archetypeFrom (Meta,)
  let archetypeEntityId = world.archetypes[archetypeIndex].add (Meta(id: id),)
  let entity = Entity(archetypeIndex: archetypeIndex, archetypeEntityId: archetypeEntityId)
  world.setEntityAt(id, entity)

proc remove*(world: var World, id: EntityId, mode: OperationMode = Deferred) =
  ## Remove an entity from the world.
  ## If `mode` is `Deferred`, the entity will be removed when `consolidate()` is called, `Deferred` is the default mode.
  ## If `mode` is `after(query)`, the entity will be removed after `query` is iterated.
  ## If `mode` is `Immediate`, the entity will be removed immediately.
  ## **Note:** Removing entities immediately during query iteration leads to undefined behaviour.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add (Character(name: "Marcus"),)
    w.remove(marcus)
    w.consolidate()

    var query: Query[(Character,)]
    for character in w.query(query):
      raiseAssert "No character should exist."

  world.checkEntityExists(id)

  if mode.kind == ImmediateMode:
    world.consolidateRemoveEntity(id)
  elif mode.kind == AfterMode:
    for meta in world.write(id, Meta):
      let operation = Operation(id: meta.id, kind: RemoveEntity)
      mode.query[].operations.add operation
  else:
    for meta in world.write(id, Meta):
      let operation = Operation(id: meta.id, kind: RemoveEntity)
      meta.enqueueOperation(operation)

    world.toConsolidate.incl id


proc applyQueryOperations[T: tuple](world: var World, query: var Query[T]) {.inline.} =
  for operation in query.operations:
    case operation.kind:
    of RemoveEntity:
      world.consolidateRemoveEntity(operation.id)
    of AddComponents:
      world.consolidateAddComponents(operation.id, operation.componentsToAdd)
    of RemoveComponents:
      world.consolidateRemoveComponents(operation.id, operation.compIdsToRemove)

  query.operations.setLen(0)


proc removesComponent(operation: Operation, componentId: ComponentId): bool =
  if operation.kind == RemoveEntity:
    return true

  if operation.kind != RemoveComponents:
    return false

  componentId in operation.compIdsToRemove


iterator query*[T: tuple](world: var World, query: var Query[T]): T.accessTuple =
  ## Query for components on entities. Components are matched based on the query's type parameter.
  ## 
  ## **Accessors:**
  ## - **Read access**: match entities that have the component for read only access. Just use the component's type.
  ## - **Write access**: match entities that have the comoponent for write access. Use `Write[Component]`.
  ## - **Optional access**: match entities that may or may not have the component. Use `Opt[Component]`, availability can be checked with `isSomething` or `isNothing`.
  ## - **Not access**: match entities that do not have the component. Use `Not[Component]`.
  ##
  ## The iterated tuple's type is the same as the query's type parameter, except for:
  ## - the `Not` accessors are excluded.
  ## - the `Write` accessors are replaced with the component's type.
  ##
  ## Queries build a cache that is updated each time the query is used.
  runnableExamples:
    import examples

    var w = World()
    w.add((Character(name: "Marcus"), Health(health: 100, maxHealth: 100), Weapon(name: "Sword")), Immediate)
    w.add((Character(name: "Elena"), Health(health: 80, maxHealth: 80), Amulet(name: "Arcane Stone")), Immediate)
    w.add((Character(name: "Brom"), Health(health: 140, maxHealth: 140), Armor(name: "Fur Armor")), Immediate)

    # Query for characters, health with write access, an optional weapon, and no armor.
    var query: Query[(Character, Write[Health], Opt[Weapon], Not[Armor])]

    for (character, health, weapon) in w.query(query):
      health.health += 10
      assert character.name != "Brom"

      weapon.isSomething:
        assert character.name == "Marcus"
        echo character.name, " has a weapon: ", value.name

      weapon.isNothing:
        assert character.name == "Elena"
        echo character.name, " has no weapon."

  world.updateQuery(query)

  for archetypeIndex in query.matchedArchetypes:
    let archetype = world.archetypes[archetypeIndex]
    let componentColumns {.used.} = world.buildComponentColumns(typeof T, archetype)

    for archetypeEntityId in archetype.entities:
      yield buildColumnAccessTuple(typeof T, componentColumns, archetypeEntityId)

  world.applyQueryOperations(query)


iterator queryForRemoval*[T](world: var World, compDesc: typedesc[T]): (Meta, T).accessTuple =
  ## Query for components to be removed from entities and components on entities to be removed.
  ## The yielded components have write access.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"), Weapon(name: "Sword", attack: 10)), Immediate)
    let elena = w.add((Character(name: "Elena"), Weapon(name: "Dagger", attack: 5)), Immediate)
    let brom = w.add((Character(name: "Brom"), Weapon(name: "Axe", attack: 15)), Immediate)

    w.remove(marcus, Weapon)
    w.remove(elena, Weapon)
    w.remove(brom)

    var removedWeapons: seq[(Meta, Weapon)] = @[]
    for (meta, weapon) in w.queryForRemoval(Weapon):
      removedWeapons.add (meta, weapon)
      assert weapon.name in ["Sword", "Dagger", "Axe"]

    assert removedWeapons.len == 3

  checkNotATuple(T)
  var ofType {.global.}: Query[(Meta, T)]
  var ids: seq[EntityId] = @[]
  let metaComponentId = world.componentIdFrom Meta
  let componentId = world.componentIdFrom T

  world.updateQuery(ofType)

  for archetypeIndex in ofType.matchedArchetypes:
    let archetype = world.archetypes[archetypeIndex]
    let ind = archetype.getIndex(metaComponentId)
    let metaComponents = cast[EcsSeq[Meta]](archetype.componentLists[ind])

    for archetypeEntityId in archetype.entities:
      let meta = addr metaComponents[archetypeEntityId]

      for operation in meta[].operations:
        if operation.removesComponent(componentId):
          ids.add meta[].id
          break

  world.applyQueryOperations(ofType)

  for id in ids:
    let entity = world.entities[id.value]
    let archetype = world.archetypes[entity.archetypeIndex]
    let archetypeEntityId = entity.archetypeEntityId
    yield world.buildAccessTuple((Write[Meta], Write[T]), archetype, archetypeEntityId)


proc releaseArchetypeIfEmpty(world: var World, index: int): bool =
  let archetype = world.archetypes[index]

  if archetype.isNil:
    return false

  if not archetype.isEmpty:
    return false

  world.archIdToIndex.del(archetype.id)
  world.archetypes[index] = nil
  world.freeArchetype.add index
  result = true


proc cleanupEmptyArchetypes*(world: var World) =
  ## Cleans up empty archetypes.
  ## This is useful mostly for deserialization routines.
  ## Removing archetypes forces caches from queries to be rebuilt.
  var releasedAny = false

  for index in 0 ..< world.archetypes.len:
    if world.releaseArchetypeIfEmpty(index):
      releasedAny = true

  if releasedAny:
    inc world.version


proc consolidate*(world: var World) =
  ## Consolidates all additions and removals in the world and drains all event queues.
  for id in world.toConsolidate:
    for meta in world.write(id, Meta):
      let operations = meta.operations
      meta.clearOperations()

      for operation in operations:
        case operation.kind:
        of RemoveEntity:
          world.consolidateRemoveEntity(id)
        of AddComponents:
          world.consolidateAddComponents(id, operation.componentsToAdd)
        of RemoveComponents:
          world.consolidateRemoveComponents(id, operation.compIdsToRemove)

  world.toConsolidate.clear()

  for queue in world.eventQueues.mvalues:
    queue.clear()


proc emit*[T](world: var World, event: T) =
  ## Enqueue an event of type `T` into the world's event queue for that type.
  ## Events are drained by `consolidate`.
  runnableExamples:
    type DamageEvent = object
      amount: int

    var w = World()
    w.emit(DamageEvent(amount: 10))

  let kind = eventKindFrom(T)

  if not world.eventQueues.hasKey(kind):
    world.eventQueues[kind] = EventQueue[T]()

  let queue = cast[EventQueue[T]](world.eventQueues[kind])
  queue.data.add(event)


proc snapshot*(world: var World, id: EntityId): Snapshot =
  ## Capture a snapshot of an entity's current components and state.
  ## The snapshot can be used to restore the entity to this state later.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"), Health(health: 100, maxHealth: 100)), Immediate)
    let snap = w.snapshot(marcus)
    assert snap != nil

  let entity = world.entities[id.value]
  let archetype = world.archetypes[entity.archetypeIndex]
  let archetypeEntityId = entity.archetypeEntityId
  let metaId = world.componentIdFrom Meta

  result = Snapshot(entityId: id)

  for compId in archetype.componentIds:
    if compId != metaId:
      let getter = world.getters[compId.int]
      let index = archetype.getIndex(compId)
      result.componentData[compId] = getter(archetype.componentLists[index], archetypeEntityId)


proc duplicateComponent(world: var World, componentId: ComponentId, snapshotSeq: EcsSeqAny): EcsSeqAny =
  let getter = world.getters[componentId.int]
  getter(snapshotSeq, 0)


proc restore*(world: var World, snap: Snapshot, id: EntityId = EntityId()) =
  ## Restore an entity to a previously captured snapshot state.
  ## Components removed since the snapshot are re-added.
  ## Components added since the snapshot are removed.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"), Health(health: 100, maxHealth: 100)), Immediate)
    let snap = w.snapshot(marcus)

    for health in w.write(marcus, Health):
      health.health = 0

    w.restore(snap)
    assert w.read(marcus, Health).health == 100

  let id = if id == EntityId(): snap.entityId else: id

  if world.has(id):
    world.consolidateRemoveEntity(id)

  world.addWithSpecificId(id)

  var componentsToAdd = initTable[ComponentId, AddItemAny]()
  var duplicates: seq[EcsSeqAny]

  for compId, snapshotSeq in snap.componentData:
    let duplicate = world.duplicateComponent(compId, snapshotSeq)
    duplicates.add duplicate
    componentsToAdd[compId] = AddItemAny(raw: duplicate.rawGet(0))

  world.consolidateAddComponents(id, componentsToAdd)


iterator collect*[T](world: var World, _: typedesc[T]): T =
  ## Yield all queued events of type `T`.
  ## Multiple systems can collect the same event type within a frame.
  ## Events are drained by `consolidate`.
  runnableExamples:
    type DamageEvent = object
      amount: int

    var w = World()
    w.emit(DamageEvent(amount: 10))
    w.emit(DamageEvent(amount: 20))

    for event in w.collect(DamageEvent):
      assert event.amount > 0

  let kind = eventKindFrom(T)

  if world.eventQueues.hasKey(kind):
    let queue = cast[EventQueue[T]](world.eventQueues[kind])

    for event in queue.data:
      yield event
