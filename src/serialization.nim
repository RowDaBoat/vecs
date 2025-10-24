import json
import world
import tables
import queries/query
import show

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
  let entities = createEntityTable(world, tup)
  let json = createJsonObject(entities)
  return json.pretty(2)

proc deserializeFromText*[T: tuple](text: string, tup: typedesc[T]): World =
  let json = parseJson(text)
  result = World()

  for (id, jsonComponent, componentType) in iteratetJsonComponents(json, result):
    result.addComponentFromJson(id, jsonComponent, componentType, T)

  result.cleanupEmptyArchetypes()


type Character = object
  name: string
  class: string

type Health = object
  health: int
  maxHealth: int

proc test(world: var World) =
  var query: Query[(Id, Character, Health)]
  for (id, character, health) in world.query(query):
    echo id, " ", character, " ", health

var w = World()

w.addEntity (
  Id(),
  Character(name: "Mark", class: "Rover"),
  Health(health: 100, maxHealth: 100)
)

w.addEntity (
  Id(),
  Character(name: "Velk", class: "Mancer"),
  Health(health: 50, maxHealth: 50)
)
echo w.show (Id, Character, Health)
w.test

echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "

let text = w.serializeToText (Character, Health)
echo text

w = deserializeFromText(text, (Character, Health))
echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
echo w.show (Id, Character, Health)
w.test

echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
echo w.show (Id, Character, Health)
w.test
