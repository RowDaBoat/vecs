import std/hashes
import std/macros


type ComponentId* = distinct int

proc `$`*(id: ComponentId): string =
  $id.int

macro compeed*[T](typ: typedesc[T]): int =
  typ.getTypeInst.repr.hash.newIntLitNode

type A = object
type B = object

echo "compeed[A]:", compeed(A)
echo "compeed[B]:", compeed(B)

assert compeed(A) == compeed(A), "A and A should always have the same compeed"
assert compeed(A) != compeed(B), "A and B should always have different compeeds"
