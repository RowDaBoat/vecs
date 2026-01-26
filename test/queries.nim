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
    let marcusId = world.add(marcus, Immediate)
    let elenaId = world.add(elena, Immediate)
    let grimmId = world.add(grimm, Immediate)

  test "query components for removal":

    world.remove(elenaId, Health)
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

    world.remove(grimmId, Health, Immediate)

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


  test "query for deferred component addition":
    var sword = Weapon(name: "Excalibur", attack: 25)
    world.add((sword,))

    checkpoint("Query should return nothing before consolidation.")
    var query: Query[(Meta, Weapon)]
    var foundCount = 0
    for (meta, weapon) in world.query(query):
      inc foundCount
    check foundCount == 0

    world.consolidate()

    checkpoint("Query should return the component with correct properties after consolidation.")
    foundCount = 0

    for (meta, weapon) in world.query(query):
      inc foundCount
      check weapon.name == "Excalibur"
      check weapon.attack == 25

    check foundCount == 1

  test "query for removal should not yield added components":
    checkpoint("Adding a component should not make it appear in removal query.")
    var sword = Weapon(name: "Sword", attack: 10)
    world.add(elenaId, sword)

    var removalCount = 0
    for (meta, weapon) in world.queryForRemoval(Weapon):
      inc removalCount

    checkpoint("Nothing should be yielded from removal query when component is added.")
    check removalCount == 0
