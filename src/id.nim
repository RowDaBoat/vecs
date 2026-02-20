# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import world


type Id*[T] = object
  value: int = -1


proc `of`*[T](id: EntityId, desc: typedesc[T]): Id[T] =
  result = Id[T](value: id.value)


proc `of`*[T](id: Id[auto], desc: typedesc[T]): Id[T] =
  result = Id[T](value: id.value)


proc `entityId`*[T](id: Id[T]): EntityId =
  EntityId(value: id.value)


template has*[T](world: var World, id: Id[T]): bool =
  world.has(id.entityId, T)


template read*[T](world: var World, id: Id[T]): T =
  world.read(id.entityId, T)


template write*[T](world: var World, id: Id[T]): var T =
  world.write(id.entityId, T)


template read*[T: tuple](world: var World, id: Id[T]): T =
  world.read(id.entityId, T)


template components*[T: tuple](world: var World, id: Id[T]): auto =
  world.components(id.entityId, T)


template remove*[T: tuple](world: var World, id: Id[T], mode: OperationMode = Deferred) =
  world.remove(id.entityId, T, mode)


template remove*[T](world: var World, id: Id[T], mode: OperationMode = Deferred) =
  world.remove(id.entityId, T, mode)
