import macros, tables
import ecsseq, queries


type OperationModeKind* = enum
  DeferredMode
  ImmediateMode
  AfterMode


type OperationMode*[T: tuple] = object
  case kind*: OperationModeKind
  of DeferredMode, ImmediateMode:
    discard
  of AfterMode:
    query*: ptr[Query[T]]


let Immediate* = OperationMode[(int,)](kind: ImmediateMode)
let Deferred* = OperationMode[(int,)](kind: DeferredMode)


proc after*[T: tuple](query: var Query[T]): OperationMode[T] =
  OperationMode[T](kind: AfterMode, query: addr query)
