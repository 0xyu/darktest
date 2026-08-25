# Coding Plan

## 0. Development Rules

Read first:

- `/AGENTS.md`
- `/docs/game-design.md`
- `/docs/coding-plan.md`

Implementation rules:

1. Work incrementally.
2. Implement only the requested phase.
3. Do not implement future systems unless required by the current phase.
4. Inspect the project before making changes.
5. Reuse existing systems whenever possible.
6. Keep the project playable after every phase.
7. Keep tuning values configurable.
8. Do not introduce unnecessary plugins or external dependencies.
9. After each phase, run the project and check Godot errors/warnings.
10. Avoid large rewrites of working systems.

---

# Phase 1 — Project Initialization

## Goal

Create a clean Godot 4.x 2D project.

## Tasks

- Initialize Godot project
- Configure main scene
- Configure display/window
- Configure input actions
- Configure basic rendering defaults
- Create the initial folder structure
- Initialize Git

Target structure:

```text
res://
├── scenes/
│   ├── player/
│   ├── enemies/
│   ├── combat/
│   ├── world/
│   ├── ui/
│   └── items/
├── scripts/
│   ├── player/
│   ├── enemies/
│   ├── combat/
│   ├── systems/
│   ├── items/
│   └── ui/
├── resources/
│   ├── enemies/
│   ├── items/
│   ├── stages/
│   └── characters/
├── assets/
│   ├── characters/
│   ├── enemies/
│   ├── environment/
│   ├── ui/
│   ├── items/
│   └── effects/
├── autoload/
└── docs/
```

## Acceptance

- Project opens successfully in Godot.
- Main scene runs without errors.

---

# Phase 2 — Core Data Architecture

## Goal

Create stable data models before complex gameplay.

## Create

Player:

- `PlayerStats`
- `PlayerProgression`

Enemy:

- `EnemyDefinition`
- `EnemyStats`
- `EnemyType`

Stage:

- `StageDefinition`
- `StageState`

Equipment:

- `EquipmentDefinition`
- `EquipmentInstance`
- `EquipmentAffix`
- `EquipmentRarity`
- `EquipmentSlot`

Combat:

- `DamageResult`
- `TurnState`
- `CombatState`

## Requirements

- Use typed GDScript.
- Prefer Godot `Resource` classes for configurable content.
- Avoid complex combat implementation in this phase.

## Acceptance

All core models can be instantiated without runtime errors.

---

# Phase 3 — Grid System

## Goal

Create a reusable grid system.

## Tasks

- Grid coordinates
- Walkable cells
- Occupied cells
- Player position
- Enemy positions
- Cell validation
- Movement range
- Basic pathfinding

Suggested API:

```text
GridMap
├── is_walkable()
├── is_occupied()
├── get_neighbors()
├── get_reachable_cells()
├── find_path()
└── world_to_grid()
```

The grid must not be tightly coupled to Player or Enemy scripts.

## Acceptance

A test scene allows the player to move around a grid.

---

# Phase 4 — Player Controller

## Goal

Create the playable hero.

## Tasks

- Player scene
- Player movement
- Movement points
- Player stats
- Grid position
- Selection feedback

Default:

```text
MovementPoints = 3
```

## Acceptance

Player moves correctly on the grid.

---

# Phase 5 — Turn Manager

## Goal

Implement the basic turn loop.

Flow:

```text
Player Turn
    ↓
Player Action Complete
    ↓
Enemy Turn
    ↓
Enemy Actions Complete
    ↓
Player Turn
```

States:

```text
PLAYER_TURN
ENEMY_TURN
VICTORY
DEFEAT
```

## Acceptance

A player and one enemy can alternate turns without state corruption.

---

# Phase 6 — Enemy System

## Goal

Create basic enemies.

## Tasks

- Enemy scene
- Enemy definition
- Enemy stats
- Enemy HP
- Enemy level
- Enemy movement
- Target selection
- Basic AI

Basic AI:

