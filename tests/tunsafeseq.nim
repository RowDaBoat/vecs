# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/unsafeseq


suite "UnsafeSeq should":
  test "add items and read them back in order":
    var sequence = newUnsafeSeqOfCapacity[int](2)
    sequence.add(10)
    sequence.add(20)
    sequence.add(30)

    check toSeq(sequence) == @[10, 20, 30]


  test "mutate items in place":
    var sequence = newUnsafeSeqOfCapacity[int](2)
    sequence.add(10)
    sequence.add(99)
    sequence.add(30)

    sequence[0] = 42
    check sequence[0] == 42
    check toSeq(sequence) == @[42, 99, 30]


  test "show its items":
    var sequence = newUnsafeSeqOfCapacity[int](2)
    sequence.add(10)
    sequence.add(20)

    check $sequence == "@[10, 20]"


  test "copy and move its contents":
    var sequence = newUnsafeSeqOfCapacity[int](2)
    sequence.add(42)
    sequence.add(99)

    checkpoint("A copy should hold its own equal contents.")
    var copy = sequence
    check toSeq(copy) == @[42, 99]

    checkpoint("Moving should transfer the contents and empty the source.")
    var moved = move(sequence)
    check toSeq(moved) == @[42, 99]
    check sequence.len == 0
