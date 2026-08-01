# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import json
import world
import tables
import queries
import cborious


proc createJsonObject(entities: Table[EntityId, seq[JsonNode]]): JsonNode =
  result = newJObject()
  result["entities"] = newJArray()

  for (id, components) in entities.pairs:
    var entity = newJObject()
    entity["id"] = newJInt(id.value)
    entity["components"] = newJArray()

    for component in components:
      entity["components"].add component

    result["entities"].add entity


iterator iteratetJsonComponents(json: JsonNode, world: var World): (EntityId, JsonNode, string) =
  for entity in json["entities"]:
    let intId = entity["id"].getInt
    let id = EntityId(value: intId)
    let components = entity["components"]
    world.addWithSpecificId id

    for jsonComponent in components:
      let componentType = jsonComponent["*component"].getStr
      jsonComponent.delete("*component")

      yield (id, jsonComponent, componentType)


proc addFromJson[T: tuple](world: var World, id: EntityId, jsonComponent: JsonNode, componentType: string, tup: typedesc[T]) =
  for name, value in fieldPairs default T:
    if $(typeof value) == componentType:
      let componentToAdd = jsonComponent.to(typeof value)
      world.add(id, componentToAdd, Immediate)


proc createEntityTable*[T: tuple](world: var World, tup: typedesc[T]): Table[EntityId, seq[JsonNode]] =
  for name, value in fieldPairs default T:
    var query: Query[(Meta, typeof value)]

    for (meta, component) in world.query(query):
      if not result.hasKey(meta.id):
        result[meta.id] = @[]

      var jsonComponent = %*component
      jsonComponent["*component"] = newJString($typeof value)
      result[meta.id].add jsonComponent


proc serializeToText*[T: tuple](world: var World, tup: typedesc[T]): string =
  ## Serialize a world to a json string.
  ## Use a tuple to specify the components to serialize, do not include the Meta component.
  runnableExamples:
    import examples

    var w = World()
    w.add((Character(name: "Marcus"), Health(health: 100, maxHealth: 100)), Immediate)
    w.add((Character(name: "Elena"), Health(health: 80, maxHealth: 80)), Immediate)
    w.add((Character(name: "Brom"), Health(health: 140, maxHealth: 140)), Immediate)
    echo w.serializeToText (Character, Health)

  let entities = createEntityTable(world, tup)
  let json = createJsonObject(entities)
  return json.pretty(2)


proc deserializeFromText*[T: tuple](text: string, tup: typedesc[T]): World =
  ## Deserialize a json string into a world.
  ## Use a tuple to specify the components to deserialize, do not include the Meta component.
  ## All entities will be given a proper Meta component.
  runnableExamples:
    import examples

    let text = """
      { "entities": [
        { "id": 2, "components": [
          { "*component": "Character", "name": "Brom", "class": "" },
          { "*component": "Health", "health": 140, "maxHealth": 140 },
          { "*component": "Weapon", "name": "Battle Axe", "attack": 32 },
          { "*component": "Armor", "name": "Fur Armor", "defense": 15, "buffs": [] }
        ] },
        { "id": 0,
          "components": [
            { "*component": "Character", "name": "Marcus", "class": "" },
            { "*component": "Health", "health": 100, "maxHealth": 100 },
            { "*component": "Weapon", "name": "Sword", "attack": 20 }
        ] },
        { "id": 1,
          "components": [
            { "*component": "Character", "name": "Elena", "class": "" },
            { "*component": "Health", "health": 80, "maxHealth": 80 },
            { "*component": "Amulet", "name": "Arcane Stone", "attack": 0, "magic": [] }
        ] }
      ] }
      """

    var w = deserializeFromText(text, (Character, Health, Weapon, Amulet, Armor))
    var characters = 0
    var weapons = 0
    var armors = 0
    var amulets = 0

    var query: Query[(Character, Health, Opt[Weapon], Opt[Amulet], Opt[Armor])]
    for (character, health, weapon, amulet, armor) in w.query(query):
      inc characters

      weapon.isSomething:
        inc weapons

      amulet.isSomething:
        inc amulets

      armor.isSomething:
        inc armors

    assert characters == 3
    assert weapons == 2
    assert armors == 1
    assert amulets == 1

  let json = parseJson(text)
  result = World()

  for (id, jsonComponent, componentType) in iteratetJsonComponents(json, result):
    result.addFromJson(id, jsonComponent, componentType, T)

  result.cleanupEmptyArchetypes()


proc encodeComponent[T](component: T): string =
  var stream = CborStream.init()
  var fieldCount = 0

  for _ in fields(component):
    inc fieldCount

  stream.cborPackInt(uint64(fieldCount + 1), CborMajor.Map)
  stream.cborPack("*component")
  stream.cborPack($typeof component)

  for name, value in fieldPairs(component):
    stream.cborPack(name)
    stream.cborPack(value)

  stream.data


