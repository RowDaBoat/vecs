# ISC License
# Copyright (c) 2025 RowDaBoat

import unittest, sets
import ../src/[examples, vecs]

suite "Queries should":
  setup:
    var world = World()
    let marcus = (Character(name: "Marcus", class: "Warrior"), Health(health: 120, maxHealth: 120))
    let elena = (Character(name: "Elena", class: "Mage"), Health(health: 80, maxHealth: 80))
    let grimm = (Character(name: "Grimm", class: "Paladin"), Health(health: 15, maxHealth: 100))
    let marcusId = world.addEntity(marcus, Immediate)
    let elenaId = world.addEntity(elena, Immediate)
    let grimmId = world.addEntity(grimm, Immediate)

  test "query components for removal":

    world.removeComponent(elenaId, Health)
    var removeCount = 0

    for (meta, health) in world.queryForRemoval(Health):
      inc removeCount
      checkpoint("Health should be removed from Elena")
      check meta.id == elenaId
      checkpoint("Only one compnent should be removed")
      check removeCount == 1

    check removeCount == 1

    world.consolidate()

    checkpoint("After consolidation, no more components should appear in a query for components to be removed")
    for (meta, health) in world.queryForRemoval(Health):
      fail()

    world.removeComponent(grimmId, Health, Immediate)

    checkpoint("After an immediate removal, no components should appear in a query for components to be removed")
    for (meta, health) in world.queryForRemoval(Health):
      fail()

  test "query components for reading":
    var query: Query[(Meta, Character, Health)]
    var characters = @[marcusId, elenaId, grimmId].toHashSet

    checkpoint("All 3 characters should be read")
    for (meta, character, health) in world.query(query):
      if meta.id notin characters:
        fail()
