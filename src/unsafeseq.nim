# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.


type
  VSeqPayload[T] = object
    cap: int
    data: UncheckedArray[T]

  VSeq*[T] = object
    len: int
    payload: ptr VSeqPayload[T]


const CHECKS_ENABLED = not defined(danger)


proc seqLenPtr*(seqVar: pointer): ptr int {.inline.} =
  cast[ptr int](seqVar)


proc seqPayloadPtr(seqVar: pointer): ptr pointer {.inline.} =
  cast[ptr pointer](cast[int](seqVar) + sizeof(int))


proc payloadCapacityPtr(payload: pointer): ptr int {.inline.} =
  cast[ptr int](payload)


proc payloadDataPtr(payload: pointer): pointer {.inline.} =
  cast[pointer](cast[int](payload) + sizeof(int))


proc unsafeSeqLen*(seqVar: pointer): int {.inline.} =
  ## Current element count of the seq at `seqVar`.
  seqLenPtr(seqVar)[]


proc unsafeSeqCap*(seqVar: pointer): int {.inline.} =
  ## Current capacity of the seq at `seqVar`.
  let payload = seqPayloadPtr(seqVar)[]

  if payload == nil: 0
  else: payloadCapacityPtr(payload)[]


proc unsafeSeqDataPtr*(seqVar: pointer): pointer {.inline.} =
  ## Raw pointer to the first element of the seq data buffer.
  ## Returns nil if the seq has no allocated payload.
  let payload = seqPayloadPtr(seqVar)[]

  if payload == nil: nil
  else: payloadDataPtr(payload)


proc nextCapacity(current: int): int {.inline.} =
  if current == 0: 4 else: current * 2


proc growPayload*(seqVar: pointer; stride: int; minCapacity: int) =
  let payloadLocation = seqPayloadPtr(seqVar)
  let oldPayload = payloadLocation[]
  let oldCapacity = if oldPayload == nil: 0 else: payloadCapacityPtr(oldPayload)[]
  var newCapacity = nextCapacity(oldCapacity)

  if newCapacity < minCapacity:
    newCapacity = minCapacity

  let headerSize = sizeof(int)
  let newPayload = alloc0(headerSize + newCapacity * stride)
  payloadCapacityPtr(newPayload)[] = newCapacity
  let currentLength = seqLenPtr(seqVar)[]

  if currentLength > 0 and oldPayload != nil:
    copyMem(payloadDataPtr(newPayload), payloadDataPtr(oldPayload), currentLength * stride)

  if oldPayload != nil:
    dealloc(oldPayload)

  payloadLocation[] = newPayload


template unsafeSet*(self: pointer, index: untyped, value: ptr byte, stride: int) =
  var data = unsafeSeqDataPtr(self)
  copyMem(cast[pointer](cast[int](data) + index * stride), value, stride)


template unsafeGet*(self: pointer, index: untyped, stride: int): ptr byte =
  var data = unsafeSeqDataPtr(self)
  cast[ptr byte](cast[int](data) + index * stride)


proc unsafeAdd*(seqVar: pointer; val: ptr byte; stride: int) =
  ## Append `stride` bytes from `val` to the seq at `seqVar`.
  let length = seqLenPtr(seqVar)[]
  let capacity = unsafeSeqCap(seqVar)

  if length >= capacity:
    growPayload(seqVar, stride, length + 1)

  let data = unsafeSeqDataPtr(seqVar)
  copyMem(cast[pointer](cast[int](data) + length * stride), val, stride)
  seqLenPtr(seqVar)[] = length + 1


proc ensureCap[T](self: var VSeq[T], minCapacity: int) =
  let headerSize = sizeof(int)

  if self.payload == nil:
    self.payload = cast[ptr VSeqPayload[T]](alloc0(headerSize + minCapacity * sizeof(T)))
    self.payload.cap = minCapacity

  if self.payload.cap < minCapacity:
    let newCapacity = minCapacity * 2
    let newData = realloc0(
      self.payload,
      headerSize + self.payload.cap * sizeof(T),
      headerSize + newCapacity * sizeof(T)
    )

    assert newData != nil, "Insufficient memory to grow VSeq."
    self.payload = cast[ptr VSeqPayload[T]](newData)
    self.payload.cap = newCapacity


proc newVSeqOfCap*[T](cap: int = 0): VSeq[T] =
  result = VSeq[T](len: 0)

  if cap > 0:
    ensureCap(result, cap)


proc newVSeq*[T](len: int = 0): VSeq[T] =
  result = VSeq[T](len: len)

  if len > 0:
    ensureCap(result, len)


proc len*[T](self: VSeq[T]): int = self.len


proc `[]`*[T](self: VSeq[T], index: int): lent T {.inline.} =
  when CHECKS_ENABLED:
    assert index >= 0 and index < self.len, "Access out of bound"

  self.payload.data[index]


proc `[]`*[T](self: var VSeq[T], index: int): var T {.inline.} =
  when CHECKS_ENABLED:
    assert index >= 0 and index < self.len, "Access out of bound"

  self.payload.data[index]


proc `[]`*[T](self: VSeq[T], index: BackwardsIndex): lent T {.inline.} =
  self[self.len - index.int]


