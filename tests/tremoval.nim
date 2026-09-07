# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/[examples, vecs]


type RemovalPayload = ref object
  value: string


type RetainedComponent = object
  payload: RemovalPayload


suite "Component removal should":
  test "accept duplicate component types":
    var world = World()
    let entityId = world.add((Character(name: "Marcus"), Health(health: 100), Weapon(name: "Sword")), Immediate)

    world.remove(entityId, (Health, Weapon, Health), Immediate)

    check world.has(entityId)
    check world.read(entityId, Meta).id == entityId
    check world.read(entityId, Character).name == "Marcus"
    check not world.has(entityId, Health)
    check not world.has(entityId, Weapon)


  test "retain reference values when removal creates and then reuses a destination":
    var world = World()
    let firstPayload = RemovalPayload(value: "First")
    let secondPayload = RemovalPayload(value: "Second")
    let firstId = world.add((RetainedComponent(payload: firstPayload), Health(health: 100), Character(name: "Marcus"), Weapon(name: "Sword")), Immediate)
    let secondId = world.add((RetainedComponent(payload: secondPayload), Health(health: 80), Character(name: "Elena"), Weapon(name: "Staff")), Immediate)

    world.remove(firstId, (Weapon, Health), Immediate)
    world.remove(secondId, (Health, Weapon), Immediate)
    GC_fullCollect()

    var query: Query[(Meta, Character, RetainedComponent)]
    var entityCount = 0

    for (meta, character, retained) in world.query(query):
      inc entityCount
      check not world.has(meta.id, Health)
      check not world.has(meta.id, Weapon)

      if meta.id == firstId:
        check character.name == "Marcus"
        check retained.payload == firstPayload
        check retained.payload.value == "First"
      else:
        check meta.id == secondId
        check character.name == "Elena"
        check retained.payload == secondPayload
        check retained.payload.value == "Second"

    check entityCount == 2


  test "retain reference values when destination columns have a different order":
    var world = World()
    let existingPayload = RemovalPayload(value: "Existing")
    let movedPayload = RemovalPayload(value: "Moved")
    let existingId = world.add((Character(name: "Elena"), RetainedComponent(payload: existingPayload)), Immediate)
    let movedId = world.add((RetainedComponent(payload: movedPayload), Health(health: 100), Character(name: "Marcus"), Weapon(name: "Sword")), Immediate)

    world.remove(movedId, (Weapon, Health), Immediate)
    GC_fullCollect()

    check world.read(existingId, Character).name == "Elena"
    check world.read(existingId, RetainedComponent).payload == existingPayload
    check world.read(existingId, RetainedComponent).payload.value == "Existing"
    check world.read(movedId, Meta).id == movedId
    check world.read(movedId, Character).name == "Marcus"
    check world.read(movedId, RetainedComponent).payload == movedPayload
    check world.read(movedId, RetainedComponent).payload.value == "Moved"
    check not world.has(movedId, Health)
    check not world.has(movedId, Weapon)


  test "preserve a pending addition across immediate removal":
    var world = World()
    let entityId = world.add((Character(name: "Marcus"), Health(health: 100)), Immediate)
    world.add(entityId, Weapon(name: "Sword", attack: 10))

    world.remove(entityId, Health, Immediate)

    check not world.has(entityId, Health)
    check not world.has(entityId, Weapon)
    check world.read(entityId, Character).name == "Marcus"

    world.consolidate()

    check not world.has(entityId, Health)
    check world.read(entityId, Meta).id == entityId
    check world.read(entityId, Character).name == "Marcus"
    check world.read(entityId, Weapon).name == "Sword"
    check world.read(entityId, Weapon).attack == 10
