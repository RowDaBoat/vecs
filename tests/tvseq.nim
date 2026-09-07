# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/unsafeseq


suite "VSeq should":
  test "add items and read them back in order":
    var sequence = newVSeqOfCap[int](2)
    sequence.add(10)
    sequence.add(20)
    sequence.add(30)

    check toSeq(sequence) == @[10, 20, 30]


  test "insert and delete items at an index":
    var sequence = newVSeqOfCap[int](2)
    sequence.add(10)
    sequence.add(20)
    sequence.add(30)

    checkpoint("Inserting should shift the tail one place to the right.")
    sequence.insert(1, 99)
    check toSeq(sequence) == @[10, 99, 20, 30]

    checkpoint("Deleting should shift the tail one place to the left.")
    sequence.delete(2)
    check toSeq(sequence) == @[10, 99, 30]


  test "mutate items in place and pop the last one":
    var sequence = newVSeqOfCap[int](2)
    sequence.add(10)
    sequence.add(99)
    sequence.add(30)

    sequence[0] = 42
    check sequence[0] == 42
    check toSeq(sequence) == @[42, 99, 30]

    checkpoint("Popping should return the last item and drop it.")
    check sequence.pop() == 30
    check toSeq(sequence) == @[42, 99]


  test "copy and move its contents":
    var sequence = newVSeqOfCap[int](2)
    sequence.add(42)
    sequence.add(99)

    checkpoint("A copy should hold its own equal contents.")
    var copy = sequence
    check toSeq(copy) == @[42, 99]

    checkpoint("Moving should transfer the contents and empty the source.")
    var moved = move(sequence)
    check toSeq(moved) == @[42, 99]
    check sequence.len == 0
