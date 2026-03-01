# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/[examples, vecs]


proc createTestWorld(): World =
  result = World()

  let marcusId = EntityId(value: 10)
  let elenaId = EntityId(value: 3)
  let bromId = EntityId(value: 7)

  result.addWithSpecificId(marcusId)
  result.add(
    marcusId,
    (
      Character(name: "Marcus", class: "Warrior"),
      Health(health: 100, maxHealth: 100),
      Weapon(name: "Sword", attack: 20)
    ),
    Immediate
  )

  result.addWithSpecificId(elenaId)
  result.add(
    elenaId,
    (
      Character(name: "Elena", class: "Mage"),
      Health(health: 80, maxHealth: 80),
      Amulet(name: "Arcane Stone", attack: 0, magic: @["Frost", "Arcane Surge"])
    ),
    Immediate
  )

  result.addWithSpecificId(bromId)
  result.add(
    bromId,
    (
      Character(name: "Brom", class: "Barbarian"),
      Health(health: 140, maxHealth: 140),
      Armor(name: "Fur Armor", defense: 15, buffs: @["Cold Resist"])
    ),
    Immediate
  )


proc checkRestoredWorld(world: var World) =
  let marcusId = EntityId(value: 10)
  let elenaId = EntityId(value: 3)
  let bromId = EntityId(value: 7)

  checkpoint("All expected entities should still exist.")
  check world.has(marcusId)
  check world.has(elenaId)
  check world.has(bromId)

  checkpoint("Each entity should preserve expected components and values.")
  check world.read(marcusId, Character).name == "Marcus"
  check world.read(marcusId, Weapon).name == "Sword"

  check world.read(elenaId, Character).name == "Elena"
  check world.read(elenaId, Amulet).magic == @["Frost", "Arcane Surge"]

  check world.read(bromId, Character).name == "Brom"
  check world.read(bromId, Armor).buffs == @["Cold Resist"]

  var query: Query[(Meta, Character, Health, Opt[Weapon], Opt[Amulet], Opt[Armor])]
  var found = 0
  for (meta, character, health, weapon, amulet, armor) in world.query(query):
    inc found

    case meta.id.value
    of 10:
      check character.class == "Warrior"
      check health.health == 100

      weapon.isSomething:
        check value.attack == 20
      amulet.isNothing:
        discard
      armor.isNothing:
        discard
    of 3:
      check character.class == "Mage"
      check health.health == 80

      weapon.isNothing:
        discard
      amulet.isSomething:
        check value.magic.len == 2
      armor.isNothing:
        discard
    of 7:
      check character.class == "Barbarian"
      check health.health == 140

      weapon.isNothing:
        discard
      amulet.isNothing:
        discard
      armor.isSomething:
        check value.defense == 15
    else:
      check false

  checkpoint("Expected exactly 3 entities in query results.")
  check found == 3


suite "Serialization should":
  test "round-trip worlds using text serialization":
    var world = createTestWorld()
    let text = world.serializeToText((Character, Health, Weapon, Amulet, Armor))
    var restored = deserializeFromText(text, (Character, Health, Weapon, Amulet, Armor))

    checkRestoredWorld(restored)

  test "round-trip worlds using binary serialization":
    var world = createTestWorld()
    let payload = world.serializeToBinary((Character, Health, Weapon, Amulet, Armor))

    checkpoint("Binary payload should include the magic header and content.")
    check payload.len > 8
    check payload[0] == byte(ord('V'))
    check payload[1] == byte(ord('E'))
    check payload[2] == byte(ord('C'))
    check payload[3] == byte(ord('S'))

    var restored = deserializeFromBinary(payload, (Character, Health, Weapon, Amulet, Armor))
    checkRestoredWorld(restored)

  test "reject invalid binary payloads":
    var raised = false

    try:
      discard deserializeFromBinary(@[byte 1, 2, 3], (Character, Health))
    except ValueError:
      raised = true
    except CatchableError:
      fail()

    check raised
