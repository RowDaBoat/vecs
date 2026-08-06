# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import std/tables
import world
import id
import queries


proc remappedEntityId(entityId: EntityId, mapping: Table[EntityId, EntityId]): EntityId =
  if entityId in mapping:
    mapping[entityId]
  else:
    EntityId()


proc remapIds[T](value: var T, mapping: Table[EntityId, EntityId]) =
  when T is Id:
    value.entityId = remappedEntityId(value.entityId, mapping)
  elif T is EntityId:
    value = remappedEntityId(value, mapping)
  elif T is string or T is seq[uint8]:
    discard
  elif T is seq or T is array:
    for item in value.mitems:
      remapIds(item, mapping)
  elif T is object or T is tuple:
    for name, field in fieldPairs(value):
      remapIds(field, mapping)
  else:
    discard


proc allEntityIds(world: var World): seq[EntityId] =
  var query: Query[(Meta,)]

  for (meta,) in world.query(query):
    result.add meta.id


proc copyComponents[T: tuple](
  source: var World,
  destination: var World,
  sourceId, destinationId: EntityId,
  mapping: Table[EntityId, EntityId],
  components: typedesc[T]
) =
  for name, value in fieldPairs default T:
    if source.has(sourceId, typeof value):
      var component = source.read(sourceId, typeof value)
      remapIds(component, mapping)
      destination.add(destinationId, component, Immediate)


proc add*[T: tuple](
  world: var World,
  other: var World,
  ids: seq[EntityId],
  components: typedesc[T]
): Table[EntityId, EntityId] {.discardable.} =
  for id in ids:
    result[id] = world.addEmpty()

  for id in ids:
    copyComponents(other, world, id, result[id], result, T)


proc add*[T: tuple](
  world: var World,
  other: var World,
  components: typedesc[T]
): Table[EntityId, EntityId] {.discardable.} =
  world.add(other, other.allEntityIds(), components)