```text
Find player
    ↓
If attack range:
    Attack
Else:
    Move toward player
```

## Acceptance

Player and enemy can move and interact in the turn loop.

---

# Phase 7 — Combat System

## Goal

Implement the full basic combat loop.

## Tasks

- Attack
- Attack range
- Damage calculation
- Defense
- HP reduction
- Death
- Critical hits
- Damage numbers
- Combat feedback

Initial formula:

```text
BaseDamage = Max(1, Attack - Defense)
```

Initial critical model:

```text
if random() < CriticalChance:
    Damage *= CriticalDamage
```

## Acceptance

The player can defeat enemies and enemies can defeat the player.

---

# Phase 8 — Stage Generation

## Goal

Create procedural sequential stages.

## Tasks

- Stage number
- Stage initialization
- Enemy spawning
- Random enemy positions
- Enemy count
- Enemy level variance
- Stage completion
- Next stage

Enemy level:

```text
StageLevel + Random(-3, +3)
```

Clamp to minimum level 1.

Recommended weighted distribution:

```text
StageLevel       40%
StageLevel -1    15%
StageLevel +1    15%
StageLevel -2    10%
StageLevel +2    10%
StageLevel -3     5%
StageLevel +3     5%
```

## Acceptance

The player can progress from Stage 1 to Stage 2 to Stage 3 and so on.

---

# Phase 9 — Enemy Scaling

## Goal

Implement stage-aware difficulty.

Starting tuning values:

```text
HPGrowthRate      = 1.20
AttackGrowthRate  = 1.16
DefenseGrowthRate = 1.15
GoldGrowthRate    = 1.18
```

Formula:

```text
Value = BaseValue × GrowthRate^(Stage - 1)
```

All values must remain tunable.

## Acceptance

Stage 1 and Stage 20 have clearly different difficulty while remaining numerically stable.

---

# Phase 10 — Boss System

## Goal

Implement guaranteed Mini Boss stages.

Every 10th stage:

```text
10
20
30
40
...
```

## Tasks

- Mini Boss definition
- Boss stats
- Boss AI
- Boss name
- Boss identifier
- Boss-specific behavior

Create at least three distinct MVP boss behaviors:

- AOE
- Summoner
- Enrager

## Acceptance

Stage 10 contains a meaningful Mini Boss encounter that is not just a high-HP normal enemy.

---

# Phase 11 — Special Encounter System

## Goal

Add surprise encounters.

Initial chance:

```text
3%
```

Pity system:

```text
+1% after failure
Reset to 3% after success
Maximum 15%
```

Encounter types:

- Elite
- Treasure Monster
- Special Monster
- Random Mini Boss
- Gold Monster
- Cursed Monster

Random Mini Boss level range:

```text
CurrentStage - 20 .. CurrentStage
```

with an additional low-frequency long-tail range toward earlier stages.

## Acceptance

Special encounters can appear and the pity system works correctly.

---

# Phase 12 — EXP / Level System

## Goal

Add player progression.

Formula:

```text
EXPToNextLevel = 100 × 1.15^(Level - 1)
```

On level up:

```text
+BaseHP
+BaseAttack
+BaseDefense
```

Enemy EXP concept:

```text
EnemyEXP =
BaseEXP
× EnemyLevelMultiplier
× EnemyTypeMultiplier
```

Example:

```text
EnemyLevelMultiplier = 1 + (EnemyLevel - 1) × 0.10
```

## Acceptance

The player gains EXP, levels up, and receives stat growth.

---

# Phase 13 — Gold System

## Goal

Add Gold progression.

Tasks:

- Gold storage
- Enemy rewards
- Boss rewards
- Stage rewards
- UI display

Formula:

```text
Gold = BaseGold × 1.18^(Stage - 1)
```

## Acceptance

Gold is correctly awarded and displayed.

---

# Phase 14 — Equipment Core

## Goal

Implement equipment generation.

Slots:

