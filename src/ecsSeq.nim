#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
type EcsSeqAny* = ref object of RootObj
  deleted: seq[bool]
  free: seq[int]

type EcsSeq*[T] = ref object of EcsSeqAny
  data: seq[T]

type Builder* = proc(): EcsSeqAny {.nimcall.}
type Adder* = proc(ecsSeq: var EcsSeqAny): int
type Mover* = proc(fromEcsSeq: var EcsSeqAny, index: int, toEcsSeq: var EcsSeqAny): int {.nimcall.}

iterator ids*(self: EcsSeqAny): int =
  for index in 0..<self.deleted.len:
    if not self.deleted[index]:
      yield index

proc add*[T](self: EcsSeq[T], item: sink T): int =
  if self.free.len > 0:
    let index = self.free.pop()
    self.data[index] = item
    self.deleted[index] = false
    result = index
  else:
    self.data.add item
    self.deleted.add false
    result = self.data.len - 1

proc del*(self: EcsSeqAny, index: int) =
  self.deleted[index] = true
  self.free.add index

proc len*(self: EcsSeqAny): int =
  self.deleted.len - self.free.len

proc has*(self: EcsSeqAny, index: int): bool =
  index >= 0 and
  index < self.deleted.len and
  not self.deleted[index]

proc `[]`*[T](self: EcsSeq[T], index: int): var T =
  self.data[index]

proc `[]=`*[T](self: var EcsSeq[T], index: int, value: T) =
  if index >= self.data.len:
    let oldLen = self.data.len
    self.data.setLen(index + 1)
    self.deleted.setLen(index + 1)

    for i in oldLen ..< self.data.len - 1:
      self.deleted[i] = true
      self.free.add i

  self.data[index] = value
  self.deleted[index] = false

proc `$`*[T](self: EcsSeq[T]): string =
  result &= "@["

  for i in 0..<self.data.len:
    if not self.deleted[i]:
      result &= $self.data[i]
      if i < self.data.len - 1:
        result &= ", "

  result &= "]"

proc ecsSeqBuilder*[T](): Builder =
  proc(): EcsSeqAny = EcsSeq[T]()

proc ecsSeqMover*[T](): Mover =
  proc(fromEcsSeq: var EcsSeqAny, index: int, toEcsSeq: var EcsSeqAny): int =
    var typedFromEcsSeq = cast[EcsSeq[T]](fromEcsSeq)
    var typedToEcsSeq = cast[EcsSeq[T]](toEcsSeq)
    let element = typedFromEcsSeq[index]
    fromEcsSeq.del index
    result = typedToEcsSeq.add element
