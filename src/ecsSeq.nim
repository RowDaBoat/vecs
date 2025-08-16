type EcsSeqAny* = ref object of RootObj
  deleted: seq[bool]
  free: seq[int]

type EcsSeq*[T] = ref object of EcsSeqAny
  data: seq[T]

type Builder* = proc(): EcsSeqAny

type Adder* = proc(ecsSeq: var EcsSeqAny): int

type Mover* = proc(fromEcsSeq: var EcsSeqAny, index: int, toEcsSeq: var EcsSeqAny): int

type Shower* = proc(ecsSeq: EcsSeqAny): string

iterator ids*(self: EcsSeqAny): int =
  for index in 0..<self.deleted.len:
    if not self.deleted[index]:
      yield index

proc add*[T](self: EcsSeq[T], item: T): int =
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

proc `[]`*[T](self: EcsSeq[T], index: int): var T =
  self.data[index]

proc `[]=`*[T](self: var EcsSeq[T], index: int, value: T) =
  self.data[index] = value

proc len*[T](self: EcsSeq[T]): int =
  self.data.len - self.free.len

proc `$`*[T](self: EcsSeq[T]): string =
  result &= "@["

  for i in 0..<self.data.len:
    if not self.deleted[i]:
      result &= $self.data[i]
      if i < self.data.len - 1:
        result &= ", "

  result &= "]"

proc ecsSeqBuilder*[T](): proc(): EcsSeqAny =
  proc(): EcsSeqAny = EcsSeq[T]()

proc ecsSeqMover*[T](): Mover =
  proc(fromEcsSeq: var EcsSeqAny, index: int, toEcsSeq: var EcsSeqAny): int =
    var typedFromEcsSeq = cast[EcsSeq[T]](fromEcsSeq)
    var typedToEcsSeq = cast[EcsSeq[T]](toEcsSeq)
    let element = typedFromEcsSeq[index]
    fromEcsSeq.del index
    result = typedToEcsSeq.add element

proc ecsSeqShower*[T](): Shower =
  proc(ecsSeq: EcsSeqAny): string =
     $cast[EcsSeq[T]](ecsSeq)
