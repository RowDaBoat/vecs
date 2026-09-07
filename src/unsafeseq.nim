# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.


type
  UnsafeSeqPayload[T] = object
    cap: int
    data: UncheckedArray[T]

  UnsafeSeq*[T] = object
    len: int
    payload: ptr UnsafeSeqPayload[T]


proc rawSeqLenPtr*(seqVar: pointer): ptr int {.inline.} =
  cast[ptr int](seqVar)


proc rawSeqPayloadPtr(seqVar: pointer): ptr pointer {.inline.} =
  cast[ptr pointer](cast[int](seqVar) + sizeof(int))


proc payloadCapacityPtr(payload: pointer): ptr int {.inline.} =
  cast[ptr int](payload)


proc payloadDataPtr(payload: pointer): pointer {.inline.} =
  cast[pointer](cast[int](payload) + sizeof(int))


proc rawSeqLen*(seqVar: pointer): int {.inline.} =
  ## Current element count of the seq at `seqVar`.
  rawSeqLenPtr(seqVar)[]


proc rawSeqCapacity*(seqVar: pointer): int {.inline.} =
  ## Current capacity of the seq at `seqVar`.
  let payload = rawSeqPayloadPtr(seqVar)[]

  if payload == nil: 0
  else: payloadCapacityPtr(payload)[]


proc rawSeqDataPtr*(seqVar: pointer): pointer {.inline.} =
  ## Raw pointer to the first element of the seq data buffer.
  ## Returns nil if the seq has no allocated payload.
  let payload = rawSeqPayloadPtr(seqVar)[]

  if payload == nil: nil
  else: payloadDataPtr(payload)


proc nextCapacity(current: int): int {.inline.} =
  if current == 0: 4 else: current * 2


proc ensureCapacity[T](self: var UnsafeSeq[T], minCapacity: int) =
  static:
    assert alignof(T) <= sizeof(int),
      "UnsafeSeq can't hold types aligned over " & $sizeof(int) & " bytes, " &
      "the payload header would misplace the element data."

  let headerSize = sizeof(int)

  if self.payload == nil:
    self.payload = cast[ptr UnsafeSeqPayload[T]](alloc0(headerSize + minCapacity * sizeof(T)))
    self.payload.cap = minCapacity
  elif self.payload.cap < minCapacity:
    let newCapacity = minCapacity * 2
    let newData = realloc0(
      self.payload,
      headerSize + self.payload.cap * sizeof(T),
      headerSize + newCapacity * sizeof(T)
    )

    assert newData != nil, "Insufficient memory to grow UnsafeSeq."
    self.payload = cast[ptr UnsafeSeqPayload[T]](newData)
    self.payload.cap = newCapacity


proc rawSeqGrow*(seqVar: pointer; stride: int; minCapacity: int) =
  let payloadLocation = rawSeqPayloadPtr(seqVar)
  let oldPayload = payloadLocation[]
  let oldCapacity = if oldPayload == nil: 0 else: payloadCapacityPtr(oldPayload)[]
  var newCapacity = nextCapacity(oldCapacity)

  if newCapacity < minCapacity:
    newCapacity = minCapacity

  let headerSize = sizeof(int)
  let newPayload = alloc0(headerSize + newCapacity * stride)
  payloadCapacityPtr(newPayload)[] = newCapacity
  let currentLength = rawSeqLenPtr(seqVar)[]

  if currentLength > 0 and oldPayload != nil:
    copyMem(payloadDataPtr(newPayload), payloadDataPtr(oldPayload), currentLength * stride)

  if oldPayload != nil:
    dealloc(oldPayload)

  payloadLocation[] = newPayload


template rawSeqSet(self: pointer, index: untyped, value: ptr byte, stride: int) =
  var data = rawSeqDataPtr(self)
  copyMem(cast[pointer](cast[int](data) + index * stride), value, stride)


template rawSeqGet*(self: pointer, index: untyped, stride: int): ptr byte =
  var data = rawSeqDataPtr(self)
  cast[ptr byte](cast[int](data) + index * stride)