```text
Weapon
Helmet
Armor
Gloves
Boots
Ring
Amulet
```

Rarity:

```text
Common
Uncommon
Rare
Epic
Legendary
Mythic
```

## Acceptance

Enemies can drop equipment and equipment can be represented as data objects.

---

# Phase 15 — Affix System

## Goal

Implement random equipment attributes.

Initial affixes:

```text
Attack
Defense
HP
CriticalChance
CriticalDamage
Dodge
Movement
AttackRange
LifeSteal
DamageVsElite
DamageVsBoss
```

Affix strength should depend on equipment level, rarity, and affix type.

Use weighted random selection.

## Acceptance

Two items of the same type can meaningfully differ in stats.

---

# Phase 16 — Loot Tables

## Goal

Implement stage-aware loot tables.

Initial normal enemy rarity distribution:

```text
Common     60%
Uncommon   25%
Rare       10%
Epic        4%
Legendary   1%
```

Special enemies and bosses require better loot tables.

Create modular systems such as:

```text
LootTable
LootGenerator
```

Do not put loot-generation logic directly inside enemy scripts.

## Acceptance

Loot varies by enemy type and encounter type.

---

# Phase 17 — Equipment Inventory

## Goal

Create equipment management.

Implement:

- Inventory
- Equipment slots
- Equip
- Unequip
- Item selection
- Item comparison foundation
- Discard
- Sell placeholder if desired

## Acceptance

The player can equip and manage dropped items.

---

# Phase 18 — Equipment Comparison

## Goal

Make loot decisions fast and readable.

Compare:

```text
Current Equipment
vs
New Equipment
```

Show actual deltas:

```text
Attack     +29
HP         -100
Crit       +4%
```

An optional estimated power delta may be shown, but must not replace actual stat comparison.

## Acceptance

A player can quickly understand whether an item is stronger or different.

---

# Phase 19 — Unique Equipment Effects

## Goal

Introduce build-defining item effects.

Initial effects:

- Every 3rd attack deals bonus damage
- Critical attacks heal the player
- Moving before attacking increases damage
- Back attacks deal bonus damage
- Attacking poisoned targets deals bonus damage

Prefer a modular effect architecture.

Suggested base concept:

```text
EquipmentEffect
├── DamageModifierEffect
├── CriticalEffect
├── HealingEffect
├── MovementAttackEffect
└── StatusEffect
```

## Acceptance

At least five unique effects work correctly in combat.

---

# Phase 20 — Auto Combat

## Goal

Allow the player to automate combat and progression.

Implement:

- Auto toggle
- Target selection
- Path selection
- Movement decision
- Attack decision
- Item usage
- Continue to next stage
- Stop on defeat
- Stop when disabled

Priority:

```text
Survival
>
Attack valid target
>
Move toward target
>
Continue progression
```

Auto mode must not permanently stall.

## Acceptance

The game can clear ordinary stages without manual input.

---

# Phase 21 — Loot Presentation

## Goal

Make loot exciting.

Implement:

- Loot drop animation
- Rarity effect
- Item reveal
- Popup
- New best item indicator
- Stronger Legendary effect
- Stronger Mythic effect

Normal loot should be fast.

High rarity loot should have stronger presentation without creating long interruptions.

## Acceptance

Loot feels rewarding before the inventory screen is opened.

---

# Phase 22 — Combat UI

## Goal

Create production-quality combat UI.

Required:

- Stage
- Player HP
- Enemy HP
- Movement Points
- Turn state
- Attack
- Item
- Auto
- Damage numbers
- Critical indicators
- Victory
- Defeat

## Acceptance

The combat loop is understandable without debug-only controls.

---

# Phase 23 — Inventory UI

## Goal

Create the dark fantasy RPG inventory.

Style direction:

- Dark fantasy
- Gothic
- Metallic frame
- Stone texture
- Gold highlights
- Clear rarity presentation

Implement:

- Equipment slots
- Inventory grid
- Item details
- Comparison panel
- Equip button
- Discard button

