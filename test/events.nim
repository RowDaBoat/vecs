# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/vecs

type
  DamageEvent = object
    amount: int

  HealEvent = object
    amount: int

suite "Events should":
  setup:
    var world = World()


  test "collect an emitted event":
    world.emit(DamageEvent(amount: 10))

    var count = 0
    for event in world.collect(DamageEvent):
      inc count
      check event.amount == 10

    check count == 1


  test "collect multiple emitted events in order":
    world.emit(DamageEvent(amount: 10))
    world.emit(DamageEvent(amount: 20))
    world.emit(DamageEvent(amount: 30))

    var amounts: seq[int]
    for event in world.collect(DamageEvent):
      amounts.add(event.amount)

    check amounts == @[10, 20, 30]


  test "allow multiple collects within a frame":
    world.emit(DamageEvent(amount: 10))

    var firstCount = 0
    for event in world.collect(DamageEvent):
      inc firstCount

    var secondCount = 0
    for event in world.collect(DamageEvent):
      inc secondCount

    check firstCount == 1
    check secondCount == 1


  test "drain events on consolidate":
    world.emit(DamageEvent(amount: 10))

    world.consolidate()

    var count = 0
    for event in world.collect(DamageEvent):
      inc count

    check count == 0


  test "isolate events by type":
    world.emit(DamageEvent(amount: 10))
    world.emit(HealEvent(amount: 5))
    world.emit(DamageEvent(amount: 20))
    world.emit(HealEvent(amount: 15))
    world.emit(DamageEvent(amount: 30))

    var healAmounts: seq[int]
    for event in world.collect(HealEvent):
      healAmounts.add(event.amount)

    check healAmounts == @[5, 15]

    var damageAmounts: seq[int]
    for event in world.collect(DamageEvent):
      damageAmounts.add(event.amount)

    check damageAmounts == @[10, 20, 30]


  test "collect from an empty queue":
    var count = 0
    for event in world.collect(DamageEvent):
      inc count

    check count == 0


  test "emit and collect across frames":
    world.emit(DamageEvent(amount: 10))
    world.emit(DamageEvent(amount: 20))

    for event in world.collect(DamageEvent):
      discard

    world.consolidate()

    world.emit(DamageEvent(amount: 30))

    var amounts: seq[int]
    for event in world.collect(DamageEvent):
      amounts.add(event.amount)

    check amounts == @[30]
