type EcsSeqAny* = ref object of RootObj
  deleted: seq[bool]
  free: seq[int]

type EcsSeq*[T] = ref object of EcsSeqAny
  data: seq[T]

proc ecsSeqBuilder*[T](): proc(): EcsSeqAny =
  proc(): EcsSeqAny = EcsSeq[T]()

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

proc del*(self: EcsSeqAny, index: Natural) =
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
