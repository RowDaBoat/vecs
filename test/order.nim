# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/vecs


type
  A = object
    value: int

  B = object
    value: int

  C = object
    value: int


suite "Component order should":
  setup:
    var world = World()
    discard world.add((A(), B(), C()), Immediate)


  test "be irrelevant for has() checks":
    let ab = world.add((A(value: 1), B(value: 2)), Immediate)
    let ba = world.add((B(value: 2), A(value: 1)), Immediate)

    checkpoint("Both entities should have A and B regardless of insertion order.")
    check world.has(ab, A)
    check world.has(ab, B)
    check world.has(ba, A)
    check world.has(ba, B)


  test "be irrelevant for query matching":
    let ab = world.add((A(value: 1), B(value: 2)), Immediate)
    let ba = world.add((B(value: 2), A(value: 1)), Immediate)

    var query: Query[(Meta, A, B)]
    var found: seq[EntityId]

    for (meta, a, b) in world.query(query):
      found.add(meta.id)

    checkpoint("Both entities should appear in Query[(Meta, A, B)].")
    check ab in found
    check ba in found


  test "be irrelevant for component values":
    let ab = world.add((A(value: 1), B(value: 2)), Immediate)
    let ba = world.add((B(value: 2), A(value: 1)), Immediate)

    var query: Query[(Meta, A, B)]

    for (meta, a, b) in world.query(query):
      if meta.id == ab or meta.id == ba:
        checkpoint("A and B values should be correct regardless of insertion order.")
        check a.value == 1
        check b.value == 2


  test "be irrelevant for three-component entities":
    let abc = world.add((A(value: 1), B(value: 2), C(value: 3)), Immediate)
    let cba = world.add((C(value: 3), B(value: 2), A(value: 1)), Immediate)
    let bca = world.add((B(value: 2), C(value: 3), A(value: 1)), Immediate)

    checkpoint("All orderings should carry all three components.")
    for id in [abc, cba, bca]:
      check world.has(id, A)
      check world.has(id, B)
      check world.has(id, C)


  test "be irrelevant when adding components one by one":
    let ab = world.add((A(value: 1),), Immediate)
    world.add(ab, B(value: 2), Immediate)

    let ba = world.add((B(value: 2),), Immediate)
    world.add(ba, A(value: 1), Immediate)

    var query: Query[(Meta, A, B)]
    var visited = 0

    for (meta, a, b) in world.query(query):
      if meta.id == ab or meta.id == ba:
        checkpoint("A and B values should match regardless of whether components were added at once or progressively.")
        check a.value == 1
        check b.value == 2
        inc visited

    check visited == 2


  test "be irrelevant for Not[] filtering":
    let ab = world.add((A(value: 1), B(value: 2)), Immediate)
    let ba = world.add((B(value: 2), A(value: 1)), Immediate)
    let aOnly = world.add((A(value: 1),), Immediate)

    var query: Query[(Meta, A, Not[B])]
    var found: seq[EntityId]

    for (meta, a) in world.query(query):
      found.add(meta.id)

    checkpoint("Only the entity without B should appear, regardless of insertion order.")
    check aOnly in found
    check ab notin found
    check ba notin found
