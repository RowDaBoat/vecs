#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import std/[packedsets, hashes, macros, intsets, options]
import typetraits, tables, sets
import entityid, archetype, entity, ecsseq, queries, components, operations, operationmodes
export entityid.EntityId, components.Meta, operationmodes
export components


type World* = object
  entities: EcsSeq[Entity] = EcsSeq[Entity]()
  archetypeIds: seq[ArchetypeId] = @[]
  archetypes: Table[ArchetypeId, Archetype]
  builders: Table[ComponentId, Builder]
  movers: Table[ComponentId, Mover]
  toConsolidate: HashSet[EntityId]
  version: int = 0


type DoubleAddDefect* = object of Defect


proc hash*(id: ArchetypeId): Hash =
  for compId in id.items:
    result = result xor (compId.int mod 32)


proc `==`*(a, b: ComponentId): bool {.borrow.}


macro typeHash*[T](typ: typedesc[T]): int =
  typ.getTypeInst.repr.hash.newIntLitNode


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
  if id.value < 0:
    raise idIsInvalid(id)


template checkNotATuple[T](tup: typedesc[T]) =
  when T is tuple:
    {.error: "Component type expected, got a tuple: " & $T.}


proc checkEntityExists(world: var World, id: EntityId) =
  if not world.entities.has(id.value):
    raise entityDoesNotExist(id)


proc checkEntityDoesNotExist(world: var World, id: EntityId) =
  if world.entities.has(id.value):
    raise entityAlreadyExists(id)


# Archetype creation and book-keeping
proc nextArchetypeAddingFrom(world: var World, previousArchetype: Archetype, componentIdsToAdd: seq[ComponentId]): var Archetype =
  let previousArchetypeId = previousArchetype.id
  var nextArchetypeId = previousArchetypeId

  for componentId in componentIdsToAdd:
    nextArchetypeId.incl componentId

  if not world.archetypes.hasKey(nextArchetypeId):
    var builders: seq[Builder] = @[]
    var movers: seq[Mover] = @[]

    for componentId in componentIdsToAdd:
      builders.add world.builders[componentId]
      movers.add world.movers[componentId]

    world.archetypes[nextArchetypeId] = previousArchetype.makeNextAdding(componentIdsToAdd, builders, movers)
    world.archetypeIds.add nextArchetypeId

  world.archetypes[nextArchetypeId]


proc nextArchetypeRemovingFrom(world: var World, previousArchetype: Archetype, componentIdsToRemove: seq[ComponentId]): var Archetype =
  let previousArchetypeId = previousArchetype.id
  var nextArchetypeId = previousArchetypeId

  for componentId in componentIdsToRemove:
    nextArchetypeId.excl componentId

  if not world.archetypes.hasKey(nextArchetypeId):
    world.archetypes[nextArchetypeId] = previousArchetype.makeNextRemoving(componentIdsToRemove)
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

    for name, typ in fieldPairs default T:
      let compId = world.componentIdFrom typeof typ
      componentIds.add compId
      builders.add world.builders[compId]
      movers.add world.movers[compId]

    world.archetypes[archetypeId] = makeArchetype(componentIds, builders, movers)
    world.archetypeIds.add archetypeId

  world.archetypes[archetypeId]


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


proc updateQuery[T: tuple](world: var World, query: var Query[T]) =
  if world.archetypes.len == query.lastArchetypeCount:
    return

  if world.version > query.lastVersion:
    query.reset(world.version)

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
      result[i] = nnkVarTy.newTree(x[1])
  result = newCall("typeof", result)


template accessor[T](world: var World, archetype: Archetype, archetypeEntityId: int): T =
  cast[EcsSeq[T]](
    archetype.componentLists[world.componentIdFrom typeof T]
  )[archetypeEntityId]


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


proc consolidateRemoveEntity(world: var World, id: EntityId) =
  let entity = world.entities[id.value]
  var archetype = world.archetypes[entity.archetypeId]

  archetype.remove entity.archetypeEntityId
  world.entities.del id.value


proc consolidateAddComponents(world: var World, id: EntityId, componentAddersById: Table[ComponentId, Adder]) =
  var entity = world.entities[id.value]
  var previousArchetype = world.archetypes[entity.archetypeId]
  var componentIds: seq[ComponentId] = @[]

  for componentId in componentAddersById.keys:
    if componentId in previousArchetype.id:
      let message = "Component " & $componentId & " already exists in Entity " & $id & "."
      raise newException(DoubleAddDefect, message)

    componentIds.add componentId

  var nextArchetype = world.nextArchetypeAddingFrom(previousArchetype, componentIds)

  entity.archetypeId = nextArchetype.id
  entity.archetypeEntityId = previousArchetype.moveAdding(entity.archetypeEntityId, nextArchetype, componentAddersById)
  world.entities[id.value] = entity


