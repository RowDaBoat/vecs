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
var characterWithSwordsQuery = Query[(Character, Sword)]()
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
```nim
# Using an Id component fills it with the Id of the entity
# This is useful for embedding references to other entities into components
let entityId = world.addEntity (Id(), Character(name: "Leon", class: "Paladin"))

for idComponent in world.component(entityId, Id):
  assert entityId == idComponent
```


## Advanced querying
```nim
# Query components for writting
var characterWithSwordsQuery = Query[(Character, Write[Health])]()
for (character, health) in world.query(characterWithSwordsQuery):
  health.health += 10
```
```nim
# Query for optional components
var characterWithSwordsQuery = Query[(Character, Opt[Weapon])]()
for (character, weapon) in world.query(characterWithSwordsQuery):
  weapon.isSmoething:
    echo character.name, " has a weapon, ", weapon.name
  weapon.isNothing:
    echo character.name, " has no weapon"
```
```nim
# Exclude components from a query
var disarmedCharacters = Query[(Character, Not[Weapon])]()
for (character,) in world.query(disarmedCharacters):
  echo character.name, " has no weapon"
```

## Roadmap
- [x] Add entities
- [x] Archetypes
- [x] Queries
- [x] Remove entities
- [x] Support dynamic archetypes
- [x] Add component
- [x] Remove component
- [x] Special Id component
- [x] Restrict generic T on queries and components procs to be tuples
- [ ] Convenience
  - [ ] Allow read access to components without an iterator
  - [ ] `component` and `components` should accept a list of Ids (map?)
  - [ ] `component` fails to compile silently when used with a Tuple
  - [ ] `components` sys-fatals when searching for a non existing Id
- [x] 'Not' Queries
- [x] 'Opt' Queries
- [x] 'Write' Queries
- [ ] Stable ids for components
- [x] Polish console output
- [ ] Foreach or non-caching queries
- [ ] Add and Remove multiple components
- [ ] Text serialization
- [ ] Binary serialization
- [ ] Concurrency support
- [ ] Zero-allocation?
- [ ] Spatial queries

- [ ] Integrate with inim?
  - [ ] Pull req: show current code
  - [ ] Pull req: use nim --eval

## Notes on static/dynamic archetypes
Building the archetypes with macros that iterate on tuple fields limits what the system can do in runtime, for example, anything combining components on an archetype that's not existing in compile-time (ie: getting an unexpected combination from an edited save-file), will absolutely fail in runtime.

To remove the need for macros and make archetypes dynamic, the archertype constructor must:
- Not use generic types.
- Receive the `ArchetypeId` computed from the components.
- Receive factory procs of type-erased collections for each component included in the archetype.

With this approach, the system must know which components will be used beforehand, losing a bit of simplicity by forcing something like `var world = world(CompA, CompB, CompC, CompD)`.

However, incidentally, declaring the component types beforehand, also allows stabilizing their ids easily.
