# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../../src/[vecs, id]


type
  Node = object
    name: string
    parentId: Id[Node]
    childrenIds: seq[Id[Node]]


  Transform = object
    position: array[3, float32]
    rotation: array[4, float32]


  Point = object
    x: float32
    y: float32


  Shape = object
    origin: Point


  Frame = object
    matrix: array[4, float32]


  Placement = object
    frame: Frame


  Inside = object
    target: Id[Node]
    entity: EntityId


  Outside = object
    inside: Inside


  Leaf = object
    value: float32


  Branch = object
    leaf: Leaf


  Trunk = object
    branch: Branch


suite "Text (JSON) serialization of complex fields should":
  test "round-trip an Id[] field":
    var world = World()
    let rootId = world.add((Node(name: "root"),), Immediate) of Node
    let childId = world.add((Node(name: "child", parentId: rootId),), Immediate) of Node

    let text = world.serializeToText((Node,))
    var restored = deserializeFromText(text, (Node,))

    checkpoint("The child's parentId should still point at the root entity.")
    check restored.read(childId).parentId == rootId

    checkpoint("The root has no parent, so parentId should stay invalid.")
    check restored.read(rootId).parentId == Id[Node]()


  test "round-trip a seq of Id[] fields":
    var world = World()
    let rootId = world.add((Node(name: "root"),), Immediate) of Node
    let childAId = world.add((Node(name: "childA", parentId: rootId),), Immediate) of Node
    let childBId = world.add((Node(name: "childB", parentId: rootId),), Immediate) of Node

    for parent in world.write(rootId):
      parent.childrenIds = @[childAId, childBId]

    let text = world.serializeToText((Node,))
    var restored = deserializeFromText(text, (Node,))

    check restored.read(rootId).childrenIds == @[childAId, childBId]


  test "round-trip a fixed size array field":
    var world = World()
    let transform = Transform(position: [1.0'f32, 2.0'f32, 3.0'f32], rotation: [0.0'f32, 0.0'f32, 0.0'f32, 1.0'f32])
    let entityId = world.add((transform,), Immediate)

    let text = world.serializeToText((Transform,))
    var restored = deserializeFromText(text, (Transform,))

    check restored.read(entityId, Transform) == transform


  test "round-trip a nested object field":
    var world = World()
    let shape = Shape(origin: Point(x: 3.0'f32, y: 4.0'f32))
    let entityId = world.add((shape,), Immediate)

    let text = world.serializeToText((Shape,))
    var restored = deserializeFromText(text, (Shape,))

    check restored.read(entityId, Shape) == shape


  test "round-trip a nested object field holding a fixed size array":
    var world = World()
    let placement = Placement(frame: Frame(matrix: [1.0'f32, 0.0'f32, 0.0'f32, 1.0'f32]))
    let entityId = world.add((placement,), Immediate)

    let text = world.serializeToText((Placement,))
    var restored = deserializeFromText(text, (Placement,))

    check restored.read(entityId, Placement) == placement


  test "round-trip ids held inside a nested object":
    var world = World()
    let rootId = world.add((Node(name: "root"),), Immediate) of Node
    let holderId = world.add((Outside(inside: Inside(target: rootId, entity: rootId.entityId)),), Immediate)

    let text = world.serializeToText((Node, Outside))
    var restored = deserializeFromText(text, (Node, Outside))
    let inside = restored.read(holderId, Outside).inside

    checkpoint("An Id[] two levels down should survive.")
    check inside.target == rootId

    checkpoint("A plain EntityId two levels down should survive.")
    check inside.entity == rootId.entityId


  test "round-trip plain objects nested several levels deep":
    var world = World()
    let trunk = Trunk(branch: Branch(leaf: Leaf(value: 2.5'f32)))
    let entityId = world.add((trunk,), Immediate)

    let text = world.serializeToText((Trunk,))
    var restored = deserializeFromText(text, (Trunk,))

    check restored.read(entityId, Trunk) == trunk