proc consolidateRemoveComponents(world: var World, id: EntityId, compIdsToRemove: PackedSet[ComponentId]) =
  var entity = world.entities[id.value]
  var previousArchetype = world.archetypes[entity.archetypeId]
  var componentIds: seq[ComponentId]

  for compId in compIdsToRemove.items:
    componentIds.add compId
  
  var nextArchetype = world.nextArchetypeRemovingFrom(previousArchetype, componentIds)

  entity.archetypeId = nextArchetype.id
  entity.archetypeEntityId = previousArchetype.moveRemoving(entity.archetypeEntityId, nextArchetype)
  world.entities[id.value] = entity


iterator archetypes*(world: var World): Archetype =
  ## Iterate through all the world's archetypes.
  ##
  ## This is mostly useful just to implement custom queries.
  ## To use Archetypes, the archetype module must be imported.
  for archetypeId in world.archetypeIds:
    yield world.archetypes[archetypeId]


proc componentIdFrom*[T](world: var World, desc: typedesc[T]): ComponentId =
  ## Get the ComponentId for a given component type.
  ## This is mostly useful to identify the components of an archetype.
  var id: int = typeHash(T)

  if not world.builders.hasKey(id.ComponentId):
    world.builders[id.ComponentId] = ecsSeqBuilder[T]()
    world.movers[id.ComponentId] = ecsSeqMover[T]()

  id.ComponentId


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
  compId in entity.archetypeId


proc read*[T](world: var World, id: EntityId, compDesc: typedesc[T]): T =
  ## Directly read a single component of an entity.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"),), Immediate)
    let character = w.read(marcus, Character)
    assert character.name == "Marcus"

  checkNotATuple(T)

  if not world.has(id, compDesc):
    raise componentDoesNotExist(id, compDesc)

  let entity = world.entities[id.value]
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId
  let compId = world.componentIdFrom typeof compDesc
  let ecsSeqAny = archetype.componentLists[compId]

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
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId
  let compId = world.componentIdFrom typeof T

  if archetype.componentLists.hasKey(compId):
    let ecsSeqAny = archetype.componentLists[compId]
    type Retype = EcsSeq[T]
    yield cast[Retype](ecsSeqAny)[archetypeEntityId]


proc read*[T: tuple](world: var World, id: EntityId, tup: typedesc[T]): T =
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
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId

  tup.fieldTypes:
    if not world.has(id, typeof FieldType):
      raise componentsDoNotExist(id, tup)

  world.buildReadTuple(tup, archetype, archetypeEntityId)


iterator components*[T: tuple](world: var World, id: EntityId, tup: typedesc[T]): tup.accessTuple =
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
      armor.isNothing:
        raiseAssert "Marcus should have a spellbook."

  world.checkEntityExists(id)

  let entity = world.entities[id.value]
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId

  var found = true

  tup.fieldTypes:
    let compId = world.componentIdFrom typeof FieldType
    found = found and archetype.componentLists.hasKey(compId)

  if found:
    yield world.buildAccessTuple(tup, archetype, archetypeEntityId)


proc add*[T: tuple](world: var World, id: EntityId, components: T, mode: OperationMode = Deferred) =
  ## Add components to an entity.
  ## If the `mode` is `Deferred`, the components will be added when `consolidate()` is called, `Deferred` is the default mode.
  ## If the `mode` is `Immediate`, the components will be added immediately.
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
  var addersById = initTable[ComponentId, Adder]()

  for name, value in fieldPairs components:
    let componentId = world.componentIdFrom typeof value

    if entity.archetypeId.contains(componentId):
      raise newException(ValueError, "Component " & $(typeof value) & " already exists in Entity " & $id)

    let component = value
    let adder = proc(ecsSeq: var EcsSeqAny): int =
      cast[EcsSeq[typeof value]](ecsSeq).add component

    addersById[componentId] = adder

  if mode.kind == ImmediateMode:
    world.consolidateAddComponents(id, addersById)
  elif mode.kind == AfterMode:
    for meta in world.write(id, Meta):
      let operation = Operation(id: meta.id, kind: AddComponents, addersById: addersById)
      mode.query[].operations.add operation
  else:
    for meta in world.write(id, Meta):
      let operation = Operation(id: meta.id, kind: AddComponents, addersById: addersById)
      meta.enqueueOperation(operation)

    world.toConsolidate.incl id


