#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import ../vecs
import components

echo "World"
var world = World()
let ids = @[
  world.add (
    Character(name: "Marcus", class: "Warrior"),
    Health(health: 120, maxHealth: 120),
    Weapon(name: "Iron Blade", attack: 25),
    Shield(name: "Steel Shield", defense: 15),
    Armor(name: "Chain Mail", defense: 20, buffs: @["Strength"])
  ),
  world.add (
    Character(name: "Elena", class: "Mage"),
    Health(health: 80, maxHealth: 80),
    Amulet(name: "Arcane Stone", attack: 30, magic: @["Fireball", "Ice Storm", "Lightning"]),
    Armor(name: "Robe of the Archmage", defense: 10, buffs: @["Intelligence"]),
    Spellbook(spells: @["Fireball", "Ice Storm", "Lightning", "Teleport"])
  ),
  world.add (
    Character(name: "Grimm", class: "Paladin"),
    Health(health: 15, maxHealth: 100),
    Weapon(name: "Holy Avenger (Damaged)", attack: 10),
    Shield(name: "Divine Aegis", defense: 18),
    Armor(name: "Plate Armor", defense: 25, buffs: @["Strength", "Faith"]),
    Skillset(skills: @["Divine Smite", "Lay on Hands", "Aura of Protection"])
  ),
  world.add (
    Character(name: "Zara", class: "Rogue"),
    Health(health: 90, maxHealth: 90),
    Weapon(name: "Shadow Dagger", attack: 22),
    Armor(name: "Leather Armor", defense: 12, buffs: @["Agility", "Stealth"]),
    Skillset(skills: @["Backstab", "Stealth", "Lockpicking", "Trap Disarm"])
  ),
  world.add (
    Character(name: "Brom", class: "Barbarian"),
    Health(health: 140, maxHealth: 140),
    Weapon(name: "Battle Axe", attack: 32),
    Armor(name: "Fur Armor", defense: 15, buffs: @["Strength", "Rage"]),
    Skillset(skills: @["Rage", "Intimidate", "Berserker Rage"])
  ),
  world.add (
    Character(name: "Lyra", class: "Ranger"),
    Health(health: 95, maxHealth: 95),
    Weapon(name: "Hunting Bow", attack: 26),
    Armor(name: "Ranger's Cloak", defense: 8, buffs: @["Agility", "Survival"]),
    Skillset(skills: @["Track", "Survival", "Animal Companion", "Precise Shot"])
  )
]

let marcus = ids[0]
let grimm = ids[2]
let zara = ids[3]

echo ""
echo ".-----------------------------."
echo "| Single component r/w access |"
echo "'-----------------------------'"

for health in world.component(grimm, Health):
  echo "  Grimm's health: ", health
  health.health += 75
  echo "  Grimm was cured 75 hit points!"
  echo "  Grimm's health: ", health

echo ""
echo ".--------------------------------."
echo "| Multiple components r/w access |"
echo "'--------------------------------'"

for (character, sword, shield, armor) in world.components(grimm, (Character, Write[Weapon], Shield, Armor)):
  echo "  ", character.name, "'s items are:\n  sword: ", sword, "\n  shield: ", shield, "\n  armor: ", armor, "\n"
  sword.attack = 28
  sword.name = "Holy Avenger"
  echo "  Grimm's sword was repaired!\n"
  echo "  ", character.name, "'s items are:\n  sword: ", sword, "\n  shield: ", shield, "\n  armor: ", armor

echo ""
echo ".----------."
echo "| Querying |"
echo "'----------'"

var characterSkillsQuery = Query[(Character, Write[Skillset])]()

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

var charactersQuery = Query[(Character, Health)]()

echo "  Characters:"
for (character, health) in world.query(charactersQuery):
  echo "  ", character.name, " ", health

world.remove grimm
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

world.add(marcus, Skillset(skills: @["Parry", "Bash", "Riposte"]))
echo "\n  Marcus has learned a skillset!\n"

echo "  Skilled characters:"
for (character, skillset) in world.query(characterSkillsQuery):
  echo "  ", character.name, "'s skills are: ", skillset.skills

echo ""
echo ".----------------------."
echo "| Removing a component |"
echo "'----------------------'"

echo "  Skilled characters:"
for (character, skillset) in world.query(characterSkillsQuery):
  echo "  ", character.name, "'s skills are: ", skillset.skills

world.remove(zara, Skillset)
echo "\n  Zara forgot her skills!\n"

echo "  Skilled characters:"
for (character, skillset) in world.query(characterSkillsQuery):
  echo "  ", character.name, "'s skills are: ", skillset.skills

echo ""
echo ".--------------------------."
echo "| Using the Meta component |"
echo "'--------------------------'"

let id = world.add (Character(name: "Leon", class: "Paladin"),)

echo "  A character with Id: ", id

for (meta, character) in world.components(id, (Meta, Character)):
  echo "  ", character.name, " has a Meta component with the character's id: ", meta.id

echo ""
echo ".-----------------."
echo "| Complex queries |"
echo "'-----------------'"

var skilledCharacters: Query[(Character, Write[Health], Opt[Skillset], Not[Spellbook])]
for (character, health, skillset) in world.query(skilledCharacters):
  #Does not compile: character.name = "Refreshed " + character.name
  echo character.name, "'s health is ", health.health, "/", health.maxHealth
  health.health += 10

  skillset.isSomething:
    echo "  Skills: ", value
echo "\nOverhealed!\n"
var healthQuery: Query[(Character, Health, Not[Spellbook])]
for (character, health) in world.query(healthQuery):
  echo character.name, "'s health is now ", health.health, "/", health.maxHealth

echo world.show (Meta, Character, Health, Weapon, Amulet, Shield, Armor, Spellbook, Skillset)
