# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.

const
  ENTITY_ID_POS* = 32
  ENTITY_ID_MASK* = (1'u64 shl ENTITY_ID_POS) - 1
  ENTITY_GEN_MASK* = not ENTITY_ID_MASK
  INVALID_ENTITY_VALUE* = int(ENTITY_ID_MASK)

type EntityId* = object
  val*: uint64 = ENTITY_ID_MASK

proc value*(e: EntityId): int = int(e.val and ENTITY_ID_MASK)
proc generation*(e: EntityId): int = int((e.val and ENTITY_GEN_MASK) shr ENTITY_ID_POS)
proc isValid*(e: EntityId): bool = e.value != INVALID_ENTITY_VALUE

template makeVal(gen, val: untyped): uint64 =
  (uint64(gen) shl ENTITY_ID_POS) or uint64(val)

proc `value=`*(e: var EntityId, val: int) =
  e.val = makeVal(e.generation, val)

proc `generation=`*(e: var EntityId, gen: int) =
  e.val = makeVal(gen, e.value)

proc newEntityId*(gen, val: int): EntityId =
  EntityId(val: makeVal(gen, val))

