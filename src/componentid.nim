import std/[macros, genasts, hashes, tables]


type ComponentId* = distinct uint


proc hash*(id: ComponentId): Hash {.borrow.}
proc `==`*(a, b: ComponentId): bool {.borrow.}
proc `$`*(id: ComponentId): string = $id.int


var nextComponentId* {.compileTime.} = 0'u64
var componentIds* {.compileTime.} = Table[int, ComponentId]()


macro toComponentId*[T](typ: typedesc[T]): ComponentId =
  let hash = typ.getTypeInst.repr.hash

  if hash notin componentIds:
    componentIds[hash] = ComponentId(nextComponentId)
    inc nextComponentId

  let idVal = componentIds[hash].uint

  genAst(idVal):
    ComponentId(idVal)
