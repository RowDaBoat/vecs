#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import options
import archetype

type Opt*[T] = Option[T]

type Not*[T] = object
  discard

type Write*[T] = object
  discard

type Query*[T: tuple] = object
  matchedArchetypes*: seq[ArchetypeId]
  lastArchetypeCount*: int
  lastVersion*: int

template isSomething*[T](self: Opt[T], body: untyped) =
  if self.isSome:
    let value {.inject.} = self.get
    body

template isNothing*[T](self: Opt[T], body: untyped) =
  if self.isNone:
    body

proc reset*[T: tuple](query: var Query[T], version: int) =
  query.matchedArchetypes = @[]
  query.lastArchetypeCount = 0
  query.lastVersion = version
