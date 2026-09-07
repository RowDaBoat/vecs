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


proc addAndZero[T](sequence: var UnsafeSeq[T]; value: var T) =
  let source = cast[ptr byte](addr value)
  let seqVar = cast[pointer](addr sequence)
  seqVar.rawSeqAdd(source, sizeof(T))
  zeroMem(source, sizeof(T))


suite "rawSeq should":
  test "read the length of a seq":
    var sequence = newUnsafeSeq[int](3)
    check rawSeqLen(addr sequence) == 3


  test "read the capacity of a seq":
    var sequence = newUnsafeSeqOfCapacity[int](8)
    check rawSeqCapacity(addr sequence) >= 8


  test "report zero capacity for an unallocated seq":
    var sequence: UnsafeSeq[int]
    check rawSeqCapacity(addr sequence) == 0


  test "point at the address of the first element":
    var sequence = newUnsafeSeq[int](3)
    let rawData = rawSeqDataPtr(addr sequence)
    check rawData == addr sequence[0]


  test "append a plain int":
    var sequence: UnsafeSeq[int]
    var value = 42
    let seqVar = cast[pointer](addr sequence)
    seqVar.rawSeqAdd(cast[ptr byte](addr value), sizeof(int))

    check sequence.len == 1
    check sequence[0] == 42


  test "grow past the initial capacity while appending":
    var sequence = newUnsafeSeqOfCapacity[int](2)
    for i in 0 ..< 10:
      var value = i
      let seqVar = cast[pointer](addr sequence)
      seqVar.rawSeqAdd(cast[ptr byte](addr value), sizeof(int))

    check sequence.len == 10
    for i in 0 ..< 10:
      check sequence[i] == i


  test "keep an added ref readable":
    var refA: ref A = new A
    refA.x = 99

    var sequence: UnsafeSeq[ref A]
    sequence.addAndZero(refA)

    check sequence.len == 1
    check sequence[0] != nil
    check sequence[0].x == 99


  test "leave the source ref nil after adding it":
    var refA: ref A = new A
    refA.x = 7

    var sequence: UnsafeSeq[ref A]
    sequence.addAndZero(refA)

    check refA == nil


  test "keep an added ref alive after its source goes out of scope":
    var sequence: UnsafeSeq[ref A]

    block:
      var refA: ref A = new A
      refA.x = 55
      sequence.addAndZero(refA)

    checkpoint("The ref lives in the sequence now, so a full collect must not reap it.")
    GC_fullCollect()

    check sequence[0] != nil
    check sequence[0].x == 55


  test "keep every added ref readable":
    var sequence: UnsafeSeq[ref A]

    for i in 0 ..< 5:
      var refA: ref A = new A
      refA.x = i * 10
      sequence.addAndZero(refA)

    check sequence.len == 5
    for i in 0 ..< 5:
      check sequence[i].x == i * 10


  test "keep refs valid across a growth":
    var sequence = newUnsafeSeqOfCapacity[ref A](1)

    for i in 0 ..< 8:
      var refA: ref A = new A
      refA.x = i * 3
      sequence.addAndZero(refA)

    check sequence.len == 8
    for i in 0 ..< 8:
      check sequence[i] != nil
      check sequence[i].x == i * 3


  test "keep the ref field of an added object readable":
    var inner: ref A = new A
    inner.x = 77

    var b: B
    b.y = 9
    b.a = inner

    var sequence: UnsafeSeq[B]
    sequence.addAndZero(b)

    check sequence.len == 1
    check sequence[0].y == 9
    check sequence[0].a != nil
    check sequence[0].a.x == 77


  test "leave the source object zeroed after adding it":
    var inner: ref A = new A
    inner.x = 33

    var b: B
    b.y = 4
    b.a = inner

    var sequence: UnsafeSeq[B]
    sequence.addAndZero(b)

    check b.y == 0
    check b.a == nil


  test "keep ref fields valid across a growth":
    var sequence = newUnsafeSeqOfCapacity[B](1)

    for i in 0 ..< 6:
      var inner: ref A = new A
      inner.x = i + 100
      var b: B
      b.y = i
      b.a = inner
      sequence.addAndZero(b)

    check sequence.len == 6
    for i in 0 ..< 6:
      check sequence[i].a != nil
      check sequence[i].a.x == i + 100
