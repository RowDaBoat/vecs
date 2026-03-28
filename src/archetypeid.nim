import std/[hashes, macros]
import componentid


func replace(node: NimNode, target, replacement: NimNode): NimNode =
  if node.eqIdent(target):
    return replacement

  result = node.copyNimNode()

  for child in node:
    result.add child.replace(target, replacement)


macro unroll*(idx: untyped, lo, hi: static int, body: untyped): untyped =
  result = newNimNode(nnkStmtList)
  for i in lo ..< hi:
    result.add nnkBlockStmt.newTree(newEmptyNode(), body.replace(idx, newLit(i)))


const ArchetypeWords* {.intdefine.} = 1
static: assert ArchetypeWords > 0, "ArchetypeWords must be greater than 1"


type ArchetypeId* = object
  components: array[0..(ArchetypeWords - 1), uint64]


proc incl*(self: var ArchetypeId, componentId: ComponentId) =
  let word = componentId.int div 64
  let bit = 1.uint64 shl (componentId.int mod 64)
  self.components[word] = self.components[word] or bit


proc excl*(self: var ArchetypeId, componentId: ComponentId) =
  let word = componentId.int div 64
  let bit = 1.uint64 shl (componentId.int mod 64)
  self.components[word] = self.components[word] and (not bit)


proc archetypeIdFrom*(componentIds: seq[ComponentId]): ArchetypeId =
  for componentId in componentIds:
    result.incl componentId


proc contains*(self: ArchetypeId, componentId: ComponentId): bool =
  let word = componentId.int div 64
  let bit = 1.uint64 shl (componentId.int mod 64)
  (self.components[word] and bit) != 0


proc contains*(self: ArchetypeId, archetypeId: ArchetypeId): bool =
  result = true

  unroll(i, 0, ArchetypeWords):
    let left = self.components[i]
    let right = archetypeId.components[i]

    if (left and right) != right:
      return false


proc disjointed*(self: ArchetypeId, archetypeId: ArchetypeId): bool =
  result = true

  unroll(i, 0, ArchetypeWords):
    let left = self.components[i]
    let right = archetypeId.components[i]

    if (left and right) != 0:
      return false


proc hash*(id: ArchetypeId): Hash =
  hash(id.components)
