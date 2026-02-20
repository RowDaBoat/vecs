# ISC License
# Copyright (c) 2025 RowDaBoat

import unittest
import std/assertions
import ../src/[examples, vecs, operationmodes]


suite "After operation mode should":
  setup:
    var world = World()
    var marcus = (Character(name: "Marcus"), Health(health: 100, maxHealth: 100))
    let marcusId = world.add(marcus, Immediate)


  test "add a component after a query is iterated":
    var disarmed {.global.}: Query[(Meta, Character, Not[Weapon])]
    
    for (meta, character) in world.query(disarmed):
      world.add(meta.id, Weapon(name: "Sword", attack: 10), after(disarmed))
      
      checkpoint("During iteration, entity should not have weapon yet.")
      check not world.has(meta.id, Weapon)
    
    checkpoint("After query iteration, Marcus should have a weapon.")
    check world.has(marcusId, Weapon)


  test "add multiple components after a query is iterated":
    var disarmed {.global.}: Query[(Meta, Character, Not[Weapon])]
    
    for (meta, character) in world.query(disarmed):
      var sword = (Weapon(name: "Sword", attack: 10))
      var shield = (Shield(name: "Shield", defense: 15))
      world.add(meta.id, (sword, shield), after(disarmed))
      
      checkpoint("During iteration, entity should not have weapon nor shield yet.")
      check not world.has(meta.id, Weapon)
      check not world.has(meta.id, Shield)
    
    checkpoint("After query iteration, Marcus should have a weapon and a shield.")
    check world.has(marcusId, Weapon)
    check world.has(marcusId, Shield)


  test "remove a component after a query is iterated":
    var withHealth {.global.}: Query[(Meta, Character, Health)]
    
    for (meta, character, health) in world.query(withHealth):
      world.remove(meta.id, Health, after(withHealth))
      
      checkpoint("During iteration, entity should still have health component.")
      check world.has(meta.id, Health)
    
    checkpoint("After query iteration, Marcus should not have a health component.")
    check not world.has(marcusId, Health)


  test "remove multiple components after a query is iterated":
    var withComponents {.global.}: Query[(Meta, Character, Health)]
    
    for (meta, character, health) in world.query(withComponents):
      world.remove(meta.id, (Character, Health), after(withComponents))
      
      checkpoint("During iteration, entity should still have character and health components.")
      check world.has(meta.id, Character)
      check world.has(meta.id, Health)
    
    checkpoint("After query iteration, Marcus should not have character nor health components.")
    check not world.has(marcusId, Character)
    check not world.has(marcusId, Health)


  test "add an entity after a query is iterated":
    var emptyQuery {.global.}: Query[(Meta,)]
    var newEntity = (Character(name: "Alice"), Health(health: 50, maxHealth: 50))
    var aliceId: EntityId
    
    for (meta,) in world.query(emptyQuery):
      aliceId = world.add(newEntity, after(emptyQuery))

      checkpoint("During iteration, Alice should exist but not have components yet.")
      check world.has(aliceId)
      check not world.has(aliceId, Character)
      check not world.has(aliceId, Health)

    checkpoint("After query iteration, Alice should have components.")
    check world.has(aliceId, Character)
    check world.has(aliceId, Health)


  test "remove an entity after a query is iterated":
    var allEntities {.global.}: Query[(Meta,)]
    
    for (meta,) in world.query(allEntities):
      world.remove(meta.id, after(allEntities))
      
      checkpoint("During iteration, entity should still exist.")
      check world.has(meta.id)
    
    checkpoint("After query iteration, Marcus should not exist.")
    check not world.has(marcusId)
