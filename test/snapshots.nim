# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/[examples, vecs]


suite "Snapshots should":
  setup:
    var world = World()
    let marcusId = world.add(
      (Character(name: "Marcus", class: "Warrior"),
       Health(health: 120, maxHealth: 120),
       Weapon(name: "Sword", attack: 10)),
      Immediate
    )


  test "restore component values after modification":
    let snap = world.snapshot(marcusId)

    for health in world.write(marcusId, Health):
      health.health = 0

    world.restore(snap)

    checkpoint("Health should be restored to snapshot values.")
    let restoredHealth = world.read(marcusId, Health)
    check restoredHealth.health == 120
    check restoredHealth.maxHealth == 120

    checkpoint("Unmodified components should keep their values.")
    let character = world.read(marcusId, Character)
    check character.name == "Marcus"


  test "restore all components after modification":
    let snap = world.snapshot(marcusId)

    for character in world.write(marcusId, Character):
      character.name = "Marcus the Changed"

    for weapon in world.write(marcusId, Weapon):
      weapon.attack = 99

    world.restore(snap)

    checkpoint("Character should be restored.")
    check world.read(marcusId, Character).name == "Marcus"

    checkpoint("Weapon should be restored.")
    check world.read(marcusId, Weapon).attack == 10


  test "re-add a component removed after snapshot":
    let snap = world.snapshot(marcusId)
    world.remove(marcusId, Weapon, Immediate)
    check not world.has(marcusId, Weapon)

    world.restore(snap)

    checkpoint("Weapon should be re-added with snapshot values.")
    check world.has(marcusId, Weapon)
    check world.read(marcusId, Weapon).name == "Sword"
    check world.read(marcusId, Weapon).attack == 10


  test "remove components added after snapshot":
    let snap = world.snapshot(marcusId)
    world.add(marcusId, Shield(name: "Kite Shield", defense: 15), Immediate)

    world.restore(snap)

    checkpoint("Shield added after snapshot should be removed.")
    check not world.has(marcusId, Shield)


  test "restore snapshot onto a different entity":
    let elenaId = world.add(
      (Character(name: "Elena", class: "Mage"), Health(health: 80, maxHealth: 80)),
      Immediate
    )
    let snap = world.snapshot(marcusId)

    world.restore(snap, elenaId)

    checkpoint("Elena should have Marcus's snapshot components.")
    check world.read(elenaId, Character) == Character(name: "Marcus", class: "Warrior")
    check world.read(elenaId, Health) == Health(health: 120, maxHealth: 120)
    check world.has(elenaId, Weapon)
    check world.read(elenaId, Weapon) == Weapon(name: "Sword", attack: 10)

    checkpoint("Marcus should be unchanged.")
    check world.read(marcusId, Character).name == "Marcus"
    check world.read(marcusId, Health).health == 120


  test "not capture the Meta component":
    let originalMeta = world.read(marcusId, Meta)
    let snap = world.snapshot(marcusId)

    world.restore(snap)

    checkpoint("Meta id should be unchanged after restore.")
    check world.read(marcusId, Meta).id == originalMeta.id
