import archetype

#[: ComponentTuple ]#
type Query*[T] = object
  matchedArchetypes*: seq[ArchetypeId]
  lastArchetypeCount*: int
