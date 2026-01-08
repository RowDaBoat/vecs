#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import tables
import vecs
import component
import intsets
import archetype
import textTable


type Spec*[T: tuple] = object
  discard


proc show[T](component: T, maxWidth: int): seq[string] =
  for name, value in fieldPairs(component):
    var entry = name & ": " & $value

    if entry.len > maxWidth:
      entry = entry.substr(0, maxWidth - 3) & "..."

    result.add entry


proc getArchetypeTable[T: tuple](world: var World, archetype: Archetype, maxWidth: int): seq[seq[seq[string]]] =
  for name, typ in fieldPairs default T:
    let componentId = world.componentIdFrom typeof typ

    if archetype.componentLists.hasKey(componentId):
      var column = @[ @[ $typeof(typ)] ]

      for component in components[typeof typ](archetype, componentId):
        column.add(show(component, maxWidth))

      result.add @[ column ]


proc show*[T: tuple](world: var World, tupleDesc: typedesc[T], maxWidth: int = 20): string =
  for archetype in world.archetypes:
    let archetypeTable = getArchetypeTable[T](world, archetype, maxWidth)
    result &= ".-----------.\n"
    result &= "| Archetype |\n"
    result &= textTable(archetypeTable) & "\n"