proc `[]`*[T](self: var VSeq[T], index: BackwardsIndex): var T {.inline.} =
  self[self.len - index.int]


proc `[]=`*[T](self: var VSeq[T], index: int, value: sink T) {.inline.} =
  when CHECKS_ENABLED:
    assert index >= 0 and index < self.len, "Access out of bound"

  self.payload.data[index] = value


proc `[]=`*[T](self: var VSeq[T], index: BackwardsIndex, value: sink T) {.inline.} =
  self[self.len - index.int] = value


proc shrink*[T](self: var VSeq[T], newLength: int) =
  assert newLength <= self.len, "Can't shrink to greater than the sequences length"

  for index in newLength ..< self.len:
    self[index].reset()

  self.len = newLength


proc grow*[T](self: var VSeq[T], newLength: int) =
  assert newLength >= self.len, "Can't grow to lesser than the sequence length"
  ensureCap(self, newLength)
  let oldLength = self.len
  self.len = newLength

  for index in oldLength ..< newLength:
    self[index] = default(T)


proc setLen*[T](self: var VSeq[T], newLength: int) =
  if self.len < newLength:
    grow(self, newLength)
  else:
    shrink(self, newLength)


proc unsafeAddAndZero*(seqVar: pointer, source: ptr byte, stride: int) =
  seqVar.unsafeAdd(source, stride)
  zeroMem(source, stride)


proc unsafeSetAndZero*(seqVar: pointer, index: int, source: ptr byte, stride: int) =
  seqVar.unsafeSet(index, source, stride)
  zeroMem(source, stride)


proc add*[T](self: var VSeq[T], value: T) =
  self.grow(self.len + 1)
  self[self.len - 1] = value


proc add*[T](self: var VSeq[T], value: openArray[T]) =
  let oldLength = self.len
  self.grow(oldLength + value.len)

  for index in oldLength ..< self.len:
    self[index] = value[index - oldLength]


proc `&`*[T](left, right: VSeq[T]): VSeq[T] =
  result = newVSeq[T](left.len + right.len)

  for index in 0 ..< left.len:
    result[index] = left[index]

  for index in 0 ..< right.len:
    result[left.len + index] = right[index]


proc pop*[T](self: var VSeq[T]): T =
  when CHECKS_ENABLED:
    assert self.len > 0, "Can't pop on empty VSeq."

  result = self[^1]
  self[^1] = default(T)
  dec self.len


proc delete*[T](self: var VSeq[T], index: int) =
  when CHECKS_ENABLED:
    assert index >= 0 and index < self.len, "Access out of bound"

  for index in index ..< self.len - 1:
    self[index] = self[index + 1]

  self[^1] = default(T)
  dec self.len


proc insert*[T](self: var VSeq[T], index: int, value: T) =
  when CHECKS_ENABLED:
    assert index >= 0 and index < self.len, "Access out of bound"

  self.grow(self.len + 1)

  for index in countdown(self.len - 1, index + 1):
    self[index] = self[index - 1]
  self[index] = value


proc del*[T](self: var VSeq[T], index: int) =
  when CHECKS_ENABLED:
    assert index >= 0 and index < self.len, "Access out of bound"

  self[index] = self[^1]
  self[^1] = default(T)
  self.shrink(self.len - 1)


proc toSeq*[T](self: VSeq[T]): seq[T] =
  result = newSeq[T](self.len)

  for index in 0 ..< self.len:
    result[index] = self[index]


proc toVSeq*[T](self: seq[T]): VSeq[T] =
  result = newVSeq[T](self.len)

  for index in 0 ..< self.len:
    result[index] = self[index]


proc clear*[T](self: var VSeq[T]) =
  self.setLen(0)


iterator items*[T](self: VSeq[T]): T =
  for index in 0 ..< self.len:
    yield self[index]


iterator mitems*[T](self: var VSeq[T]): var T =
  for index in 0 ..< self.len:
    yield self[index]


iterator pairs*[T](self: VSeq[T]): (int, T) =
  for index in 0 ..< self.len:
    yield (index, self[index])


iterator mpairs*[T](self: var VSeq[T]): (int, T) =
  for index in 0 ..< self.len:
    yield (index, self[index])


template destroy[T](self: var VSeq[T]) =
  if self.payload != nil:
    for index in 0 ..< self.len:
      self[index].reset()

    self.payload.dealloc()
    self.payload = nil

  self.len = 0


proc `=destroy`*[T](self: var VSeq[T]) =
  destroy(self)


proc `=sink`*[T](dest: var VSeq[T]; src: VSeq[T]) =
  if dest.payload != src.payload:
    destroy(dest)

  dest.payload = src.payload
  dest.len = src.len


proc `=copy`*[T](dest: var VSeq[T]; src: VSeq[T]) =
  if src.payload == dest.payload:
    return
  if src.payload == nil:
    destroy(dest)
  else:
    dest.setLen(src.len)

    for index in 0 ..< src.len:
      dest[index] = src[index]


proc `=dup`*[T](src: VSeq[T]): VSeq[T] =
  if src.payload != nil:
    result = newVSeqOfCap[T](src.payload.cap)
    result.setLen(src.len)

    for index in 0 ..< src.len:
      result[index] = src[index]
