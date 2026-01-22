# ISC License
# Copyright (c) 2025 RowDaBoat

import unittest
import ../src/examples
import ../src/vecs

suite "World should":
  setup:
    var world = World()
    var marcus = (Character(name: "Marcus"), Health(health: 100, maxHealth: 100))
    let elena = (Character(name: "Elena"), Health(health: 80, maxHealth: 80))
    let marcusId = world.addEntity(marcus, OperationMode.Immediate)


  test "add entities immediately":
    let elenaId = world.addEntity(elena, OperationMode.Immediate)

    checkpoint("Elena should exist and have components immediately.")
    check world.hasEntity(elenaId)
    check world.hasComponent(elenaId, Character)
    check world.hasComponent(elenaId, Health)


  test "deferr addition of entities until consolidation":
    let elenaId = world.addEntity elena

    checkpoint("Elena should exist, but not have components yet.")
    check world.hasEntity(elenaId)
    check not world.hasComponent(elenaId, Character)
    check not world.hasComponent(elenaId, Health)

    world.consolidate()

    checkpoint("Elena should exist and have components now.")
    check world.hasEntity(elenaId)
    check world.hasComponent(elenaId, Character)
    check world.hasComponent(elenaId, Health)


  test "remove entities immediately":
    world.removeEntity(marcusId, OperationMode.Immediate)

    checkpoint("Marcus should not exist.")
    check not world.hasEntity(marcusId)


  test "deferr removal of entities until consolidation":
    world.removeEntity marcusId

    checkpoint("Marcus should still exist.")
    check world.hasEntity(marcusId)

    world.consolidate()

    checkpoint("Marcus should not exist.")
    check not world.hasEntity(marcusId)


  test "add a component immediately":
    var sword = (Weapon(name: "Sword", attack: 10))
    world.addComponent(marcusId, sword, OperationMode.Immediate)

    checkpoint("Marcus should have a weapon.")
    check world.hasComponent(marcusId, Weapon)


  test "deferr addition of a component until consolidation":
    var sword = (Weapon(name: "Sword", attack: 10))
    world.addComponent(marcusId, sword)

    checkpoint("Marcus should not have a weapon yet.")
    check not world.hasComponent(marcusId, Weapon)

    world.consolidate()

    checkpoint("Marcus should have a weapon now.")
    check world.hasComponent(marcusId, Weapon)


  test "add multiple components immediately":
    var sword = (Weapon(name: "Sword", attack: 10))
    var shield = (Shield(name: "Shield", defense: 15))
    world.addComponents(marcusId, (sword, shield), OperationMode.Immediate)

    checkpoint("Marcus should have a weapon and a shield.")
    check world.hasComponent(marcusId, Weapon)
    check world.hasComponent(marcusId, Shield)


  test "deferr addition of multiple components until consolidation":
    var sword = (Weapon(name: "Sword", attack: 10))
    var shield = (Shield(name: "Shield", defense: 15))
    world.addComponents(marcusId, (sword, shield))

    checkpoint("Marcus should not have a weapon nor a shieldyet.")
    check not world.hasComponent(marcusId, Weapon)
    check not world.hasComponent(marcusId, Shield)

    world.consolidate()

    checkpoint("Marcus should have a weapon and a shield now.")
    check world.hasComponent(marcusId, Weapon)
    check world.hasComponent(marcusId, Shield)


  test "remove a component immediately":
    world.removeComponent(marcusId, Health, OperationMode.Immediate)

    checkpoint("Marcus should not have a health component anymore.")
    check not world.hasComponent(marcusId, Health)


  test "deferr removal of a component until consolidation":
    world.removeComponent(marcusId, Health)

    checkpoint("Marcus should still have a health component.")
    check world.hasComponent(marcusId, Health)

    world.consolidate()

    checkpoint("Marcus should not have a health component anymore.")
    check not world.hasComponent(marcusId, Health)


  test "remove multiple components immediately":
    world.removeComponents(marcusId, (Character, Health), OperationMode.Immediate)

    checkpoint("Marcus should not have a health nor a character component anymore.")
    check not world.hasComponent(marcusId, Health)
    check not world.hasComponent(marcusId, Character)


  test "deferr the removal of multiple components until consolidation":
    world.removeComponents(marcusId, (Character, Health))

    checkpoint("Marcus should still have character and health components.")
    check world.hasComponent(marcusId, Character)
    check world.hasComponent(marcusId, Health)

    world.consolidate()

    checkpoint("Marcus should not have a health nor a character component anymore.")
    check not world.hasComponent(marcusId, Health)
    check not world.hasComponent(marcusId, Character)
