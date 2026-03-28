import std/hashes
import componentid


type ArchetypeId* = object
  components: uint64


proc incl*(self: var ArchetypeId, componentId: ComponentId) =
  self.components = self.components or (1.uint64 shl componentId.uint64)


proc excl*(self: var ArchetypeId, componentId: ComponentId) =
  self.components = self.components and (not (1.uint64 shl componentId.uint64))


proc archetypeIdFrom*(componentIds: seq[ComponentId]): ArchetypeId =
  for componentId in componentIds:
    result.incl componentId


proc contains*(self: ArchetypeId, componentId: ComponentId): bool =
  (self.components and (1.uint64 shl componentId.uint64)) != 0


proc contains*(self: ArchetypeId, archetypeId: ArchetypeId): bool =
  (self.components and archetypeId.components) == archetypeId.components


proc disjointed*(self: ArchetypeId, archetypeId: ArchetypeId): bool =
  (self.components and archetypeId.components) == 0'u64


proc hash*(id: ArchetypeId): Hash =
  hash(id.components)
