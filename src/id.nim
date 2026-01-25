import world


type Id*[T] = object
  value: int = -1


proc `of`*[T](id: EntityId, desc: typedesc[T]): Id[T] =
  result = Id[T](value: id.value)


proc `of`*[T](id: Id[auto], desc: typedesc[T]): Id[T] =
  result = Id[T](value: id.value)


proc `entityId`*[T](id: Id[T]): EntityId =
  EntityId(value: id.value)


template hasComponent*[T](world: var World, id: Id[T]): bool =
  world.hasComponent(id.entityId, T)


template readComponent*[T](world: var World, id: Id[T]): T =
  world.readComponent(id.entityId, T)


template component*[T](world: var World, id: Id[T]): var T =
  world.component(id.entityId, T)


template readComponents*[T: tuple](world: var World, id: Id[T]): T =
  world.readComponents(id.entityId, T)


template components*[T: tuple](world: var World, id: Id[T]): auto =
  world.components(id.entityId, T)


template removeComponents*[T: tuple](world: var World, id: Id[T], mode: OperationMode = Deferred) =
  world.removeComponents(id.entityId, T, mode)


template removeComponent*[T](world: var World, id: Id[T], mode: OperationMode = Deferred) =
  world.removeComponent(id.entityId, T, mode)
