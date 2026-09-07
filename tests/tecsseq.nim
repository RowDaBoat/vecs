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


  test "return the correct length":
    check container.len == 0

    checkpoint("Length should increase after additions.")
    discard container.add("Marcus")
    check container.len == 1

    discard container.add("Elena")
    check container.len == 2


  test "read items via [] accessor":
    let idx = container.add("Marcus")

    check container[idx] == "Marcus"


  test "write items via []= accessor":
    let idx = container.add("Marcus")

    container[idx] = "Marco"

    check container[idx] == "Marco"


  test "set items at specific index via addAt":
    container.addAt(0, "Marcus")
    container.addAt(2, "Grimm")

    check container[0] == "Marcus"
    check container[2] == "Grimm"
    check container.len == 3


  test "show its items":
    discard container.add("Marcus")
    discard container.add("Elena")

    check $container == """@["Marcus", "Elena"]"""
