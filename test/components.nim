# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/[examples, vecs]


suite "Components access should":
  setup:
    var world = World()
    let marcus = (Character(name: "Marcus", class: "Warrior"), Health(health: 120, maxHealth: 120), Weapon(name: "Sword", attack: 10))
    let elena = (Character(name: "Elena", class: "Mage"), Health(health: 80, maxHealth: 80))
    let grimm = (Character(name: "Grimm", class: "Paladin"), Health(health: 15, maxHealth: 100), Armor(name: "Fur Armor", defense: 5))
    let marcusId = world.add(marcus, Immediate)
    let elenaId = world.add(elena, Immediate)
    let grimmId = world.add(grimm, Immediate)


  test "read components of an entity":
    var called = false

    for (character, health) in world.components(marcusId, (Character, Health)):
      called = true
      checkpoint("Components access should allow reading components.")
      check character.name == "Marcus"
      check health.health == 120
      check health.maxHealth == 120

    checkpoint("Components access should have been called.")
    check called


  test "do not yield entities missing a required component":
    checkpoint("Entities missing a component required for read should not be yielded.")
    for (character, health) in world.components(elenaId, (Character, Weapon)):
      fail()

    checkpoint("Entities missing a component required for write should not be yielded.")
    for (character, health) in world.components(elenaId, (Character, Write[Weapon])):
      fail()


  test "write to components of an entity":
    checkpoint("Components access should allow writing components.")
    for (character, health) in world.components(marcusId, (Character, Write[Health])):
      check character.name == "Marcus"
      health.health = 0

    checkpoint("Values should be up to date.")
    let updatedHealth = world.read(marcusId, Health)
    check updatedHealth.health == 0


  test "access optional components of an entity":
    checkpoint("Optional access should be 'some' when the component exists.")
    for (character, weapon) in world.components(marcusId, (Character, Opt[Weapon])):
      weapon.isSomething:
        check character.name == "Marcus"
        check value.name == "Sword"
        check value.attack == 10
      weapon.isNothing:
        fail()

    checkpoint("Optional access should be 'none' when the component is missing.")
    for (character, weapon) in world.components(elenaId, (Character, Opt[Weapon])):
      weapon.isSomething:
        fail()
      weapon.isNothing:
        check character.name == "Elena"


  test "ignore entities with excluded components":
    checkpoint("Entities that have a component marked as 'Not' should not be yielded.")
    for (character,) in world.components(grimmId, (Character, Not[Armor])):
      fail()

    checkpoint("Entities that do not have a component marked as 'Not' should be yielded.")
    var yielded = false
    for (character,) in world.components(elenaId, (Character, Not[Armor])):
      yielded = true
      check character.name == "Elena"

    check yielded
