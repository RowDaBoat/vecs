# vecs

Vexel's ECS library for Nim👑, heavily inspired by [Beef🥩](https://github.com/beef331)'s [yeacs](https://github.com/beef331/nimtrest/blob/master/yeacs.nim), a lot of his ideas were used, and some of his macros were directly copied.

`vecs`'s API aims to be mostly the same, with minor differences.

The main design differences between `vecs` and `yeacs` are in the implementation:
- `vecs` avoids manually copying memory, erasure is implemented by using abstract types, then casting to concrete types when needed. This simplifies book-keeping a bit, and goes easier on references, not needing to track move semantics.
- `vecs` approaches ECS with a collection for each component in the archetype, while `yeacs` instead uses a single collection of tuples of components for each archetype.


## Documentation
The API reference is available [here](https://rowdaboat.github.io/vecs/).


### Basic Usage
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


### Advanced querying
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
- [x] 'Not' Queries
- [x] 'Opt' Queries
- [x] 'Write' Queries
- [x] Stable ids for components
- [x] Polish console output
- [x] Convenience procs and checks
- [x] Refactor `Id` component to a `Metadata` component with id, removal, and addition info
- [x] Additions and removals should be enqueued and consolidated in order later
- [x] Text serialization
- [ ] Binary serialization
- [ ] Integrate with [reploid](http://github.com/RowDaBoat/reploid)
- [ ] Convenience procs
  - [ ] `component` and `components` accept a list of entity ids
  - [ ] Add and Remove multiple components
- [ ] Concurrency support
- [ ] Zero-allocation?
- [ ] Spatial and custom queries
