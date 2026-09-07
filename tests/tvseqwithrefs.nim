# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/unsafeseq


type
  A = object
    x: int

  B = object
    y: int
    a: ref A


proc addAndZero[T](sequence: var VSeq[T], value: var T) =
  let source = cast[ptr byte](addr value)
  let seqVar = cast[pointer](addr sequence)
  seqVar.unsafeAdd(source, sizeof(T))
  zeroMem(source, sizeof(T))


suite "VSeq should":
  test "keep a ref readable after addAndZero":
    var refA: ref A = new A
    refA.x = 42

    var sequence = newVSeqOfCap[ref A](4)
    sequence.addAndZero(refA)

    check refA.isNil
    check sequence.len == 1
    check sequence[0].x == 42


  test "keep a ref declared in an inner block alive after a full collect":
    var sequence = newVSeqOfCap[ref A](4)

    block:
      var refA: ref A = new A
      refA.x = 99
      sequence.addAndZero(refA)

    checkpoint("The ref lives in the sequence now, so a full collect must not reap it.")
    GC_fullCollect()

    check sequence[0] != nil
    check sequence[0].x == 99


  test "keep every added ref readable":
    var sequence = newVSeqOfCap[ref A](2)

    for i in 0 ..< 5:
      var refA: ref A = new A
      refA.x = i * 10
      sequence.addAndZero(refA)

    check sequence.len == 5
    for i in 0 ..< 5:
      check sequence[i].x == i * 10


  test "keep refs valid across a reallocation":
    var sequence = newVSeqOfCap[ref A](1)

    var refA: ref A = new A
    refA.x = 7
    sequence.addAndZero(refA)

    var refB: ref A = new A
    refB.x = 13
    sequence.addAndZero(refB)

    check sequence.len == 2
    check sequence[0].x == 7
    check sequence[1].x == 13


  test "keep the ref field of an added object readable":
    var inner: ref A = new A
    inner.x = 55

    var b: B
    b.y = 1
    b.a = inner

    var sequence = newVSeqOfCap[B](4)
    sequence.addAndZero(b)

    check sequence.len == 1
    check sequence[0].y == 1
    check sequence[0].a != nil
    check sequence[0].a.x == 55


  test "keep a stored object valid after its source copy is zeroed":
    var inner: ref A = new A
    inner.x = 88

    var b: B
    b.y = 3
    b.a = inner

    var sequence = newVSeqOfCap[B](4)
    sequence.addAndZero(b)

    checkpoint("Zeroing the source copy must leave the stored object intact.")
    check sequence[0].y == 3
    check sequence[0].a != nil
    check sequence[0].a.x == 88


  test "keep the ref fields of every added object readable":
    var sequence = newVSeqOfCap[B](2)

    for i in 0 ..< 4:
      var inner: ref A = new A
      inner.x = i + 100
      var b: B
      b.y = i
      b.a = inner
      sequence.addAndZero(b)

    check sequence.len == 4
    for i in 0 ..< 4:
      check sequence[i].y == i
      check sequence[i].a != nil
      check sequence[i].a.x == i + 100


  test "keep ref fields valid across a reallocation":
    var sequence = newVSeqOfCap[B](1)

    for i in 0 ..< 8:
      var inner: ref A = new A
      inner.x = i * 3
      var b: B
      b.y = i
      b.a = inner
      sequence.addAndZero(b)

    check sequence.len == 8
    for i in 0 ..< 8:
      check sequence[i].a != nil
      check sequence[i].a.x == i * 3


  test "return a valid ref when popped":
    var refA: ref A = new A
    refA.x = 21

    var sequence = newVSeqOfCap[ref A](4)
    sequence.addAndZero(refA)

    let popped = sequence.pop()
    check sequence.len == 0
    check popped != nil
    check popped.x == 21


  test "keep the remaining refs valid after a delete":
    var sequence = newVSeqOfCap[ref A](4)

    for i in 0 ..< 3:
      var refA: ref A = new A
      refA.x = i
      sequence.addAndZero(refA)

    sequence.delete(1)

    check sequence.len == 2
    check sequence[0].x == 0
    check sequence[1].x == 2


  test "release objects holding refs when cleared":
    var sequence = newVSeqOfCap[B](4)

    for i in 0 ..< 3:
      var inner: ref A = new A
      inner.x = i
      var b: B
      b.y = i
      b.a = inner
      sequence.addAndZero(b)

    sequence.clear()
    check sequence.len == 0


  test "keep the remaining refs valid after a swap-delete":
    var sequence = newVSeqOfCap[ref A](4)

    for i in 0 ..< 4:
      var refA: ref A = (new A)
      refA.x = i * 5
      sequence.addAndZero(refA)

    sequence.del(1)

    check sequence.len == 3
    check sequence[0].x == 0
    check sequence[2].x == 10


  test "keep ref fields reachable through a copy":
    var inner: ref A = new A
    inner.x = 77

    var b: B
    b.y = 9
    b.a = inner

    var sequence = newVSeqOfCap[B](4)
    sequence.addAndZero(b)

    let copy = sequence
    check copy[0].a != nil
    check copy[0].a.x == 77