proc rawSeqAdd*(seqVar: pointer; val: ptr byte; stride: int) =
  ## Append `stride` bytes from `val` to the seq at `seqVar`.
  let length = rawSeqLenPtr(seqVar)[]
  let capacity = rawSeqCapacity(seqVar)

  if length >= capacity:
    rawSeqGrow(seqVar, stride, length + 1)

  let data = rawSeqDataPtr(seqVar)
  copyMem(cast[pointer](cast[int](data) + length * stride), val, stride)
  rawSeqLenPtr(seqVar)[] = length + 1


proc newUnsafeSeqOfCapacity*[T](cap: int = 0): UnsafeSeq[T] =
  result = UnsafeSeq[T](len: 0)

  if cap > 0:
    ensureCapacity(result, cap)


proc newUnsafeSeq*[T](len: int = 0): UnsafeSeq[T] =
  result = UnsafeSeq[T](len: len)

  if len > 0:
    ensureCapacity(result, len)


proc len*[T](self: UnsafeSeq[T]): int = self.len


proc `[]`*[T](self: UnsafeSeq[T], index: int): lent T {.inline.} =
  assert index >= 0 and index < self.len, "Access out of bound"
  self.payload.data[index]


proc `[]`*[T](self: var UnsafeSeq[T], index: int): var T {.inline.} =
  assert index >= 0 and index < self.len, "Access out of bound"
  self.payload.data[index]


proc `[]=`*[T](self: var UnsafeSeq[T], index: int, value: sink T) {.inline.} =
  assert index >= 0 and index < self.len, "Access out of bound"
  self.payload.data[index] = value


proc grow[T](self: var UnsafeSeq[T], newLength: int) =
  assert newLength >= self.len, "Can't grow to lesser than the sequence length"
  ensureCapacity(self, newLength)
  let oldLength = self.len
  self.len = newLength

  for index in oldLength ..< newLength:
    self[index] = default(T)


proc shrink[T](self: var UnsafeSeq[T], newLength: int) =
  assert newLength <= self.len, "Can't shrink to greater than the sequences length"

  for index in newLength ..< self.len:
    self[index].reset()

  self.len = newLength


proc setLen*[T](self: var UnsafeSeq[T], newLength: int) =
  if self.len < newLength:
    grow(self, newLength)
  else:
    shrink(self, newLength)


proc rawSeqAddAndZero*(seqVar: pointer, source: ptr byte, stride: int) =
  seqVar.rawSeqAdd(source, stride)
  zeroMem(source, stride)


proc rawSeqSetAndZero*(seqVar: pointer, index: int, source: ptr byte, stride: int) =
  seqVar.rawSeqSet(index, source, stride)
  zeroMem(source, stride)


proc add*[T](self: var UnsafeSeq[T], value: T) =
  self.grow(self.len + 1)
  self[self.len - 1] = value


proc toSeq*[T](self: UnsafeSeq[T]): seq[T] =
  result = newSeq[T](self.len)

  for index in 0 ..< self.len:
    result[index] = self[index]


proc `$`*[T](self: UnsafeSeq[T]): string =
  $self.toSeq()


template destroy[T](self: var UnsafeSeq[T]) =
  if self.payload != nil:
    for index in 0 ..< self.len:
      self[index].reset()

    self.payload.dealloc()
    self.payload = nil

  self.len = 0


proc `=destroy`*[T](self: var UnsafeSeq[T]) =
  destroy(self)


proc `=sink`*[T](dest: var UnsafeSeq[T]; src: UnsafeSeq[T]) =
  if dest.payload != src.payload:
    destroy(dest)

  dest.payload = src.payload
  dest.len = src.len


proc `=copy`*[T](dest: var UnsafeSeq[T]; src: UnsafeSeq[T]) =
  if src.payload == dest.payload:
    return
  if src.payload == nil:
    destroy(dest)
  else:
    dest.setLen(src.len)

    for index in 0 ..< src.len:
      dest[index] = src[index]


proc `=dup`*[T](src: UnsafeSeq[T]): UnsafeSeq[T] =
  if src.payload != nil:
    result = newUnsafeSeqOfCapacity[T](src.payload.cap)
    result.setLen(src.len)

    for index in 0 ..< src.len:
      result[index] = src[index]
