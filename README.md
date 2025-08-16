# vecs

Vexel's ECS library for Nim👑, heavily inspired by [Beef🥩](https://github.com/beef331)'s [yeacs](https://github.com/beef331/nimtrest/blob/master/yeacs.nim), a lot of his ideas were used, and some of his macros were directly copied.

`vecs`'s API aims to be mostly the same, with minor differences.

The main design differences between `vecs` and `yeacs` are in the implementation:
- `vecs` avoids manually copying memory, erasure is implemented by using abstract types, then casting to concrete types when needed. This simplifies book-keeping a bit, and goes easier on references, not needing to track move semantics.
- `vecs` approaches ECS with a collection for each component in the archetype, while `yeacs` instead uses a single collection of tuples of components for each archetype.

## Usage
```nim
# Create a world
var world = World()
```
```nim
# Add an entity
let entityId = world.addEntity (
  Character(name: "Marcus", class: "Warrior"),
  Health(health: 120, maxHealth: 120)
)
```
```nim
# Get a component from an entity
for health in world.component(entityId, Health):
  health.health += 75
```
```nim
# Get multiple components from an entity
for (character, health) in world.component(entityId, (Character, Health)):
  character.name = "Happy " & character.name
  health.health += 75
```
```nim
# Query for components
var characterWithSwordsQuery {.global.} = Query[(Character, Sword)]()
for (character, sword) in world.query(characterWithSwordsQuery):
  echo character.name, " has a sword, ", sword.name, "!"
```
```nim
# Removing an entity
world.removeEntity entityId
```
```nim
# Adding a component
world.addComponent(entityId, Shield(name: "Steel Shield", defense: 15))
```
```nim
# Removing a component
world.removeComponent(entityId, Shield)
```

## Roadmap
- [x] Add entities
- [x] Archetypes
- [x] Queries
- [x] Remove entities
- [x] Support dynamic archetypes
- [x] Add component
- [x] Remove component
- [ ] Special Id component
- [ ] 'Not' Queries
- [ ] Stable ids for components
- [ ] Foreach or non-caching queries
- [ ] Add and Remove multiple components
- [ ] Text serialization
- [ ] Polish console output
- [ ] Binary serialization
- [ ] Zero-allocation?
- [ ] Spatial queries

## Notes on static/dynamic archetypes
Building the archetypes with macros that iterate on tuple fields limits what the system can do in runtime, for example, anything combining components on an archetype that's not existing in compile-time (ie: getting an unexpected combination from an edited save-file), will absolutely fail in runtime.

To remove the need for macros and make archetypes dynamic, the archertype constructor must:
- Not use generic types.
- Receive the `ArchetypeId` computed from the components.
- Receive factory procs of type-erased collections for each component included in the archetype.

With this approach, the system must know which components will be used beforehand, losing a bit of simplicity by forcing something like `var world = world(CompA, CompB, CompC, CompD)`.

However, incidentally, declaring the component types beforehand, also allows stabilizing their ids easily.
