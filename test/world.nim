# ISC License
# Copyright (c) 2025 RowDaBoat

import unittest
import std/assertions
import ../src/examples
import ../src/vecs


suite "World should":
  setup:
    var world = World()
    var marcus = (Character(name: "Marcus"), Health(health: 100, maxHealth: 100))
    let elena = (Character(name: "Elena"), Health(health: 80, maxHealth: 80))
    let marcusId = world.add(marcus, OperationMode.Immediate)


  test "add entities immediately":
    let elenaId = world.add(elena, OperationMode.Immediate)

    checkpoint("Elena should exist and have components immediately.")
    check world.has(elenaId)
    check world.has(elenaId, Character)
    check world.has(elenaId, Health)


  test "deferr addition of entities until consolidation":
    let elenaId = world.add elena

    checkpoint("Elena should exist, but not have components yet.")
    check world.has(elenaId)
    check not world.has(elenaId, Character)
    check not world.has(elenaId, Health)

    world.consolidate()

    checkpoint("Elena should exist and have components now.")
    check world.has(elenaId)
    check world.has(elenaId, Character)
    check world.has(elenaId, Health)


  test "remove entities immediately":
    world.remove(marcusId, OperationMode.Immediate)

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)


  test "deferr removal of entities until consolidation":
    world.remove marcusId

    checkpoint("Marcus should still exist.")
    check world.has(marcusId)

    world.consolidate()

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)


  test "add a component immediately":
    var sword = (Weapon(name: "Sword", attack: 10))
    world.add(marcusId, sword, OperationMode.Immediate)

    checkpoint("Marcus should have a weapon.")
    check world.has(marcusId, Weapon)


  test "deferr addition of a component until consolidation":
    var sword = (Weapon(name: "Sword", attack: 10))
    world.add(marcusId, sword)

    checkpoint("Marcus should not have a weapon yet.")
    check not world.has(marcusId, Weapon)

    world.consolidate()

    checkpoint("Marcus should have a weapon now.")
    check world.has(marcusId, Weapon)


  test "add multiple components immediately":
    var sword = (Weapon(name: "Sword", attack: 10))
    var shield = (Shield(name: "Shield", defense: 15))
    world.add(marcusId, (sword, shield), OperationMode.Immediate)

    checkpoint("Marcus should have a weapon and a shield.")
    check world.has(marcusId, Weapon)
    check world.has(marcusId, Shield)


  test "deferr addition of multiple components until consolidation":
    var sword = (Weapon(name: "Sword", attack: 10))
    var shield = (Shield(name: "Shield", defense: 15))
    world.add(marcusId, (sword, shield))

    checkpoint("Marcus should not have a weapon nor a shieldyet.")
    check not world.has(marcusId, Weapon)
    check not world.has(marcusId, Shield)

    world.consolidate()

    checkpoint("Marcus should have a weapon and a shield now.")
    check world.has(marcusId, Weapon)
    check world.has(marcusId, Shield)


  test "remove a component immediately":
    world.remove(marcusId, Health, OperationMode.Immediate)

    checkpoint("Marcus should not have a health component anymore.")
    check not world.has(marcusId, Health)


  test "deferr removal of a component until consolidation":
    world.remove(marcusId, Health)

    checkpoint("Marcus should still have a health component.")
    check world.has(marcusId, Health)

    world.consolidate()

    checkpoint("Marcus should not have a health component anymore.")
    check not world.has(marcusId, Health)


  test "remove multiple components immediately":
    world.remove(marcusId, (Character, Health), OperationMode.Immediate)

    checkpoint("Marcus should not have a health nor a character component anymore.")
    check not world.has(marcusId, Health)
    check not world.has(marcusId, Character)


  test "deferr the removal of multiple components until consolidation":
    world.remove(marcusId, (Character, Health))

    checkpoint("Marcus should still have character and health components.")
    check world.has(marcusId, Character)
    check world.has(marcusId, Health)

    world.consolidate()

    checkpoint("Marcus should not have a health nor a character component anymore.")
    check not world.has(marcusId, Health)
    check not world.has(marcusId, Character)

  test "add a component after a consolidated addition of an entity":
    var w = World()
    w.add (Character(name: "Marcus"),)
    w.consolidate()

    var disarmed {.global.}: Query[(Meta, Character, Not[Weapon])]
    for (meta, character) in w.query(disarmed):
      w.add(meta.id, Weapon(name: "Sword", attack: 10))

    w.consolidate()


  test "add an entity in immediate mode, and then add component on a query":
    var w = World()
    let id = w.add (Character(name: "Marcus"), Immediate)

    var weaponAdded = false
    var disarmed {.global.}: Query[(Meta, Not[Weapon])]
    for (meta,) in w.query(disarmed):
      weaponAdded = true
      w.add(meta.id, Weapon(name: "Sword", attack: 10))

    checkpoint("Weapon should have been added in the query.")
    check weaponAdded

    checkpoint("Marcus should not have a weapon yet.")
    check not w.has(id, Weapon)

    w.consolidate()

    checkpoint("Marcus should have a weapon.")
    check w.has(id, Weapon)


  test "make deferred components queriable only after consolidation":
    var sword = (Weapon(name: "Sword", attack: 10))
    world.add(marcusId, sword)

    checkpoint("Marcus should not have a weapon yet.")
    var query: Query[(Meta, Character, Weapon)]
    for (meta, character, weapon) in world.query(query):
      fail()

    world.consolidate()

    var count = 0
    for (meta, character, weapon) in world.query(query):
      inc count
      check character.name == "Marcus"
      check weapon.name == "Sword"
      check weapon.attack == 10

    checkpoint("Marcus should now have a weapon.")
    check count == 1


  test "raise a defect when adding two components of the same type in deferred mode":
    var w = World()
    var failed = false
    let id = w.add((Character(name: "Marcus"),), Immediate)

    checkpoint("Deferr the addition of two components of the same type.")
    w.add(id, Weapon(name: "Sword", attack: 10))
    w.add(id, Weapon(name: "Axe", attack: 15))

    checkpoint("Expect a 'DoubleAddDefect' error.")
    try:
      w.consolidate()
    except DoubleAddDefect:
      failed = true
    except CatchableError:
      checkpoint("No 'DoubleAddDefect' error was raised.")
      fail()

    assert failed
