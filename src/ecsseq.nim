# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unsafeseq

type EcsSeqAny* = ref object of RootObj
  stride*: int
  rawPtr*: pointer


type EcsSeq*[T] = ref object of EcsSeqAny
  data: VSeq[T]


type AddItemAny* = ref object of RootObj
  raw*: pointer


type AddItem*[T] = ref object of AddItemAny
  data*: T


type Builder* =
  proc(): EcsSeqAny {.nimcall.}


type Getter* =
  proc(fromEcsSeq: EcsSeqAny, index: int): EcsSeqAny {.nimcall.}


proc ensureInitialized[T](self: EcsSeq[T]) =
  if self.rawPtr == nil:
    self.stride = sizeof(T)
    self.rawPtr = addr self.data


proc add*(self: EcsSeqAny, item: ptr byte): int =
  self.rawPtr.unsafeAddAndZero(item, self.stride)
  result = self.rawPtr.unsafeSeqLen - 1


proc add*[T](self: EcsSeq[T], item: sink T): int =
  self.ensureInitialized()
  self.data.add item
  self.data.len - 1


proc addAt*(self: EcsSeqAny, index: int, value: ptr byte) =
  if index >= self.rawPtr.unsafeSeqLen:
    if index >= self.rawPtr.unsafeSeqCap: self.rawPtr.growPayload(self.stride, index + 1)
    self.rawPtr.seqLenPtr[] = index + 1
  self.rawPtr.unsafeSetAndZero(index, value, self.stride)


proc addAt*[T](self: EcsSeq[T], index: int, value: sink T) =
  if index >= self.data.len:
    self.data.setLen(index + 1)
  self.data[index] = value


proc len*[T](self: EcsSeq[T]): int =
  self.data.len


proc len*(self: EcsSeqAny): int =
  self.rawPtr.unsafeSeqLen()


proc `[]`*[T](self: EcsSeq[T], index: int): var T =
  self.data[index]


proc `[]=`*[T](self: EcsSeq[T], index: int, value: sink T) =
  self.data[index] = value


proc `$`*[T](self: EcsSeq[T]): string =
  $self.data


proc newAddItem*[T](val: sink T): AddItem[T] =
  result = AddItem[T](data: val)
  result.raw = addr result.data


proc newEcsSeq*[T](): EcsSeq[T] =
  result = EcsSeq[T](stride: sizeof(T), data: newVSeq[T]())
  result.rawPtr = addr result.data


proc buildEcsSeq[T](): EcsSeqAny =
  newEcsSeq[T]()


proc ecsSeqBuilder*[T](): Builder =
  proc(): EcsSeqAny = buildEcsSeq[T]()


proc rawGet*(self: EcsSeqAny, index: int): pointer {.inline.} =
  self.rawPtr.unsafeGet(index, self.stride)


proc moveEcsSeq*(fromEcsSeq: var EcsSeqAny, fromIndex: int, toEcsSeq: var EcsSeqAny, toIndex: int) =
  let element = fromEcsSeq.rawGet(fromIndex)
  toEcsSeq.addAt(toIndex, cast[ptr byte](element))


proc ecsSeqGetter*[T](): Getter =
  proc(fromEcsSeq: EcsSeqAny, index: int): EcsSeqAny {.nimcall.} =
    let source = cast[EcsSeq[T]](fromEcsSeq)
    let snapshot = EcsSeq[T]()
    snapshot.ensureInitialized()
    snapshot.addAt(0, source[index])
    snapshot
