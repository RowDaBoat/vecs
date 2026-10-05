# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/[examples, vecs, operationmodes]


proc danglingIds(world: var World): seq[EntityId] =
  var everyEntity: Query[(Meta,)]

  for (meta,) in world.query(everyEntity):
    if not world.has(meta.id):
      result.add meta.id


proc entityCount(world: var World): int =
  var everyEntity: Query[(Meta,)]

  for (meta,) in world.query(everyEntity):
    inc result


suite "Consolidation should":
  setup:
    var world = World()
    let marcusId = world.add((Character(name: "Marcus"),), Immediate)


  test "drop a deferred addition enqueued before a deferred entity removal":
    world.add(marcusId, Weapon(name: "Sword", attack: 10))
    world.remove(marcusId)
    world.consolidate()

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)

    checkpoint("No row should survive Marcus's removal.")
    check world.entityCount() == 0
    check world.danglingIds().len == 0


  test "drop a deferred addition enqueued after a deferred entity removal":
    world.remove(marcusId)
    world.add(marcusId, Weapon(name: "Sword", attack: 10))
    world.consolidate()

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)

    checkpoint("No row should survive Marcus's removal.")
    check world.entityCount() == 0
    check world.danglingIds().len == 0


  test "drop a deferred component removal enqueued after a deferred entity removal":
    world.remove(marcusId)
    world.remove(marcusId, Character)
    world.consolidate()

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)

    checkpoint("No row should survive Marcus's removal.")
    check world.entityCount() == 0
    check world.danglingIds().len == 0


  test "drop a deferred addition targeting an entity removed immediately":
    world.add(marcusId, Weapon(name: "Sword", attack: 10))
    world.remove(marcusId, Immediate)
    world.consolidate()

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)

    checkpoint("No row should survive Marcus's removal.")
    check world.entityCount() == 0
    check world.danglingIds().len == 0


  test "drop a second deferred entity removal of the same entity":
    world.remove(marcusId)
    world.remove(marcusId)
    world.consolidate()

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)

    let elenaId = world.add((Character(name: "Elena"),), Immediate)
    let bromId = world.add((Character(name: "Brom"),), Immediate)

    checkpoint("Elena and Brom should not share an entity slot.")
    check elenaId != bromId
    check world.has(elenaId)
    check world.has(bromId)

    checkpoint("Elena and Brom should be the only rows left.")
    check world.entityCount() == 2
    check world.danglingIds().len == 0


  test "drop an after(query) addition targeting an entity removed in the same query":
    var characters {.global.}: Query[(Meta, Character)]

    for (meta, character) in world.query(characters):
      world.remove(meta.id, after(characters))
      world.add(meta.id, Weapon(name: "Sword", attack: 10), after(characters))

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)

    checkpoint("No row should survive Marcus's removal.")
    check world.entityCount() == 0
    check world.danglingIds().len == 0


  test "drop an after(query) component removal targeting an entity removed in the same query":
    var characters {.global.}: Query[(Meta, Character)]

    for (meta, character) in world.query(characters):
      world.remove(meta.id, after(characters))
      world.remove(meta.id, Character, after(characters))

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)

    checkpoint("No row should survive Marcus's removal.")
    check world.entityCount() == 0
    check world.danglingIds().len == 0


  test "keep queried ids valid when a removed entity's slot is reused":
    world.remove(marcusId)
    world.add(marcusId, Weapon(name: "Sword", attack: 10))
    world.consolidate()

    let elenaId = world.add((Character(name: "Elena"),), Immediate)

    checkpoint("Elena should reuse Marcus's entity slot with a fresh generation.")
    check elenaId.value == marcusId.value
    check elenaId != marcusId

    checkpoint("Every queried id must belong to a living entity.")
    check world.danglingIds().len == 0

    var queriedIds: seq[EntityId] = @[]
    var characters: Query[(Meta, Character)]

    for (meta, character) in world.query(characters):
      queriedIds.add meta.id

    checkpoint("Only Elena should be queried.")
    check queriedIds == @[elenaId]
