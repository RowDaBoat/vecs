# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import std/[macros, assertions]
import ../src/vecs


macro defineComponents(): untyped =
  result = newStmtList()

  for i in 1..92:
    let typeName = ident("C" & $i)

    result.add quote do:
      type `typeName` = object

defineComponents()


macro registerComponents(world: untyped): untyped =
  var tup = newNimNode(nnkTupleConstr)

  for i in 1..92:
    tup.add newCall(ident("C" & $i))

  quote do:
    discard `world`.add(`tup`, Immediate)


suite "Many components should":
  setup:
    var world = World()
    registerComponents(world)


  test "support adding and querying low-numbered components":
    let id = world.add((C1(), C2(), C3()), Immediate)

    checkpoint("Entity should carry C1, C2, and C3.")
    check world.has(id, C1)
    check world.has(id, C2)
    check world.has(id, C3)


  test "support adding and querying high-numbered components":
    let id = world.add((C90(), C91(), C92()), Immediate)

    checkpoint("Entity should carry C90, C91, and C92.")
    check world.has(id, C90)
    check world.has(id, C91)
    check world.has(id, C92)


  test "support operations crossing the word boundary":
    let id = world.add((C63(), C64(), C65()), Immediate)

    checkpoint("All three boundary-spanning components should be present.")
    check world.has(id, C63)
    check world.has(id, C64)
    check world.has(id, C65)

    world.remove(id, C64, Immediate)

    checkpoint("C64 should be gone while its neighbours remain.")
    check world.has(id, C63)
    check not world.has(id, C64)
    check world.has(id, C65)


  test "support removing high-numbered components":
    let id = world.add((C88(), C89()), Immediate)
    world.remove(id, C89, Immediate)

    checkpoint("C89 should be removed while C88 remains.")
    check world.has(id, C88)
    check not world.has(id, C89)


  test "support querying high-numbered components":
    let id = world.add((C80(), C81()), Immediate)
    var query: Query[(Meta, C80, C81)]

    checkpoint("Query should find the entity with both components.")
    var found = false
    for (meta, c80, c81) in world.query(query):
      if meta.id == id:
        found = true
    check found


  test "support Not[] filtering with high-numbered components":
    let withHigh = world.add((C1(), C92()), Immediate)
    let withoutHigh = world.add((C1(),), Immediate)
    var query: Query[(Meta, C1, Not[C92])]

    checkpoint("Only the entity without C92 should be returned.")

    var count = 0

    for (meta, c1) in world.query(query):
      if meta.id == withHigh or meta.id == withoutHigh:
        inc count
        check meta.id == withoutHigh

    check count == 1


  test "support write access to high-numbered components":
    let id = world.add((C75(),), Immediate)

    checkpoint("Write iterator should yield exactly once for the entity.")

    var yields = 0

    for c75 in world.write(id, C75):
      inc yields

    check yields == 1
