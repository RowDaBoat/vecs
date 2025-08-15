import std/[packedsets, hashes, macros, intsets]
import typetraits
import tables
import archetype
import entity
import component
import ecsSeq
import query

type Id* = object
  id: int

type Not*[T] = distinct T

type World = object
  entities: EcsSeq[Entity] = EcsSeq[Entity]()
  archetypes: Table[ArchetypeId, Archetype]
  builders: Table[ComponentId, Builder]
  movers: Table[ComponentId, Mover]
  nextComponentId: int

proc hash*(id: ArchetypeId): Hash =
  for compId in id.items:
    result = result xor (compId.int mod 32)

proc archetypeIdFrom*[T: tuple](world: var World, desc: typedesc[T]): ArchetypeId =
  for name, typ in fieldPairs default T:
    let compId = world.componentIdFrom typeof typ
    result.incl compId

proc archetypeFrom*[T: tuple](world: var World, tupleDesc: typedesc[T]): var Archetype =
  let archetypeId = world.archetypeIdFrom T

  if not world.archetypes.hasKey(archetypeId):
    var componentIds: seq[ComponentId] = @[]
    var builders: seq[Builder] = @[]
    var movers: seq[Mover] = @[]

    for name, typ in fieldPairs default T:
      let compId = world.componentIdFrom typeof typ
      componentIds.add compId
      builders.add world.builders[compId]
      movers.add world.movers[compId]

    world.archetypes[archetypeId] = makeArchetype(componentIds, builders, movers)

  world.archetypes[archetypeId]

proc nextArchetypeFrom(world: var World, previousArchetype: Archetype, componentId: ComponentId): var Archetype =
  let previousArchetypeId = previousArchetype.id
  var nextArchetypeId = previousArchetypeId
  nextArchetypeId.incl componentId

  if not world.archetypes.hasKey(nextArchetypeId):
    let builder = world.builders[componentId]
    let mover = world.movers[componentId]
    world.archetypes[nextArchetypeId] = previousArchetype.makeNextAdding(@[componentId], @[builder], @[mover])

  world.archetypes[nextArchetypeId]

macro varTuple*(t: typedesc): untyped =
  result = t.getTypeInst[^1].copyNimTree

  for i in countDown(result.len - 1, 0):
    if result[i].kind == nnkBracketExpr and result[i][0] == bindSym"Not":
      result.del(i)

  for i, x in result:
    if x.kind != nnkBracketExpr:
      result[i] = nnkVarTy.newTree(x)
  result = newCall("typeof", result)

macro buildVarTuple(world: var World, t: typedesc, archetype: untyped, archetypeEntityId: untyped): untyped =
  let tupleType = t.getTypeInst[^1]
  var tupleExprs = nnkTupleConstr.newTree()
  
  for i in 0..<tupleType.len:
    let fieldType = tupleType[i]
    
    let fieldExpr = quote do:
      cast[EcsSeq[`fieldType`]](
        `archetype`.componentLists[world.componentIdFrom typeof `fieldType`]
      )[`archetypeEntityId`]
    
    tupleExprs.add(fieldExpr)

  result = tupleExprs

proc componentIdFrom*[T](world: var World, desc: typedesc[T]): ComponentId =
  var id {.global.}: int
  once:
    id = world.nextComponentId
    inc world.nextComponentId
    world.builders[id.ComponentId] = ecsSeqBuilder[T]()
    world.movers[id.ComponentId] = ecsSeqMover[T]()
  id.ComponentId

proc addEntity*[T: tuple](world: var World, components: T): Id {.discardable.} =
  var archetype = world.archetypeFrom T
  let archetypeEntityId = archetype.add components
  let id = world.entities.add Entity(archetypeId: archetype.id, archetypeEntityId: archetypeEntityId)
  Id(id: id)

proc removeEntity*(world: var World, id: Id) =
  let entity = world.entities[id.id]
  var archetype = world.archetypes[entity.archetypeId]
  archetype.remove entity.archetypeEntityId
  world.entities.del id.id

iterator component*[T](world: var World, id: Id, compDesc: typedesc[T]): var T =
  let entity = world.entities[id.id]
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId
  let compId = world.componentIdFrom typeof compDesc

  if not archetype.componentLists.hasKey(compId):
    raise newException(ValueError, "Component " & $compDesc & " not found in Entity " & $id)

  let ecsSeqAny = archetype.componentLists[compId]
  type Retype = EcsSeq[T]
  yield cast[Retype](ecsSeqAny)[archetypeEntityId]

