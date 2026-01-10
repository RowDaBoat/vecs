#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import std/[packedsets, hashes, macros, intsets]
import typetraits, tables
import archetype, entity, components, ecsSeq, queries, operations

type World* = object
  entities: EcsSeq[Entity] = EcsSeq[Entity]()
  archetypeIds: seq[ArchetypeId] = @[]
  archetypes: Table[ArchetypeId, Archetype]
  builders: Table[ComponentId, Builder]
  movers: Table[ComponentId, Mover]
  toRemove: seq[(Id, ComponentId)] = @[]
  version: int = 0


proc hash*(id: ArchetypeId): Hash =
  for compId in id.items:
    result = result xor (compId.int mod 32)


proc `==`*(a, b: ComponentId): bool {.borrow.}

macro typeHash*[T](typ: typedesc[T]): int =
  typ.getTypeInst.repr.hash.newIntLitNode

# Errors
proc idIsInvalid(id: Id): ref Exception =
  newException(Exception, "Id is invalid: " & $id)


proc entityDoesNotExist(id: Id): ref Exception =
  newException(Exception, "Entity with id " & $id & " does not exist.")


proc componentDoesNotExist[T](id: Id, comp: typedesc[T]): ref Exception =
  newException(Exception, "Component " & $comp & " does not exist in the entity with id " & $id)


proc componentsDoNotExist[T: tuple](id: Id, tup: typedesc[T]): ref Exception =
  newException(Exception, "One or more components of " & $tup & " do not exist in the entity with id " & $id)


proc entityAlreadyExists(id: Id): ref Exception =
  newException(Exception, "Entity with id " & $id & " already exists.")


# Checks
proc checkIdIsValid(id: Id) =
  if id.value < 0:
    raise idIsInvalid(id)


template checkNotATuple[T](tup: typedesc[T]) =
  when T is tuple:
    {.error: "Component type expected, got a tuple: " & $T.}


proc checkEntityExists(world: var World, id: Id) =
  if not world.entities.has(id.value):
    raise entityDoesNotExist(id)


proc checkEntityDoesNotExist(world: var World, id: Id) =
  if world.entities.has(id.value):
    raise entityAlreadyExists(id)


# Archetype creation and book-keeping
proc nextArchetypeAddingFrom(world: var World, previousArchetype: Archetype, componentIdToAdd: ComponentId): var Archetype =
  let previousArchetypeId = previousArchetype.id
  var nextArchetypeId = previousArchetypeId
  nextArchetypeId.incl componentIdToAdd

  if not world.archetypes.hasKey(nextArchetypeId):
    let builder = world.builders[componentIdToAdd]
    let mover = world.movers[componentIdToAdd]

    world.archetypes[nextArchetypeId] = previousArchetype.makeNextAdding(@[componentIdToAdd], @[builder], @[mover])
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


proc hasComponent*[T](world: var World, id: Id, compDesc: typedesc[T]): bool =
  ## Check if an entity has a given component.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.addEntity (Character(name: "Marcus"),)
    assert w.hasComponent(marcus, Character) == true
    assert w.hasComponent(marcus, Health) == false

  checkNotATuple(T)
  world.checkEntityExists(id)

  let entity = world.entities[id.value]
  let compId = world.componentIdFrom typeof compDesc
  compId in entity.archetypeId


proc readComponent*[T](world: var World, id: Id, compDesc: typedesc[T]): T =
  ## Directly read a single component of an entity.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.addEntity (Character(name: "Marcus"),)
    let character = w.readComponent(marcus, Character)
    assert character.name == "Marcus"

  checkNotATuple(T)

  if not world.hasComponent(id, compDesc):
    raise componentDoesNotExist(id, compDesc)

  let entity = world.entities[id.value]
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId
  let compId = world.componentIdFrom typeof compDesc
  let ecsSeqAny = archetype.componentLists[compId]

  type Retype = EcsSeq[T]
  cast[Retype](ecsSeqAny)[archetypeEntityId]


iterator component*[T](world: var World, id: Id, compDesc: typedesc[Write[T]]): var T =
  ## Write access to a single component of an entity.
  ## An iterator is used to ensure fast and safe access to the component.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.addEntity (Character(name: "Marcus"),)

    for character in w.component(marcus, Write[Character]):
      character.name = "Mark"

    assert w.readComponent(marcus, Character).name == "Mark"

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


proc readComponents*[T: tuple](world: var World, id: Id, tup: typedesc[T]): T =
  ## Direct read access to multiple components of an entity.
  ## The `T` tuple must contain no `Write`, `Opt`, or `Not` accessors.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.addEntity (Character(name: "Marcus"), Weapon(name: "Sword"), Spellbook(spells: @["Fireball", "Ice Storm", "Lightning"]))
    let (weapon, spellbook) = w.readComponents(marcus, (Weapon, Spellbook))
    assert weapon.name == "Sword"
    assert spellbook.spells == @["Fireball", "Ice Storm", "Lightning"]

  world.checkEntityExists(id)

  let entity = world.entities[id.value]
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId

  var found = true

  tup.fieldTypes:
    if not world.hasComponent(id, typeof FieldType):
      raise componentsDoNotExist(id, tup)

  world.buildReadTuple(tup, archetype, archetypeEntityId)


