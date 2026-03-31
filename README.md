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
# Import the library
import vecs
```
```nim
# Declare some components, components are regular value objects.
type Charcter = object
  name*: string
  class*: string

type Health = object
  current*: int
  max*: int

type Weapon = object
  name*: string
  attack*: int
```
```nim
# Create a world
var world = World()
```
```nim
# Add an entity with components
let entityId = world.add (
  Character(name: "Marcus", class: "Warrior"),
  Health(current: 120, max: 120)
)
```
```nim
# Get a component from an entity to read its values
let health = world.read(entityId, Health)
echo health.current " / " & health.max
```
```nim
# Get a component from an entity with write access
for health in world.write(entityId, Health):
  health.current += 75
```
```nim
# Read multiple components from an entity
let (character, health) = world.read(entityId, (Character, Health))
echo character.name & "'s health is: " & health.current
```
```nim
# Write to multiple components from an entity
for (character, health) in world.components(entityId, (Write[Character], Write[Health])):
  character.name = "Happy " & character.name
  health.current += 75
```
```nim
# Query for components
var characterWithSwordsQuery = Query[(Character, Write[Sword])]()
for (character, sword) in world.query(characterWithSwordsQuery):
  sword.attack += 10
  echo character.name, "'s weapon ", sword.name, " reforged!"
```
```nim
# Removing an entity
world.remove entityId
```
```nim
# Adding a component
world.add(entityId, Shield(name: "Steel Shield", defense: 15))
```
```nim
# Removing a component
world.remove(entityId, Shield)
```
```nim
# The `Meta` component is automatically added, and holds the `Id` of the entity.
# This is useful for embedding references to other entities into components.
let entityId = world.add((Character(name: "Leon", class: "Paladin"),), Immediate)

let meta = world.read(entityId, Meta):
assert entityId == meta.id
```


### Advanced querying
```nim
# Query components for writting
var charactersWithHealth = Query[(Character, Write[Health])]()
for (character, health) in world.query(charactersWithHealth):
  health.current += 10
```
```nim
# Query for optional components
var charactersWithWeapons = Query[(Character, Opt[Weapon])]()
for (character, weapon) in world.query(charactersWithWeapons):
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


### Events
```nim
# Declare event types, events are regular value objects.
type DamageEvent = object
  amount: int

type HealEvent = object
  amount: int
```
```nim
# Emit an event from anywhere in the game loop
world.emit(DamageEvent(amount: 25))
world.emit(HealEvent(amount: 10))
```
```nim
# Collect and process events, the events can be collected multiple times
for event in world.collect(DamageEvent):
  echo "Damage dealt: ", event.amount
```
```nim
# Each event type is isolated — collecting DamageEvent does not affect HealEvent
for event in world.collect(HealEvent):
  echo "Health restored: ", event.amount
```
```nim
# Calling consolidate() drains all event queues
world.consolidate()

for event in world.collect(DamageEvent):
  echo "Won't be called"
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
- [x] Add `after` operation mode, that processes add/remove operations after a query is iterated
- [x] Minimal events system
- [ ] Binary serialization
- [ ] Integrate with [reploid](http://github.com/RowDaBoat/reploid)
- [ ] Convenience procs
  - [ ] `component` and `components` accept a list of entity ids
  - [ ] Add and Remove multiple components
- [ ] Concurrency support
- [ ] Zero-allocation?
- [ ] Spatial and custom queries
 