proc createBinaryEntityTable[T: tuple](world: var World, tup: typedesc[T]): Table[EntityId, seq[string]] =
  for name, value in fieldPairs default T:
    var query: Query[(Meta, typeof value)]

    for (meta, component) in world.query(query):
      if not result.hasKey(meta.id):
        result[meta.id] = @[]

      result[meta.id].add encodeComponent(component)


proc writeBinaryEntities(stream: CborStream, entities: Table[EntityId, seq[string]]) =
  stream.cborPackInt(1, CborMajor.Map)
  stream.cborPack("entities")
  stream.cborPackInt(uint64(entities.len), CborMajor.Array)

  for (id, components) in entities.pairs:
    stream.cborPackInt(2, CborMajor.Map)
    stream.cborPack("id")
    stream.cborPack(id.value)
    stream.cborPack("components")
    stream.cborPackInt(uint64(components.len), CborMajor.Array)

    for componentBytes in components:
      stream.write(componentBytes)


proc serializeToBinary*[T: tuple](world: var World, tup: typedesc[T]): string =
  ## Serialize a world to a CBOR-encoded binary string.
  ## Use a tuple to specify the components to serialize, do not include the Meta component.
  let entities = createBinaryEntityTable(world, tup)
  var stream = CborStream.init()
  stream.writeBinaryEntities(entities)
  stream.data


proc readComponentTypeName(stream: CborStream): (string, int) =
  ## Reads a component map's header and its leading "*component" entry.
  ## Returns the component's type name and the count of fields left to read.
  let (major, ai) = stream.readInitialSkippingTags()
  doAssert major == CborMajor.Map
  let fieldCount = int(stream.readAddInfo(ai))

  var markerKey: string
  stream.cborUnpack(markerKey)
  var componentType: string
  stream.cborUnpack(componentType)

  (componentType, fieldCount - 1)


proc skipRemainingFields(stream: CborStream, count: int) =
  for _ in 0 ..< count:
    stream.skipCborMsg() # key
    stream.skipCborMsg() # value


proc setMatchingField[T](component: var T, name: string, stream: CborStream): bool =
  ## Reads the next value into `component`'s field named `name`, if any.
  ## Field types are primitives/seqs, so this avoids cborious's generic
  ## object/tuple decode, which errors out when instantiated from another module.
  for fieldName, fieldValue in fieldPairs(component):
    if fieldName == name:
      stream.cborUnpack(fieldValue)
      return true

  false


proc readRemainingFields[T](stream: CborStream, component: var T, count: int) =
  for _ in 0 ..< count:
    var key: string
    stream.cborUnpack(key)

    if not setMatchingField(component, key, stream):
      stream.skipCborMsg()


proc addComponentFromBinary[T: tuple](world: var World, id: EntityId, stream: CborStream, componentType: string, remainingFields: int, tup: typedesc[T]): bool =
  for name, value in fieldPairs default T:
    if $(typeof value) == componentType:
      var componentToAdd: typeof(value)
      stream.readRemainingFields(componentToAdd, remainingFields)
      world.add(id, componentToAdd, Immediate)
      return true

  false


proc readBinaryComponents[T: tuple](world: var World, id: EntityId, stream: CborStream, componentCount: int, tup: typedesc[T]) =
  for _ in 0 ..< componentCount:
    let (componentType, remainingFields) = stream.readComponentTypeName()
    let matched = world.addComponentFromBinary(id, stream, componentType, remainingFields, T)

    if not matched:
      stream.skipRemainingFields(remainingFields)


proc readBinaryEntities[T: tuple](world: var World, stream: CborStream, tup: typedesc[T]) =
  let (topMajor, topAi) = stream.readInitialSkippingTags()
  doAssert topMajor == CborMajor.Map
  discard stream.readAddInfo(topAi)

  var entitiesKey: string
  stream.cborUnpack(entitiesKey)

  let (arrayMajor, arrayAi) = stream.readInitialSkippingTags()
  doAssert arrayMajor == CborMajor.Array
  let entityCount = int(stream.readAddInfo(arrayAi))

  for _ in 0 ..< entityCount:
    let (entityMajor, entityAi) = stream.readInitialSkippingTags()
    doAssert entityMajor == CborMajor.Map
    discard stream.readAddInfo(entityAi)

    var idKey: string
    stream.cborUnpack(idKey)
    var idValue: int
    stream.cborUnpack(idValue)
    let id = EntityId(value: idValue)
    world.addWithSpecificId id

    var componentsKey: string
    stream.cborUnpack(componentsKey)

    let (componentsMajor, componentsAi) = stream.readInitialSkippingTags()
    doAssert componentsMajor == CborMajor.Array
    let componentCount = int(stream.readAddInfo(componentsAi))

    world.readBinaryComponents(id, stream, componentCount, T)


proc deserializeFromBinary*[T: tuple](data: string, tup: typedesc[T]): World =
  ## Deserialize a CBOR-encoded binary string into a world.
  ## Use a tuple to specify the components to deserialize, do not include the Meta component.
  ## All entities will be given a proper Meta component.
  var stream = CborStream.init(data)
  result = World()
  result.readBinaryEntities(stream, T)
  result.cleanupEmptyArchetypes()
