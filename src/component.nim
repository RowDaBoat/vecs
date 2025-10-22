type ComponentId* = distinct int

proc `$`*(id: ComponentId): string =
  $id.int
