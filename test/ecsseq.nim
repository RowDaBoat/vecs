# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/ecsseq


suite "EcsSeq should":
  setup:
    var container = EcsSeq[string]()


  test "add items and return their index":
    let idx0 = container.add("Marcus")
    let idx1 = container.add("Elena")
    let idx2 = container.add("Grimm")

    check idx0 == 0
    check idx1 == 1
    check idx2 == 2


  test "check if an item exists with has":
    let idx = container.add("Marcus")

    checkpoint("Item should exist after adding.")
    check container.has(idx)

    container.del(idx)

    checkpoint("Item should not exist after deletion.")
    check not container.has(idx)


  test "delete items by index":
    let idx0 = container.add("Marcus")
    let idx1 = container.add("Elena")

    container.del(idx0)

    checkpoint("Deleted item should no longer exist.")
    check not container.has(idx0)
    checkpoint("Other items should still exist.")
    check container.has(idx1)


  test "check for existing/non existing and valid/invalid indices":
    let idx = container.add("Marcus")

    checkpoint("Existing indices should return true.")
    check container.has(idx)
    checkpoint("Valid non-existing indices should return false.")
    check not container.has(2)
    checkpoint("Negative indices should return false.")
    check not container.has(-1)
    checkpoint("Out of bounds indices should return false.")
    check not container.has(100)


  test "return the correct length":
    check container.len == 0

    checkpoint("Length should increase after first addition.")
    let idx = container.add("Marcus")
    check container.len == 1

    checkpoint("Length should increase after second addition.")
    discard container.add("Elena")
    check container.len == 2

    checkpoint("Length should decrease after deletion.")
    container.del(idx)
    check container.len == 1


  test "read items via [] accessor":
    let idx = container.add("Marcus")

    check container[idx] == "Marcus"


  test "write items via []= accessor":
    let idx = container.add("Marcus")

    container[idx] = "Marco"

    check container[idx] == "Marco"


  test "iterate over items":
    let idx0 = container.add("Marcus")
    let idx1 = container.add("Elena")
    let idx2 = container.add("Grimm")

    checkpoint("All items should be iterated.")
    var collectedIds: seq[int] = @[]
    for id in container.ids:
      collectedIds.add(id)

    check collectedIds == @[idx0, idx1, idx2]

    checkpoint("Deleted items should not be iterated.")
    container.del(idx1)
    collectedIds = @[]
    for item in container.ids:
      collectedIds.add(item)

    check collectedIds == @[idx0, idx2]


  test "iterate over ids after multiple additions and deletions":
    let idx0 = container.add("Marcus")
    let idx1 = container.add("Elena")
    container.del(idx0)
    let idx2 = container.add("Grimm")
    let idx3 = container.add("Zara")
    container.del(idx2)

    var collectedIds: seq[int] = @[]
    for id in container.ids:
      collectedIds.add(id)

    checkpoint("Only non-deleted items should be iterated.")
    check idx1 in collectedIds
    check idx3 in collectedIds
    check container.len == 2
