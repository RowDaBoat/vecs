#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import std/macros


type Id* = object
  id*: int = -1


type Meta* = object
  id*: Id


macro WithMeta*[T: tuple](t: typedesc[T]): typedesc =
  let tupleType = t.getTypeInst[^1]
  result = tupleType.copyNimTree
  result.insert(0, ident"Meta")


proc withMeta*[T: tuple](t: T): WithMeta(T) =
  macro prependMeta(): untyped =
    var arg = bindSym("t")
    result = newNimNode(nnkTupleConstr)
    result.add newCall(ident"Meta")

    for i, d in pairs(arg.getTypeImpl):
      result.add newTree(nnkBracketExpr, arg, newLit(i))

  result = prependMeta()


proc id*(meta: Meta): Id =
  meta.id
