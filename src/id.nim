# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import world


type Id*[T] = object
  val: uint64 = ENTITY_ID_MASK


proc value*[T](e: Id[T]): int =
  int(e.val and ENTITY_ID_MASK)


proc generation*[T](e: Id[T]): int =
  int((e.val and ENTITY_GEN_MASK) shr ENTITY_ID_POS)


proc isValid*[T](e: Id[T]): bool =
  e.value != INVALID_ENTITY_VALUE


template makeVal(gen, val: untyped): uint64 =
  (uint64(gen) shl ENTITY_ID_POS) or uint64(val)


proc `value=`*[T](e: var Id[T], val: int) =
  e.val = makeVal(e.generation, val)


proc `generation=`*[T](e: var Id[T], gen: int) =
  e.val = makeVal(gen, e.value)


proc newId*[T](gen, val: int): Id[T] =
  Id[T](val: makeVal(gen, val))


proc `of`*[T](id: EntityId, desc: typedesc[T]): Id[T] =
  result = Id[T](val: id.val)


proc `of`*[T](id: Id[auto], desc: typedesc[T]): Id[T] =
  result = Id[T](val: id.val)


proc `entityId`*[T](id: Id[T]): EntityId =
  EntityId(val: id.val)


proc `entityId=`*[T](id: var Id[T], entityId: EntityId) =
  id.val = entityId.val


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
