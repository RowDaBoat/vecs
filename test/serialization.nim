# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import std/strutils
import ../src/[examples, vecs]


type
  Portrait = object
    name: string
    data: seq[byte]


suite "Binary (CBOR) serialization should":
  setup:
    var world = World()
    let marcusId = world.add(
      (Character(name: "Marcus", class: "Warrior"),
       Health(health: 120, maxHealth: 120),
       Weapon(name: "Sword", attack: 10)),
      Immediate
    )
    let elenaId = world.add(
      (Character(name: "Elena", class: "Mage"),
       Health(health: 80, maxHealth: 80)),
      Immediate
    )


  test "round-trip component values":
    let data = world.serializeToBinary((Character, Health, Weapon))
    var restored = deserializeFromBinary(data, (Character, Health, Weapon))

    checkpoint("Marcus should keep his component values.")
    check restored.read(marcusId, Character) == Character(name: "Marcus", class: "Warrior")
    check restored.read(marcusId, Health) == Health(health: 120, maxHealth: 120)
    check restored.read(marcusId, Weapon) == Weapon(name: "Sword", attack: 10)

    checkpoint("Elena should keep her component values and have no Weapon.")
    check restored.read(elenaId, Character) == Character(name: "Elena", class: "Mage")
    check restored.read(elenaId, Health) == Health(health: 80, maxHealth: 80)
    check not restored.has(elenaId, Weapon)


  test "preserve entity ids":
    let data = world.serializeToBinary((Character, Health, Weapon))
    var restored = deserializeFromBinary(data, (Character, Health, Weapon))

    checkpoint("Restored entities should exist under their original ids.")
    check restored.has(marcusId)
    check restored.has(elenaId)


  test "round-trip a component holding binary data":
    let bytes = @[0'u8, 1'u8, 2'u8, 128'u8, 200'u8, 253'u8, 254'u8, 255'u8]
    let portraitId = world.add((Portrait(name: "Marcus' portrait", data: bytes),), Immediate)

    let data = world.serializeToBinary((Portrait,))
    var restored = deserializeFromBinary(data, (Portrait,))

    checkpoint("Binary data should survive the round-trip unchanged.")
    check restored.read(portraitId, Portrait).data == bytes
    check restored.read(portraitId, Portrait).name == "Marcus' portrait"


  test "store binary data as a contiguous byte sequence in the serialized output":
    let bytes = @[10'u8, 20'u8, 30'u8, 128'u8, 200'u8, 253'u8, 254'u8, 255'u8]
    discard world.add((Portrait(name: "Elena's portrait", data: bytes),), Immediate)

    let data = world.serializeToBinary((Portrait,))

    var rawBytes = newString(bytes.len)
    for i, value in bytes:
      rawBytes[i] = char(value)

    checkpoint("The exact byte sequence should appear contiguously in the serialized output.")
    check data.find(rawBytes) != -1
