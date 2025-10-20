import std/options; export options

type Opt*[T] = Option[T]

template isSomething*[T](self: Opt[T], body: untyped) =
  if self.isSome:
    let value {.inject.} = self.get
    body

template isNothing*[T](self: Opt[T], body: untyped) =
  if self.isNone:
    body
