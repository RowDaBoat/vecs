import archetype

type Query*[T] = object
  matchedArchetypes*: seq[ArchetypeId]
  lastArchetypeCount*: int
