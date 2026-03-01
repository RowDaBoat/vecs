# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import json
import world
import tables
import queries


const BinarySerializationMagic = "VECSBIN1"


type BinaryReader = object
  data: seq[byte]
  position: int


proc invalidBinarySerialization(reason: string): ref Exception =
  newException(ValueError, "Invalid binary serialization payload: " & reason)


proc toByteSeq(data: openArray[byte]): seq[byte] =
  result = newSeq[byte](data.len)
  for index in 0..<data.len:
    result[index] = data[index]


proc writeUInt32(data: var seq[byte], value: uint32) =
  data.add byte(value and 0xFF'u32)
  data.add byte((value shr 8) and 0xFF'u32)
  data.add byte((value shr 16) and 0xFF'u32)
  data.add byte((value shr 24) and 0xFF'u32)


proc writeUInt64(data: var seq[byte], value: uint64) =
  data.add byte(value and 0xFF'u64)
  data.add byte((value shr 8) and 0xFF'u64)
  data.add byte((value shr 16) and 0xFF'u64)
  data.add byte((value shr 24) and 0xFF'u64)
  data.add byte((value shr 32) and 0xFF'u64)
  data.add byte((value shr 40) and 0xFF'u64)
  data.add byte((value shr 48) and 0xFF'u64)
  data.add byte((value shr 56) and 0xFF'u64)


proc writeString(data: var seq[byte], text: string) =
  if text.len > int(high(uint32)):
    raise newException(
      ValueError,
      "Cannot serialize a string longer than " & $high(uint32) & " bytes."
    )

  data.writeUInt32(text.len.uint32)
  for char in text:
    data.add byte(ord(char))


proc ensureRemaining(reader: BinaryReader, expectedBytes: int) =
  if expectedBytes < 0 or reader.position + expectedBytes > reader.data.len:
    raise invalidBinarySerialization("unexpected end of input.")


proc readUInt32(reader: var BinaryReader): uint32 =
  reader.ensureRemaining(4)
  result = uint32(reader.data[reader.position]) or
    (uint32(reader.data[reader.position + 1]) shl 8) or
    (uint32(reader.data[reader.position + 2]) shl 16) or
    (uint32(reader.data[reader.position + 3]) shl 24)
  inc reader.position, 4


proc readUInt64(reader: var BinaryReader): uint64 =
  reader.ensureRemaining(8)
  result = uint64(reader.data[reader.position]) or
    (uint64(reader.data[reader.position + 1]) shl 8) or
    (uint64(reader.data[reader.position + 2]) shl 16) or
    (uint64(reader.data[reader.position + 3]) shl 24) or
    (uint64(reader.data[reader.position + 4]) shl 32) or
    (uint64(reader.data[reader.position + 5]) shl 40) or
    (uint64(reader.data[reader.position + 6]) shl 48) or
    (uint64(reader.data[reader.position + 7]) shl 56)
  inc reader.position, 8


proc readString(reader: var BinaryReader): string =
  let length = int(reader.readUInt32())
  reader.ensureRemaining(length)
  result = newString(length)

  for index in 0..<length:
    result[index] = char(reader.data[reader.position + index])

  inc reader.position, length


proc readAndValidateMagic(reader: var BinaryReader) =
  reader.ensureRemaining(BinarySerializationMagic.len)

  for expected in BinarySerializationMagic:
    let actual = char(reader.data[reader.position])
    inc reader.position

    if actual != expected:
      raise invalidBinarySerialization("invalid magic header.")


proc createEntityTable*[T: tuple](world: var World, tup: typedesc[T]): Table[EntityId, seq[JsonNode]] =
  for name, value in fieldPairs default T:
    var query: Query[(Meta, typeof value)]

    for (meta, component) in world.query(query):
      if not result.hasKey(meta.id):
        result[meta.id] = @[]

      var jsonComponent = %*component
      jsonComponent["*component"] = newJString($typeof value)
      result[meta.id].add jsonComponent


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


proc serializeToBinary*[T: tuple](world: var World, tup: typedesc[T]): seq[byte] =
  ## Serialize a world into binary data.
  ## Use a tuple to specify the components to serialize, do not include the Meta component.
  runnableExamples:
    import examples

    var w = World()
    w.add((Character(name: "Marcus"), Health(health: 100, maxHealth: 100)), Immediate)

    let data = w.serializeToBinary((Character, Health))
    assert data.len > 0

  let entities = createEntityTable(world, tup)

  if entities.len > int(high(uint32)):
    raise newException(
      ValueError,
      "Cannot serialize more than " & $high(uint32) & " entities."
    )

  for char in BinarySerializationMagic:
    result.add byte(ord(char))

  result.writeUInt32(entities.len.uint32)

  for (id, components) in entities.pairs:
    if id.value < 0:
      raise newException(ValueError, "Cannot serialize an invalid entity id: " & $id)

    if components.len > int(high(uint32)):
      raise newException(
        ValueError,
        "Cannot serialize more than " & $high(uint32) & " components in a single entity."
      )

    result.writeUInt64(id.value.uint64)
    result.writeUInt32(components.len.uint32)

    for component in components:
      result.writeString($component)


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


proc deserializeFromBinary*[T: tuple](data: openArray[byte], tup: typedesc[T]): World =
  ## Deserialize binary data into a world.
  ## Use a tuple to specify the components to deserialize, do not include the Meta component.
  ## All entities will be given a proper Meta component.
  runnableExamples:
    import examples

    var w = World()
    w.add((Character(name: "Marcus"), Health(health: 100, maxHealth: 100)), Immediate)

    let data = w.serializeToBinary((Character, Health))
    var restored = deserializeFromBinary(data, (Character, Health))
    assert restored.has(EntityId(value: 0), Character)

  var reader = BinaryReader(data: toByteSeq(data))
  reader.readAndValidateMagic()

  let entityCount = int(reader.readUInt32())
  result = World()

  for i in 0..<entityCount:
    let intId = reader.readUInt64()

    if intId > uint64(high(int)):
      raise invalidBinarySerialization("entity id does not fit in an int.")

    let id = EntityId(value: int(intId))
    result.addWithSpecificId(id)

    let componentCount = int(reader.readUInt32())
    for j in 0..<componentCount:
      var jsonComponent = parseJson(reader.readString())

      if jsonComponent.kind != JObject or not jsonComponent.hasKey("*component"):
        raise invalidBinarySerialization(
          "component entries must be json objects with a \"*component\" key."
        )

      let componentType = jsonComponent["*component"].getStr
      jsonComponent.delete("*component")
      result.addFromJson(id, jsonComponent, componentType, T)

  if reader.position != reader.data.len:
    raise invalidBinarySerialization("payload has trailing bytes.")

  result.cleanupEmptyArchetypes()