## Acceptance

Inventory is readable and usable.

---

# Phase 24 — Stage Result UI

## Goal

Make stage completion rewarding.

Display:

```text
LEVEL CLEAR

EXP
Gold
Loot
```

Highlight:

```text
NEW BEST ITEM
```

Provide:

```text
NEXT STAGE
```

## Acceptance

Stage completion communicates progress and rewards clearly.

---

# Phase 25 — Save / Load

## Goal

Persist progression locally.

Persist at least:

- Stage
- Level
- EXP
- Gold
- Equipment
- Inventory
- Settings

Do not implement cloud save during MVP.

## Acceptance

Restarting the game preserves progression.

---

# Phase 26 — Balance Pass

## Goal

Tune the complete loop through representative stages.

Test at minimum:

```text
Stage 1
Stage 5
Stage 10
Stage 20
Stage 30
Stage 50
Stage 100
```

Measure:

- Average combat duration
- Average equipment drops
- Gold income
- EXP progression
- Death rate
- Boss difficulty
- Legendary frequency
- Power increase from upgrades

Adjust only a small group of variables at a time.

Potential tuning targets:

```text
Enemy growth
Player growth
Loot rate
Rarity rate
Affix strength
Gold
EXP
Special encounter rate
Boss difficulty
```

## Acceptance

Progression feels neither permanently blocked nor trivially effortless.

---

# Phase 27 — VFX / Game Feel

## Goal

Improve combat and reward feedback.

Add:

- Hit flash
- Damage numbers
- Critical effects
- Enemy death effects
- Item drop effects
- Level-up effect
- Legendary reveal
- Sound feedback
- Optional limited screen shake

Do not prioritize VFX over a functioning gameplay loop.

## Acceptance

Basic combat and loot have satisfying audiovisual feedback.

---

# Phase 28 — Refactoring

## Goal

Clean the code before significant expansion.

Review:

- Duplicate logic
- Circular dependencies
- Excessive autoload usage
- Hard-coded values
- Large God scripts
- Unnecessary global state
- Unused resources
- Debug code

Refactor only after gameplay is stable.

## Acceptance

Architecture remains understandable for future AI-assisted development.

---

# Phase 29 — MVP Acceptance Test

## Combat

- [ ] Player moves on grid
- [ ] Player attacks
- [ ] Enemy moves
- [ ] Enemy attacks
- [ ] Turn system works
- [ ] Critical damage works
- [ ] Player can die
- [ ] Enemy can die

## Progression

- [ ] Stage increases
- [ ] Enemy scaling works
- [ ] EXP works
- [ ] Player levels up
- [ ] Gold works

## Boss

- [ ] Stage 10 is Mini Boss
- [ ] Stage 20 is Mini Boss
- [ ] Mini Boss has unique behavior
- [ ] Boss drops better loot

## Special Encounters

- [ ] Random special encounter works
- [ ] Pity system works
- [ ] Random Mini Boss works

## Loot

- [ ] Equipment drops
- [ ] Rarity works
- [ ] Affixes work
- [ ] Equipment can be equipped
- [ ] Equipment comparison works
- [ ] Unique effects work

## Auto

- [ ] Auto mode can clear stages
- [ ] Auto mode can attack
- [ ] Auto mode can move
- [ ] Auto mode stops on death

## UI

- [ ] Combat UI works
- [ ] Inventory works
- [ ] Loot popup works
- [ ] Stage result works

## Persistence

- [ ] Save works
- [ ] Load works

---

# Phase 30 — Future Expansion

Only after MVP is stable.

Potential future systems:

```text
Skills
Classes
Talent Tree
Crafting
Sockets
Gems
Set Items
Enchanting
More Bosses
More Enemy Types
More Build Archetypes
Dungeons
Endless Mode
Daily Challenges
Achievements
Quests
Meta Progression
```

Do not implement these before the core loot/combat loop is proven fun.
