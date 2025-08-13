type ComponentId* = distinct int

var nextComponentId = 0

proc componentIdFrom*[T](desc: typedesc[T]): ComponentId =
  var id {.global.}: int
  once:
    id = nextComponentId
    inc nextComponentId
  id.ComponentId

proc `$`*(id: ComponentId): string =
  $id.int
