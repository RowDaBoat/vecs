# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import std/assertions
import ../src/[examples, vecs, operationmodes]


suite "Immediate operations should":
  setup:
    var world = World()
    var marcus = (Character(name: "Marcus"), Health(health: 100, maxHealth: 100))
    let elena = (Character(name: "Elena"), Health(health: 80, maxHealth: 80))
    let marcusId = world.add(marcus, Immediate)


  test "add an empty entity":
    let emptyId = world.addEmpty()

    checkpoint("Empty entity should exist with only Meta.")
    check world.has(emptyId)
    check world.read(emptyId, Meta).id == emptyId


  test "add multiple empty entities with unique ids":
    let firstId = world.addEmpty()
    let secondId = world.addEmpty()

    checkpoint("Each empty entity should have a unique id.")
    check firstId != secondId
    check world.has(firstId)
    check world.has(secondId)


  test "add components to an empty entity":
    let emptyId = world.addEmpty()
    world.add(emptyId, Character(name: "Ghost"), Immediate)

    checkpoint("Empty entity should now have the added component.")
    check world.has(emptyId, Character)
    check world.read(emptyId, Character).name == "Ghost"


  test "add entities immediately":
    let elenaId = world.add(elena, Immediate)

    checkpoint("Elena should exist and have components immediately.")
    check world.has(elenaId)
    check world.has(elenaId, Character)
    check world.has(elenaId, Health)


  test "remove entities immediately":
    world.remove(marcusId, Immediate)

    checkpoint("Marcus should not exist.")
    check not world.has(marcusId)


  test "add a component immediately":
    var sword = (Weapon(name: "Sword", attack: 10))
    world.add(marcusId, sword, Immediate)

    checkpoint("Marcus should have a weapon.")
    check world.has(marcusId, Weapon)


  test "add multiple components immediately":
    var sword = (Weapon(name: "Sword", attack: 10))
    var shield = (Shield(name: "Shield", defense: 15))
    world.add(marcusId, (sword, shield), Immediate)

    checkpoint("Marcus should have a weapon and a shield.")
    check world.has(marcusId, Weapon)
    check world.has(marcusId, Shield)


  test "remove a component immediately":
    world.remove(marcusId, Health, Immediate)

    checkpoint("Marcus should not have a health component anymore.")
    check not world.has(marcusId, Health)


  test "remove multiple components immediately":
    world.remove(marcusId, (Character, Health), Immediate)

    checkpoint("Marcus should not have a health nor a character component anymore.")
    check not world.has(marcusId, Health)
    check not world.has(marcusId, Character)