iterator components*[T: tuple](world: var World, id: Id, tup: typedesc[T]): tup.varTuple =
  let entity = world.entities[id.id]
  let archetype = world.archetypes[entity.archetypeId]
  let archetypeEntityId = entity.archetypeEntityId

  tup.fieldTypes:
    let compId = world.componentIdFrom typeof FieldType

    if not archetype.componentLists.hasKey(compId):
      raise newException(ValueError, "Component " & $FieldType & " not found in Entity " & $id)

  yield world.buildVarTuple(tup, archetype, archetypeEntityId)

proc addComponent*[T](world: var World, id: Id, component: T) =
  var entity = world.entities[id.id]
  let componentId = world.componentIdFrom typeof T

  if entity.archetypeId.contains(componentId):
    raise newException(ValueError, "Component " & $T & " already exists in Entity " & $id)

  var previousArchetype = world.archetypes[entity.archetypeId]
  var nextArchetype = world.nextArchetypeFrom(previousArchetype, componentId)

  let adder = proc(ecsSeq: var EcsSeqAny): int =
    cast[EcsSeq[T]](ecsSeq).add component

  var adders = initTable[ComponentId, Adder]()
  adders[componentId] = adder

  entity.archetypeId = nextArchetype.id
  entity.archetypeEntityId = previousArchetype.move(entity.archetypeEntityId, nextArchetype, adders)

#proc removeComponent*[T](world: var World, id: Id) =
#  var entity = world.entities[id.id]
#  let componentId = world.componentIdFrom typeof T

#  let previousArchetype = world.archetypes[entity.archetypeId]
#  let archetypeEntityId = entity.archetypeEntityId
#  let mover = world.movers[componentId]
#  mover(archetype.componentLists[componentId], archetypeEntityId, archetype.componentLists[componentId])

iterator query*[T: tuple](world: var World, query: var Query[T]): T.varTuple =
  if world.archetypes.len != query.lastArchetypeCount:
    for archetypeId, archetype in world.archetypes.pairs:
      if archetype.matches(world.archetypeIdFrom T):
        query.matchedArchetypes.add archetypeId

    query.lastArchetypeCount = world.archetypes.len

  for archetypeId in query.matchedArchetypes:
    let archetype = world.archetypes[archetypeId]
    for index in 0..<archetype.entityCount:
      yield world.buildVarTuple(typeof T, archetype, index)

proc `$`*(entities: seq[Entity]): string =
  result &= "@[\n"

  for entity in entities:
    result &= "    " & $entity & "\n"

  result &= "  ]"

proc `$`*(archetypes: Table[ArchetypeId, Archetype]): string =
  result &= "@{\n"

  for (id, archetype) in archetypes.pairs:
    result &= "    " & $id & ": " & $archetype & "\n"

  result &= "  }"

proc `$`*(world: World): string =
  "(\n" & 
  "  entities: " & $world.entities & ",\n" &
  "  archetypes: " & $world.archetypes & "\n" &
  ")\n"