iterator components*[T: tuple](world: var World, id: Id, tup: typedesc[T]): tup.accessTuple =
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
    let marcus = w.addEntity (Character(name: "Marcus"), Weapon(name: "Sword"), Spellbook(spells: @["Fireball", "Ice Storm", "Lightning"]))

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


proc addComponent*[T](world: var World, id: Id, component: T) =
  ## Add a component to an entity
  runnableExamples:
    import examples
    import show

    var w = World()
    let marcus = w.addEntity (Id(), Character(name: "Marcus"),)
    w.addComponent(marcus, Health(health: 100, maxHealth: 100))

    assert w.hasComponent(marcus, Health) == true

  checkNotATuple(T)
  world.checkEntityExists(id)

  var entity = world.entities[id.value]
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
  world.entities[id.value] = entity


proc addEntity*[T: tuple](world: var World, components: T): Id {.discardable.} =
  ## Add an entity with components, use the special `Id` component to allow getting the entity's id in queries.
  ## `addEntity` also returns the entity's `Id`.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.addEntity (Id(), Character(name: "Marcus"))

    assert w.readComponent(marcus, Id) == marcus
    assert w.readComponent(marcus, Character).name == "Marcus"

  var archetype = world.archetypeFrom T
  let archetypeEntityId = archetype.add components
  let entity = Entity(archetypeId: archetype.id, archetypeEntityId: archetypeEntityId)
  let id = world.entities.add entity
  result = Id(value: id)

  for idComponent in world.component(result, Write[Id]):
    idComponent.value = id


proc addEntityWithSpecificId*(world: var World, id: Id) =
  ## Add an entity with a given id. The entity will have a single Id component.
  ## This is useful mostly for deserialization.
  ## **Note:** Any id above 0 is valid, however a greater id will allocate more memory.
  runnableExamples:
    import examples

    var w = World()
    w.addEntityWithSpecificId(Id(value: 10))

  checkIdIsValid(id)
  world.checkEntityDoesNotExist(id)

  var archetype = world.archetypeFrom (Id,)
  let archetypeEntityId = archetype.add (id,)
  let entity = Entity(archetypeId: archetype.id, archetypeEntityId: archetypeEntityId)
  world.entities[id.value] = entity


proc removeComponent*[T](world: var World, id: Id, compDesc: typedesc[T]) =
  ## Prepare a component for removal.
  ## A RemoveComponent component is added to the entity immediately, for it to be queried if necessary.
  ## The component is effectively removed when `processComponentRemovals` is called.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.addEntity (Character(name: "Marcus"), Weapon(name: "Sword"))
    w.removeComponent(marcus, Weapon)
    w.processComponentRemovals()

    assert w.hasComponent(marcus, Weapon) == false

  checkNotATuple(T)
  world.checkEntityExists(id)

  let entity = world.entities[id.value]
  let componentId = world.componentIdFrom typeof T

  if not entity.archetypeId.contains(componentId):
    raise newException(ValueError, "Component " & $T & " not found in Entity " & $id)

  world.addComponent(id, RemoveComponent[T]())
  let witnessId = world.componentIdFrom typeof RemoveComponent[T]

  world.toRemove.add (id, componentId)
  world.toRemove.add (id, witnessId)


proc removeEntity*(world: var World, id: Id) =
  ## Prepares an entity for removal.
  ## A RemoveEntity component is added to the entity immediately, for it to be queried if necessary.
  ## The entitiy is effectively removed when `processEntityRemovals` is called.
  runnableExamples:
    import examples

    var w = World()
    let marcus = w.addEntity (Character(name: "Marcus"),)
    w.removeEntity(marcus)
    w.processEntityRemovals()

    var query: Query[(Character,)]
    for (character,) in w.query(query):
      echo "Character: ", character.name
      raiseAssert "No character should exist."

  world.checkEntityExists(id)

  if world.hasComponent(id, RemoveEntity):
    return

  world.addComponent(id, RemoveEntity(id: id))


iterator query*[T: tuple](world: var World, query: var Query[T]): T.accessTuple =
  ## Query entities by components. Components are matched based on the query's type parameter.
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
    w.addEntity (Character(name: "Marcus"), Health(health: 100, maxHealth: 100), Weapon(name: "Sword"))
    w.addEntity (Character(name: "Elena"), Health(health: 80, maxHealth: 80), Amulet(name: "Arcane Stone"))
    w.addEntity (Character(name: "Brom"), Health(health: 140, maxHealth: 140), Armor(name: "Fur Armor"))

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


proc processEntityRemovals*(world: var World) =
  ## Effectively removes entities that have been prepared for removal.
  var query {.global.}: Query[(RemoveEntity,)]

  for (remove,) in world.query(query):
    let entity = world.entities[remove.id.value]
    var archetype = world.archetypes[entity.archetypeId]

    archetype.remove entity.archetypeEntityId
    world.entities.del remove.id.value


proc processComponentRemovals*(world: var World) =
  ## Effectively removes components that have been prepared for removal.
  for (id, componentId) in world.toRemove:
    var entity = world.entities[id.value]
    var previousArchetype = world.archetypes[entity.archetypeId]
    var nextArchetype = world.nextArchetypeRemovingFrom(previousArchetype, componentId)

    entity.archetypeId = nextArchetype.id
    entity.archetypeEntityId = previousArchetype.moveRemoving(entity.archetypeEntityId, nextArchetype)
    world.entities[id.value] = entity #TODO: is this really needed?

  world.toRemove = @[]


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
