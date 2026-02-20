# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
type
  Character* = object
    name*: string
    class*: string

  Health* = object
    health*: int
    maxHealth*: int

  Weapon* = object
    name*: string
    attack*: int

  Amulet* = object
    name*: string
    attack*: int
    magic*: seq[string]

  Shield* = object
    name*: string
    defense*: int

  Armor* = object
    name*: string
    defense*: int
    buffs*: seq[string]

  Spellbook* = object
    spells*: seq[string]

  Skillset* = object
    skills*: seq[string]
