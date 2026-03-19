# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import std/[macros, hashes]


type EventKind* = distinct int


type EventQueue*[T] = ref object of RootObj
  data*: seq[T]


proc `==`*(a, b: EventKind): bool = a.int == b.int
proc hash*(a: EventKind): Hash = hash(a.int)


macro eventKindFrom*[T](typ: typedesc[T]): EventKind =
  newTree(nnkCast, bindSym"EventKind", newLit(typ.getTypeInst.repr.hash))

