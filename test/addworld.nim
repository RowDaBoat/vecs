# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import std/tables
import ../src/[vecs, id]


type
  Tag = object
    name: string

  Link = object
    target: Id[Tag]

  Group = object
    members: seq[Id[Tag]]

  Anchor = object
    primary: Id[Tag]

  Frame = object
    anchor: Anchor

  Slots = object
    targets: array[2, Id[Tag]]

  Owner = object
    entity: EntityId

  Derived = object
    cached: int


type Migrated = (Tag, Link, Group, Frame, Slots, Owner)


const missingId = EntityId(value: 123)


suite "Adding a whole world should":
  setup:
    var world = World()
    let existingId = world.add((Tag(name: "existing"),), Immediate)

    var other = World()
    let tagId = other.add((Tag(name: "target"),), Immediate)
    let linkId = other.add((Link(target: (tagId of Tag)),), Immediate)


  test "copy entities and their components":
    let mapping = world.add(other, Migrated)

    check world.read(mapping[tagId], Tag) == Tag(name: "target")


  test "return a mapping holding every source entity":
    let mapping = world.add(other, Migrated)

    checkpoint("Every source entity should have a counterpart in the destination.")
    check tagId in mapping
    check linkId in mapping
    check world.has(mapping[tagId])
    check world.has(mapping[linkId])


  test "give each counterpart a new identity":
    let mapping = world.add(other, Migrated)

    checkpoint("Counterparts should not reuse the source ids.")
    check mapping[tagId] != tagId

    checkpoint("Meta should carry the counterpart's own id.")
    check world.read(mapping[tagId], Meta).id == mapping[tagId]


  test "remap ids pointing inside the added world":
    let mapping = world.add(other, Migrated)

    check world.read(mapping[linkId], Link).target == (mapping[tagId] of Tag)


  test "invalidate ids pointing outside the added world":
    let strayId = other.add((Link(target: (missingId of Tag)),), Immediate)
    let mapping = world.add(other, Migrated)

    check world.read(mapping[strayId], Link).target == Id[Tag]()


  test "remap ids held in sequences":
    let groupId = other.add((Group(members: @[tagId of Tag]),), Immediate)
    let mapping = world.add(other, Migrated)

    check world.read(mapping[groupId], Group).members == @[mapping[tagId] of Tag]


  test "remap ids held in nested objects":
    let frameId = other.add((Frame(anchor: Anchor(primary: (tagId of Tag))),), Immediate)
    let mapping = world.add(other, Migrated)

    check world.read(mapping[frameId], Frame).anchor.primary == (mapping[tagId] of Tag)


  test "remap ids held in fixed size arrays":
    let slotsId = other.add((Slots(targets: [tagId of Tag, missingId of Tag]),), Immediate)
    let mapping = world.add(other, Migrated)
    let slots = world.read(mapping[slotsId], Slots)

    checkpoint("Ids inside the added world should be remapped.")
    check slots.targets[0] == (mapping[tagId] of Tag)

    checkpoint("Ids outside the added world should be invalidated.")
    check slots.targets[1] == Id[Tag]()


  test "remap plain EntityId fields":
    let ownerId = other.add((Owner(entity: tagId),), Immediate)
    let mapping = world.add(other, Migrated)

    check world.read(mapping[ownerId], Owner).entity == mapping[tagId]


  test "copy only the listed components":
    let mixedId = other.add((Tag(name: "mixed"), Derived(cached: 7)), Immediate)
    let mapping = world.add(other, Migrated)

    checkpoint("Listed components should be copied.")
    check world.has(mapping[mixedId], Tag)

    checkpoint("Components outside the tuple should be left behind.")
    check not world.has(mapping[mixedId], Derived)


  test "keep entities whose components are all left behind":
    let derivedId = other.add((Derived(cached: 1),), Immediate)
    let mapping = world.add(other, Migrated)

    checkpoint("The entity should still exist, holding nothing but Meta.")
    check world.has(mapping[derivedId])
    check not world.has(mapping[derivedId], Derived)


  test "leave the source world unchanged":
    discard world.add(other, Migrated)

    check other.read(tagId, Tag) == Tag(name: "target")
    check other.read(linkId, Link).target == (tagId of Tag)


  test "keep the entities already in the destination":
    discard world.add(other, Migrated)

    check world.read(existingId, Tag) == Tag(name: "existing")


suite "Adding part of a world should":
  setup:
    var world = World()
    discard world.add((Tag(name: "existing"),), Immediate)

    var other = World()
    let tagId = other.add((Tag(name: "target"),), Immediate)
    let linkId = other.add((Link(target: (tagId of Tag)),), Immediate)


  test "copy only the given entities":
    let mapping = world.add(other, @[tagId], Migrated)

    checkpoint("Only the requested entity should be added.")
    check tagId in mapping
    check linkId notin mapping
    check world.read(mapping[tagId], Tag) == Tag(name: "target")


  test "remap ids pointing inside the added entities":
    let mapping = world.add(other, @[tagId, linkId], Migrated)

    check world.read(mapping[linkId], Link).target == (mapping[tagId] of Tag)


  test "invalidate ids pointing to entities left behind":
    let mapping = world.add(other, @[linkId], Migrated)

    check world.read(mapping[linkId], Link).target == Id[Tag]()