when isMainModule:
  type
    Character = object
      name: string
      class: string

    Health = object
      health: int
      maxHealth: int

    Sword = object
      name: string
      attack: int

    Staff = object
      name: string
      attack: int
      magic: seq[string]

    Shield = object
      name: string
      defense: int

    Armor = object
      name: string
      defense: int
      buffs: seq[string]

    Spellbook = object
      spells: seq[string]

    Skillset = object
      skills: seq[string]

  echo "World"
  var world = World()
  let ids = @[
    world.addEntity (
      Character(name: "Marcus", class: "Warrior"),
      Health(health: 120, maxHealth: 120),
      Sword(name: "Iron Blade", attack: 25),
      Shield(name: "Steel Shield", defense: 15),
      Armor(name: "Chain Mail", defense: 20, buffs: @["Strength"])
    ),
    world.addEntity (
      Character(name: "Elena", class: "Mage"),
      Health(health: 80, maxHealth: 80),
      Staff(name: "Arcane Staff", attack: 30, magic: @["Fireball", "Ice Storm", "Lightning"]),
      Armor(name: "Robe of the Archmage", defense: 10, buffs: @["Intelligence"]),
      Spellbook(spells: @["Fireball", "Ice Storm", "Lightning", "Teleport"])
    ),
    world.addEntity (
      Character(name: "Grimm", class: "Paladin"),
      Health(health: 15, maxHealth: 100),
      Sword(name: "Holy Avenger (Damaged)", attack: 10),
      Shield(name: "Divine Aegis", defense: 18),
      Armor(name: "Plate Armor", defense: 25, buffs: @["Strength", "Faith"]),
      Skillset(skills: @["Divine Smite", "Lay on Hands", "Aura of Protection"])
    ),
    world.addEntity (
      Character(name: "Zara", class: "Rogue"),
      Health(health: 90, maxHealth: 90),
      Sword(name: "Shadow Dagger", attack: 22),
      Armor(name: "Leather Armor", defense: 12, buffs: @["Agility", "Stealth"]),
      Skillset(skills: @["Backstab", "Stealth", "Lockpicking", "Trap Disarm"])
    ),
    world.addEntity (
      Character(name: "Brom", class: "Barbarian"),
      Health(health: 140, maxHealth: 140),
      Sword(name: "Battle Axe", attack: 32),
      Armor(name: "Fur Armor", defense: 15, buffs: @["Strength", "Rage"]),
      Skillset(skills: @["Rage", "Intimidate", "Berserker Rage"])
    ),
    world.addEntity (
      Character(name: "Lyra", class: "Ranger"),
      Health(health: 95, maxHealth: 95),
      Sword(name: "Hunting Bow", attack: 26),
      Armor(name: "Ranger's Cloak", defense: 8, buffs: @["Agility", "Survival"]),
      Skillset(skills: @["Track", "Survival", "Animal Companion", "Precise Shot"])
    )
  ]

  echo "The world:\n", world, "\n\n"

  let grimm = ids[2]

  echo ".-----------------------------."
  echo "| Single component r/w access |"
  echo "'-----------------------------'"
  for health in world.component(grimm, Health):
    echo "  Grimm's health: ", health
    health.health += 75
    echo "  Grimm was cured 75 hit points!"
    echo "  Grimm's health: ", health, "\n"

  echo ".--------------------------------."
  echo "| Multiple components r/w access |"
  echo "'--------------------------------'"
  for (character, sword, shield, armor) in world.components(grimm, (Character, Sword, Shield, Armor)):
    echo "  ", character.name, "'s items are:\n  sword: ", sword, "\n  shield: ", shield, "\n  armor: ", armor, "\n"
    sword.attack = 28
    sword.name = "Holy Avenger"
    echo "  Grimm's sword was repaired!\n"
    echo "  ", character.name, "'s items are:\n  sword: ", sword, "\n  shield: ", shield, "\n  armor: ", armor, "\n"

  echo ".----------."
  echo "| Querying |"
  echo "'----------'"

  var characterSkillsQuery {.global.} = Query[(Character, Skillset)]()
 
  echo "  Skilled characters:"
  for (character, skillset) in world.query(characterSkillsQuery):
    echo "  ", character.name, "'s skills are: ", skillset.skills

  echo ""

  for (character, skillset) in world.query(characterSkillsQuery):
    skillset.skills.add "Tracking"
    echo "  ", character.name, " learned Tracking!"

  echo ""

  for (character, skillset) in world.query(characterSkillsQuery):
    echo "  ", character.name, "'s skills are:  ", skillset.skills

  echo ""

  echo ".--------------------."
  echo "| Removing an entity |"
  echo "'--------------------'"

  var charactersQuery {.global.} = Query[(Character, Health)]()

  echo "  Characters:"
  for (character, health) in world.query(charactersQuery):
    echo "  ", character.name, " ", health

  world.removeEntity grimm
  echo "\n  Grimm left the party.\n"

  echo "  Characters:"
  for (character, health) in world.query(charactersQuery):
    echo "  ", character.name, " ", health

  echo ""

  echo ".--------------------."
  echo "| Adding a component |"
  echo "'--------------------'"

  echo "  Skilled characters:"
  for (character, skillset) in world.query(characterSkillsQuery):
    echo "  ", character.name, "'s skills are: ", skillset.skills

  world.addComponent(ids[0], Skillset(skills: @["Parry", "Bash", "Riposte"]))
  echo "Marcus has learned a skillset!\n"

  echo "\n  Skilled characters:"
  for (character, skillset) in world.query(characterSkillsQuery):
    echo "  ", character.name, "'s skills are: ", skillset.skills
