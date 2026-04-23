# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/examples
import ../src/vecs
import ../src/id


type Node = object
  name: string
  children: seq[Id[Node]]


proc node(w: var World, name: string, children: varargs[Id[Node]]): Id[Node] =
  w.add((Node(name: name, children: @children),), Immediate) of Node


suite "Id should":
  setup:
    var world = World()
    let marcus = (Character(name: "Marcus"), Health(health: 100, maxHealth: 100))
    let marcusId = world.add(marcus, Immediate)


  test "convert EntityId to Id and back":
    let id = marcusId of Character
    let backToEntityId = id.entityId

    check backToEntityId == marcusId


  test "convert an Id of a type to an Id of another type":
    let characterId = marcusId of Character
    let nodeId = characterId of Node

    check nodeId.entityId == marcusId


  test "check if entity has component":
    let id = marcusId of Character

    check world.has(id)


  test "read a single component":
    let id = marcusId of Character
    let character = world.read(id)

    check character.name == "Marcus"


  test "write to a single component via iterator":
    let id = marcusId of Health

    for health in world.write(id):
      health.health = 50

    check world.read(marcusId, Health).health == 50


  test "read multiple components":
    let id = marcusId of (Character, Health)

    let (character, health) = world.read(id)

    check character.name == "Marcus"
    check health.health == 100


  test "access multiple components via iterator":
    let id = marcusId of (Character, Health)

    for (character, health) in world.components(id):
      check character.name == "Marcus"
      check health.health == 100


  test "use Ids to access components":
    var w = World()

    let root =
      w.node("A",
        w.node("B",
          w.node("D")),
        w.node("C",
          w.node("E"),
          w.node("F")))

    var visited: seq[string] = @[]
    var stack = @[root]

    while stack.len > 0:
      let current = stack.pop()
      let node = w.read(current)
      visited.add node.name

      for i in countdown(node.children.high, 0):
        stack.add node.children[i]

    check visited == @["A", "B", "D", "C", "E", "F"]