proc add*[T](world: var World, id: EntityId, component: T, mode: OperationMode = Deferred) =
  ## Add a component to an entity.
  ## If the `mode` is `Deferred`, the component will be added when `consolidate()` is called, `Deferred` is the default mode.
  ## If the `mode` is `Immediate`, the component will be added immediately.
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
  ## If the `mode` is `Deferred`, the components will be removed when `consolidate()` is called, `Deferred` is the default mode.
  ## If the `mode` is `Immediate`, the components will be removed immediately.
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

    if not entity.archetypeId.contains(componentId):
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
  ## If the `mode` is `Deferred`, the component will be removed when `consolidate()` is called, `Deferred` is the default mode.
  ## If the `mode` is `Immediate`, the component will be removed immediately.
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
  ## If the `mode` is `Deferred`, the entity with the `Meta` component is created immediately, but the components will be added when `consolidate()` is called, `Deferred` is the default mode.
  ## If the `mode` is `Immediate`, the components will be added immediately.
  ## **Note:** Adding entities immediately during query iteration leads to undefined behaviour.
  ## Returns the new entity's `Id`.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add((Character(name: "Marcus"),), Immediate)

    assert w.read(marcus, Meta).id == marcus
    assert w.read(marcus, Character).name == "Marcus"

  if mode.kind == ImmediateMode:
    var archetype = world.archetypeFrom WithMeta(T)
    let archetypeEntityId = archetype.add withMeta(components)
    let entity = Entity(archetypeId: archetype.id, archetypeEntityId: archetypeEntityId)
    let id = world.entities.add entity
    result = EntityId(value: id)

    for meta in world.write(result, Meta):
      meta.id = result
  else:
    var archetype = world.archetypeFrom (Meta,)
    var archetypeEntityId = archetype.add (Meta(),)
    let entity = Entity(archetypeId: archetype.id, archetypeEntityId: archetypeEntityId)
    let id = world.entities.add entity
    result = EntityId(value: id)

    for meta in world.write(result, Meta):
      meta.id = result

    world.add(result, components, mode)


proc addWithSpecificId*(world: var World, id: EntityId) =
  ## Add an entity with a given id immediately.
  ## The entity will have a single Meta component.
  ## This is useful mostly for deserialization.
  ## **Note:** Any id above 0 is valid, however a greater id will allocate more memory.
  runnableExamples:
    import examples

    var w = World()
    w.addWithSpecificId(EntityId(value: 10))

  checkIdIsValid(id)
  world.checkEntityDoesNotExist(id)

  var archetype = world.archetypeFrom (Meta,)
  let archetypeEntityId = archetype.add (Meta(id: id),)
  let entity = Entity(archetypeId: archetype.id, archetypeEntityId: archetypeEntityId)
  world.entities[id.value] = entity

proc remove*(world: var World, id: EntityId, mode: OperationMode = Deferred) =
  ## Remove an entity from the world.
  ## If the `mode` is `Deferred`, the entity will be removed when `consolidate()` is called, `Deferred` is the default mode.
  ## If the `mode` is `Immediate`, the entity will be removed immediately.
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


proc has*(world: var World, id: EntityId): bool =
  ## Check if an entity exists.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.add (Character(name: "Marcus"),)
    assert w.has(marcus) == true
    assert w.has(EntityId(value: 10)) == false

  world.entities.has(id.value)


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

  for archetypeId in query.matchedArchetypes:
    let archetype = world.archetypes[archetypeId]
    for archetypeEntityId in archetype.entities:
      yield world.buildAccessTuple(typeof T, archetype, archetypeEntityId)

  for operation in query.operations:
    case operation.kind:
    of RemoveEntity:
      world.consolidateRemoveEntity(operation.id)
    of AddComponents:
      world.consolidateAddComponents(operation.id, operation.addersById)
    of RemoveComponents:
      world.consolidateRemoveComponents(operation.id, operation.compIdsToRemove)

  query.operations.setLen(0)


iterator queryForRemoval*[T](world: var World, compDesc: typedesc[T]): (Meta, T) =
  ## Query for components to be removed from entities and components on entities to be removed.
  ## Only read access is allowed.
  runnableExamples:
    discard

  checkNotATuple(T)
  var ofType {.global.}: Query[(Meta, T)]
  var tuples : seq[(Meta, T)] = @[]

  for (meta, component) in world.query(ofType):
    for operation in meta.operations:
      if operation.kind == RemoveEntity:
        tuples.add (meta, component)
        break
      elif operation.kind == RemoveComponents and world.componentIdFrom(T) in operation.compIdsToRemove:
        tuples.add (meta, component)
        break

  for tup in tuples:
    yield tup


proc cleanupEmptyArchetypes*(world: var World) =
  ## Cleans up empty archetypes.
  ## This is useful mostly for deserialization routines.
  ## Removing archetypes forces caches from queries to be rebuilt.
  var upVersion = false
  var newArchetypeIds: seq[ArchetypeId] = @[]

  for archetypeId in world.archetypeIds:
    let archetype = world.archetypes[archetypeId]
    if archetype.isEmpty:
      world.archetypes.del archetypeId
      upVersion = true
    else:
      newArchetypeIds.add archetypeId
  
  if upVersion:
    inc world.version
    world.archetypeIds = newArchetypeIds


proc consolidate*(world: var World) =
  ## Consolidates all additions and removals in the world.
  for id in world.toConsolidate:
    for meta in world.write(id, Meta):
      let operations = meta.operations
      meta.clearOperations()

      for operation in operations:
        case operation.kind:
        of RemoveEntity:
          world.consolidateRemoveEntity(meta.id)
        of AddComponents:
          world.consolidateAddComponents(meta.id, operation.addersById)
        of RemoveComponents:
          world.consolidateRemoveComponents(meta.id, operation.compIdsToRemove)

  world.toConsolidate.clear()
