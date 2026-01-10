import json
import world
import tables
import queries
import components

proc createEntityTable*[T: tuple](world: var World, tup: typedesc[T]): Table[Id, seq[JsonNode]] =
  for name, value in fieldPairs default T:
    var query: Query[(Id, typeof value)]

    for (id, component) in world.query(query):
      if not result.hasKey(id):
        result[id] = @[]

      var jsonComponent = %*component
      jsonComponent["*component"] = newJString($typeof value)
      result[id].add jsonComponent

proc createJsonObject(entities: Table[Id, seq[JsonNode]]): JsonNode =
  result = newJObject()
  result["entities"] = newJArray()

  for (id, components) in entities.pairs:
    var entity = newJObject()
    entity["id"] = newJInt(id.id)
    entity["components"] = newJArray()

    for component in components:
      entity["components"].add component

    result["entities"].add entity

iterator iteratetJsonComponents(json: JsonNode, world: var World): (Id, JsonNode, string) =
  for entity in json["entities"]:
    let intId = entity["id"].getInt
    let id = Id(id: intId)
    let components = entity["components"]
    world.addEntityWithSpecificId id

    for jsonComponent in components:
      let componentType = jsonComponent["*component"].getStr
      jsonComponent.delete("*component")

      yield (id, jsonComponent, componentType)

proc addComponentFromJson[T: tuple](world: var World, id: Id, jsonComponent: JsonNode, componentType: string, tup: typedesc[T]) =
  for name, value in fieldPairs default T:
    if $(typeof value) == componentType:
      let componentToAdd = jsonComponent.to(typeof value)
      world.addComponent(id, componentToAdd)

proc serializeToText*[T: tuple](world: var World, tup: typedesc[T]): string =
  ## Serialize a world to a json string.
  ## Use a tuple to specify the components to serialize, do not include the Id component.
  ## Only entities with an Id component will be serialized.
  runnableExamples:
    import examples

    var w = World()
    w.addEntity (Id(), Character(name: "Marcus"), Health(health: 100, maxHealth: 100))
    w.addEntity (Id(), Character(name: "Elena"), Health(health: 80, maxHealth: 80))
    w.addEntity (Id(), Character(name: "Brom"), Health(health: 140, maxHealth: 140))
    echo w.serializeToText (Character, Health)

  let entities = createEntityTable(world, tup)
  let json = createJsonObject(entities)
  return json.pretty(2)

proc deserializeFromText*[T: tuple](text: string, tup: typedesc[T]): World =
  ## Deserialize a json string into a world.
  ## Use a tuple to specify the components to deserialize, do not include the Id component.
  ## All entities will be given an Id component.
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

    var w = deserializeFromText(text, (Id, Character, Health, Weapon, Amulet, Armor))
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
    result.addComponentFromJson(id, jsonComponent, componentType, T)

  result.cleanupEmptyArchetypes()
