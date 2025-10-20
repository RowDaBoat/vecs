import ../archetype

type Query*[T: tuple] = object
  matchedArchetypes*: seq[ArchetypeId]
  lastArchetypeCount*: int
