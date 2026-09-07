# Game Design Document

## 1. Overview

### Genre

- RPG
- Grid-based
- Turn-based combat
- Loot-focused progression
- Auto-combat / idle-friendly
- Dark fantasy

### Core Fantasy

The player controls a hero progressing through increasingly difficult stages.

The main gameplay fantasy is:

> Fight enemies → receive loot → discover better equipment → become stronger → clear higher stages → encounter stronger enemies and better loot.

The primary source of player excitement should come from:

1. Killing enemies
2. Discovering rare equipment
3. Comparing equipment stats
4. Finding powerful random affixes
5. Discovering special enemies and mini bosses
6. Suddenly becoming much stronger after obtaining a good item
7. Pushing to a higher stage

The game should feel easy to understand but increasingly deep as equipment builds develop.

---

# 2. Core Gameplay Loop

```text
Enter Stage
    ↓
Generate Stage
    ↓
Generate Enemies
    ↓
Player Turn
    ↓
Move + Attack / Skill / Item
    ↓
Enemy Turn
    ↓
Repeat
    ↓
Enemies Defeated
    ↓
Rewards
    ├── EXP
    ├── Gold
    └── Equipment
    ↓
Review / Equip Loot
    ↓
Next Stage
```

The player should always have a clear reason to continue to the next stage.

---

# 3. Combat System

## 3.1 Grid

Combat takes place on a grid.

Each cell represents one movement position.

The first implementation should support:

- Orthogonal movement
- 4-direction movement
- Occupied cells
- Walkable cells
- Enemy cells
- Player cell
- Basic pathfinding

Diagonal movement is not required for the MVP.

## 3.2 Turn Structure

Each player turn consists of:

```text
Movement Phase
+
One Action
```

The player may:

- Move
- Attack
- Use Skill
- Use Item

The intended default behavior is:

```text
Move 0..MovementPoints cells
+
1 Action
```

Example:

```text
Movement Points = 3

Player may:
Move 2 cells
+
Attack
```

or:

```text
Move 3 cells
+
Use Item
```

The player should NOT be forced to choose between movement and action.

## 3.3 Player Movement

Default:

```text
MovementPoints = 3
```

Movement can later be modified by:

- Equipment
- Buffs
- Debuffs
- Skills
- Special effects

Movement should remain predictable and easy to understand.

## 3.4 Attack

A basic attack requires:

- A valid target
- Target inside attack range
- Player has not already consumed the turn action

Default melee attack:

```text
AttackRange = 1
```

Future weapons may modify:

- Attack range
- Area of effect
- Target count
- Damage type
- Special attack behavior

## 3.5 Skills

Skills use the same player-turn action as a basic attack: the player may move
0..MovementPoints cells and then use one skill. The initial skill set is:

```text
Whirlwind       Four orthogonally adjacent cells around the player, 0.8x damage
Arcane Bolt     Single target, two-cell range, 1.0x damage
Execution       Single target, one-cell range, 1.5x damage
```

All skills start at level 0 (unlearned). Each player level-up grants one skill
point. Spending one point learns a skill or raises its level, up to level 5.
Each skill level increases its damage multiplier by 0.1. Whirlwind affects
every living enemy in its four adjacent cells. Arcane Bolt and Execution use
the currently selected enemy as their target. Skills cannot be used while
unlearned or without a valid target, and successful skill use ends the
player's turn.

## 3.6 Damage

Initial base damage:

```text
BaseDamage = AttackerPower - TargetDefense
```

Final base damage must be at least 1.

Conceptually:

```text
FinalDamage =
Max(1, BaseDamage)
× SkillMultiplier
× CriticalMultiplier
× ModifierMultiplier
```

The implementation should avoid unnecessary floating-point complexity.

## 3.7 Critical Hit

Initial default values:

```text
CriticalChance = 5%
CriticalDamage = 150%
```

Critical hits should have:

- Distinct visual effect
- Larger damage number
- Sound effect
- Short hit feedback

Critical hits are one of the main combat excitement sources.

## 3.8 Enemy Turn

Turn flow:

```text
Player Turn
    ↓
Enemy AI
    ↓
Enemy Turn
```

Basic enemy AI:

1. Find player
2. Calculate reachable cells
3. Move toward player
4. Attack if target is in range
5. Otherwise end turn

MVP enemy AI should be deterministic and reliable.

Complex tactical AI is not required initially.

---

# 4. Auto Combat

Auto mode is a major feature.

The player may toggle:

```text
MANUAL
AUTO
```

## Manual

Player controls:

- Movement
- Target selection
- Attack
- Skill
- Item

## Auto

The system automatically:

1. Selects a target
2. Finds a path
3. Moves toward target
4. Attacks when possible
5. Uses configured skills
6. Uses healing items when required
7. Continues until combat ends

Auto mode should prioritize:

```text
Survival
>
Target Selection
>
Damage
>
Movement Efficiency
```

The player should be able to stop auto mode at any time.

Auto mode must never permanently soft-lock combat.

### 4.1 Game Speed

Auto combat provides three selectable pacing modes:

```text
x1       0.40 seconds between automatic decisions
x2       0.20 seconds between automatic decisions
FASTEST  existing rapid test/debug pacing (0.05 seconds)
```

x1 is the default for normal play. Changing the mode immediately updates any
pending automatic decision without resetting the current turn or other combat
state. The setting only affects main-hero auto decisions; it does not change
global engine time or unrelated systems.

## 4.2 Farming Toggle

FARMING (previously labelled AUTO STAGE) controls what happens after a
cleared stage. It is off by default.

```text
FARMING ON   →  stay on the cleared stage and re-spawn its enemies so the
                stage can be fought again (repeat farming)
FARMING OFF  →  advance to the next stage after a clear
```

FARMING applies regardless of the AUTO toggle. When FARMING is ON, defeating
every enemy on the current stage re-spawns that stage's enemies — AUTO keeps
attacking it automatically (idle farming), and manual play continues on the
same stage. No NEXT STAGE prompt appears while FARMING is on.

When FARMING is OFF a cleared stage advances to the next one through the
**Next Stage Point** (exit). The hero must physically stand on the top exit
cell before the stage can advance:

```text
FARMING OFF + MANUAL  →  after a clear the hero free-roams; the NEXT STAGE
                        button (to the right of END TURN) stays disabled until
                        the hero stands on the exit cell, then it may be pressed
                        (SPACE works the same way)
FARMING OFF + AUTO    →  after a clear the AUTO controller walks the hero to
                        the exit cell and auto-starts the next stage when the
                        hero reaches it
FARMING ON + AUTO     →  the stage re-spawns as usual; standing on the exit
                        cell does nothing
```

---

# 5. Stage System

The game is divided into sequential stages.

```text
Stage 1
Stage 2
Stage 3
...
Stage 10
Stage 11
...
```

Stages increase in difficulty.

## 5.1 Hybrid Level Data

The playable stage pipeline resolves a level through `LevelManager` and
`LevelProvider`, then passes the resulting `StageDefinition` to
`StageManager`:

```text
LevelManager → LevelProvider → StageDefinition → StageManager → Battle
```

`StageEnemyEntry` references an existing `EnemyData` and stores only stage
composition data such as count, level offset, spawn rule, and optional stat
overrides. Fixed levels are authored as `LevelConfig` resources under
`resources/levels/`. Levels without a fixed resource are generated from a
`LevelTemplate` using the level ID as the procedural seed. Both paths return
the same `StageDefinition` shape.

### Stage Arena Points

Every combat arena uses the same grid layout with two fixed gate cells in a
configured lane column (default `x = 3`, the 4th column from the left):

- **Stage Starting Point** — bottom row (`y = grid_height - 1`). The hero is
  teleported here whenever a **new** stage number is generated (first boot,
  advancing, or a defeat retreat to the previous stage). FARMING re-spawn of
  the *same* stage number does not move the hero.
- **Next Stage Point** (exit) — top row (`y = 0`). The hero must stand on this
  cell to advance (see §4.2).

Both cells are derived from `StageManager.stage_gate_column` and the grid size.
Enemies never spawn on the Starting Point (it is occupied by the hero), and any
enemy sitting on the exit cell is gone once the stage is fully cleared, so the
exit is always reachable after victory.

## 5.2 Normal Stage

Most stages contain:

- Randomized enemies
- Random enemy positions
- Random enemy composition

Enemy level:

```text
EnemyLevel = StageLevel + Random(-3, +3)
```

Enemy level must not fall below 1.

Example:

```text
Stage = 20

Possible enemy levels:
17
18
19
20
21
22
23
```

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

This keeps most enemies close to the intended stage difficulty.

---

# 6. Mini Boss Stages

Every 10th stage contains a guaranteed Mini Boss.

```text
10
20
30
40
50
...
```

Mini Boss stages should:

- Have stronger enemies
- Have a named Mini Boss
- Use a unique encounter configuration
- Guarantee high-value loot

Mini Boss encounters should not feel like normal enemies with more HP.

Each Mini Boss should have at least one special mechanic.

Examples:

- Area attack
- Summon minions
- Enrage
- High mobility
- Poison
- Reduced damage from frontal attacks
- Counter attack

---

# 7. Special Encounters

After each stage there is a low chance of a special encounter.

Possible encounters:

- Special Monster
- Elite Monster
- Treasure Monster
- Rare Monster
- Random Mini Boss
- Gold Monster
- Cursed Monster

Default special encounter chance:

```text
3%
```

Use bad-luck protection.

After each unsuccessful roll:

```text
SpecialChance += 1%
```

After a special encounter occurs:

```text
SpecialChance = 3%
```

Recommended cap:

```text
MaxSpecialChance = 15%
```

## 7.1 Random Mini Boss

A random Mini Boss may appear on any non-guaranteed stage.

The random Mini Boss level may range from:

```text
Minimum unlocked stage
        ↓
Current stage
```

Example:

```text
Current Stage = 100

Random Mini Boss Level:
1..100
```

The probability distribution should favor enemies closer to the current stage while still allowing older boss types to appear.

Recommended:

```text
80%:
CurrentStage - 20 .. CurrentStage

20%:
1 .. CurrentStage - 21
```

Clamp to valid stage range.

## 7.2 High-Value Loot

Special Monsters and Mini Bosses should provide significantly better loot opportunities.

Mini Boss:

```text
Guaranteed:
High-quality equipment
```

Recommended minimum rarity:

```text
Rare+
```

A special Mini Boss may use:

```text
Epic+
```

Legendary should remain uncommon.

Do not guarantee Legendary on every Mini Boss.

---

# 8. Enemy Scaling

Enemy HP should scale exponentially with stage.

The design philosophy borrows from Clicker Heroes: continuously compounding growth creates progression walls and power spikes. The exact formula is intentionally customized for this game.

Recommended initial formula:

```text
EnemyHP(stage, enemyBaseHP) =
enemyBaseHP × HPGrowthRate^(stage - 1)
```

Initial target:

```text
HPGrowthRate = 1.20
```

This value is configurable.

Recommended starting values:

```text
HP Growth       = 1.20
Attack Growth   = 1.16
Defense Growth  = 1.15
```

These are tuning values, not permanent constants.

---

# 9. Player Progression

Player power comes primarily from:

1. Equipment
2. Level
3. Permanent progression

Equipment should be the most exciting source of power.

Player power should NOT increase at exactly the same rate as enemy power.

Intended pattern:

```text
Enemy gradually becomes stronger
        ↓
Player struggles
        ↓
New equipment
        ↓
Large power increase
        ↓
Player temporarily overpowers enemies
        ↓
New difficulty wall
        ↓
Repeat
```

A good item should be capable of noticeably changing progression speed.

---

# 10. Player Stats

MVP stats:

```text
Level
EXP
HP
Attack
Defense
Critical Chance
Critical Damage
Movement
Attack Range
Dodge
Life Steal
```

Possible future stats:

```text
Attack Speed
Armor Penetration
Elemental Damage
Damage vs Elite
Damage vs Boss
Healing Received
Status Effect Chance
Status Effect Duration
```

Do not implement all future stats during MVP.

---

# 11. Experience

Experience is rewarded from enemies.

Recommended concept:

```text
EnemyEXP =
BaseEXP
× EnemyLevelMultiplier
× EnemyTypeMultiplier
```

Example:

```text
EnemyLevelMultiplier =
1 + (EnemyLevel - 1) × 0.10
```

Bosses and special enemies should have substantially higher EXP rewards.

## 11.1 Player Level Formula

Recommended initial level requirement:

```text
EXPToNextLevel =
100 × 1.15^(Level - 1)
```

Player level should provide moderate power growth.

On level up:

```text
+BaseHP
+BaseAttack
+BaseDefense
```

Equipment should remain the most exciting source of power.

---

# 12. Gold

Gold is a secondary progression currency.

Gold can be earned from:

- Normal enemies
- Elite enemies
- Special enemies
- Mini Bosses

Recommended scaling:

```text
Gold =
BaseGold × 1.18^(Stage - 1)
```

The first MVP may only display and collect Gold.

---

# 13. Equipment System

Equipment is the primary reward system.

MVP equipment slots:

```text
Weapon
Helmet
Armor
Gloves
Boots
Ring
Amulet
```

---

# 14. Equipment Rarity

Initial rarity tiers:

```text
Common
Uncommon
Rare
Epic
Legendary
Mythic
```

Rarity affects:

- Number of affixes
- Affix strength
- Chance of special effects
- Visual appearance
- Equipment score

---

# 15. Equipment Affixes

Initial affixes:

```text
Attack
Defense
HP
Critical Chance
Critical Damage
Dodge
Movement
Attack Range
Life Steal
Damage vs Elite
Damage vs Boss
```

Affix strength depends on:

```text
EquipmentLevel
EquipmentRarity
AffixType
```

Use weighted random generation.

Avoid completely uncontrolled random values that produce impossible or consistently useless items.

---

# 16. Equipment Affix Count

Suggested starting model:

```text
Common:
1 affix

Uncommon:
2 affixes

Rare:
3 affixes

Epic:
4 affixes

Legendary:
5 affixes
+
chance of unique effect

Mythic:
5+ affixes
+
guaranteed unique effect
```

Exact values can be tuned through playtesting.

---

# 17. Unique Equipment Effects

Some high-rarity equipment can contain unique effects.

Initial examples:

```text
Every 3rd attack deals +100% damage.
```

```text
Critical attacks restore 5% HP.
```

```text
Moving at least 2 cells before attacking increases damage by 75%.
```

```text
Attacking from behind deals +100% damage.
```

```text
Attacking a poisoned enemy deals +50% damage.
```

Unique effects should interact with grid and turn-based combat.

---

# 18. Build Archetypes

The equipment system should gradually support different builds.

Example builds:

## Berserker

Focus:

```text
High Attack
High Critical Damage
```

## Assassin

Focus:

```text
Critical Chance
Dodge
Movement
Back Attack
```

## Vampire

Focus:

```text
Life Steal
HP
Critical
Melee
```

## Poison

Focus:

```text
Poison
Damage over Time
Movement
Kiting
```

## Ranged

Focus:

```text
Attack Range
Projectile Damage
Movement
```

Builds should emerge naturally from equipment rather than being locked to a rigid class system in the MVP.

---

# 19. Loot Generation

Normal enemies should have a chance to drop equipment.

Initial conceptual distribution:

```text
Common     60%
Uncommon   25%
Rare       10%
Epic        4%
Legendary   1%
```

These values are starting values and must be tuned through playtesting.

Special enemies and Mini Bosses should use significantly better loot tables.

Loot chance may depend on:

```text
EnemyType
EnemyLevel
Stage
Boss status
Special encounter
```

---

# 20. Loot Philosophy

The game should contain both:

```text
Frequent small rewards
```

and:

```text
Rare exciting rewards
```

Normal combat:

```text
Gold
EXP
Common/Uncommon equipment
```

Elite:

```text
Uncommon/Rare
```

Special:

```text
Rare/Epic
```

Mini Boss:

```text
Rare+
```

Legendary should remain rare enough to create excitement.

---

# 21. Equipment Comparison

When an item drops, the UI should immediately compare it against the currently equipped item.

Example:

```text
Epic Sword

Attack      154   ▲29
Crit         12%  ▲4%

Overall Power:
+14.7%
```

Possible actions:

```text
Equip
Keep
Sell
Discard
```

The comparison UI must be easy to understand.

Do not rely solely on an overall power score; show actual stat differences.

---

# 22. Loot Presentation

Loot should not instantly disappear into inventory.

Flow:

```text
Enemy Dies
    ↓
Item Drops
    ↓
Glow / Animation
    ↓
Rarity Reveal
    ↓
Stats Display
    ↓
Comparison
```

Legendary and Mythic items should have stronger presentation through:

- Glow
- Particle
- Sound
- Screen feedback
- Special item frame
- Item reveal animation

Loot presentation is part of the gameplay loop.

---

# 23. Stage Rewards

At stage completion:

```text
EXP
Gold
Equipment
```

Display a summary:

```text
LEVEL CLEAR

Gold      +12,540
EXP       +2,314

Loot:
Rare Sword
Epic Armor
Legendary Ring
```

Highlight:

```text
NEW BEST ITEM
```

when appropriate.

---

# 24. Death

If the player dies:

```text
Defeat
```

The game should allow an MVP-friendly retry flow.

On defeat the player retreats to the previous stage. If AUTO combat was enabled
before the defeat, it stays enabled and resumes automatically on that stage.

Avoid heavy punishment until the core game loop is proven fun.

---

# 25. Difficulty Philosophy

The intended rhythm is:

```text
Easy Progression
    ↓
Increasing Challenge
    ↓
Difficulty Wall
    ↓
Loot Upgrade
    ↓
Power Spike
    ↓
Fast Progression
    ↓
New Difficulty Wall
```

The player should not feel permanently stuck.

---

# 26. Visual Direction

## Overall Style

Dark fantasy / Gothic ARPG.

The UI may take high-level inspiration from dark fantasy action RPG inventory design, but must not directly copy copyrighted artwork or proprietary UI assets.

Target qualities:

- Dark
- Heavy
- Medieval
- Metallic
- Gothic
- High contrast
- Premium-looking
- Strong rarity presentation

## UI Direction

Use:

- Dark stone / metal frames
- Gold accents
- Dark backgrounds
- Heavy fantasy typography
- Strong rarity hierarchy
- Clear readable icons

Suggested hierarchy:

```text
HP / Resource
Stage
Combat Area
Enemy Information
Action Buttons
Equipment
Loot
Auto Mode
```

The UI must remain readable on small displays.

---

# 27. Combat UI

Required:

```text
Player HP
Enemy HP
Stage
Current Turn
Movement Points
Action availability
Attack button
Item button
Auto button
```

Optional future:

```text
Buffs
Debuffs
Cooldowns
Combat log
```

---

# 28. Damage Feedback

Damage numbers should communicate:

```text
Normal Damage
Critical Damage
Healing
Poison Damage
```

Critical damage should visually stand out from normal damage.

---

# 29. Randomness Philosophy

Randomness should create excitement, not frustration.

Use:

- Weighted random
- Controlled rarity distribution
- Bad-luck protection
- Stage-aware loot
- Enemy level variance
- Special encounter chance

Avoid completely uncontrolled RNG.

---

# 30. MVP Scope

The first playable version should contain only:

## Combat

- Grid
- Player movement
- Enemy movement
- Turn system
- Basic attack
- Damage
- HP
- Death

## Progression

- Stage number
- Stage scaling
- Enemy levels
- Mini Boss every 10 stages
- Special encounter chance

## Loot

- Equipment
- Rarity
- Random affixes
- Equipment slots
- Equipment comparison
- Equip / discard

## Progression Rewards

- EXP
- Level
- Gold

## Auto

- Auto movement
- Auto targeting
- Auto attack
- Auto continue

## UI

- Combat UI
- Inventory
- Equipment comparison
- Loot popup
- Stage result
- Dark fantasy visual direction

---

# 31. Non-MVP Features

Do not implement initially:

- PvP
- Multiplayer
- Guild
- Trading
- Complex crafting
- Socket system
- Gems
- Set equipment
- Massive skill tree
- Multiple currencies
- Complex quest system
- Multiple playable characters
- Complex online account system

These may be added after the core loop is proven fun.

---

# 32. Design Priorities

Priority order:

1. Combat feels responsive
2. Loot is exciting
3. Equipment comparison is easy
4. Character becomes visibly stronger
5. Stage progression feels rewarding
6. Special encounters feel surprising
7. Auto mode works reliably
8. Build diversity develops naturally
9. UI looks premium
10. Advanced systems come later

---

# 33. Golden Rule

The game should create the feeling:

> "I will play one more stage because there might be a better item."

The repeating loop is:

```text
Fight
→ Drop
→ Inspect
→ Upgrade
→ Power Spike
→ Next Stage
```

This loop is more important than secondary systems.

# Platform & Screen Layout

## Primary Platform

The game is designed primarily for **mobile devices in portrait orientation**.

### Platform Priority

1. Mobile Portrait — **Primary**
2. Tablet Portrait — Secondary
3. Desktop — Development / Debugging only

Desktop landscape is **not** the primary target and must not drive UI or gameplay layout decisions.

## Orientation

* Default orientation: **Portrait**
* Primary aspect ratio: **9:16**
* Must also support common modern mobile ratios such as:

    * 9:19.5
    * 9:20
    * 9:21
* Never assume a fixed physical screen resolution.
* UI must adapt to different portrait resolutions and aspect ratios.

## Godot Configuration

Godot project settings must use portrait-oriented display settings.

The project should be configured so that running the game starts in a portrait window.

Do not change the project to landscape orientation unless explicitly requested.

## UI Design Rules

All UI must be designed for a portrait mobile screen.

### Layout

* Use responsive Godot Containers where appropriate.
* Avoid hard-coded absolute positions for important UI elements.
* Keep critical controls within comfortable thumb-reach areas.
* Do not place important information only at the extreme top or bottom edges.
* Respect mobile safe areas and screen cutouts where applicable.
* UI must remain usable on narrow portrait screens.

### Interaction

The primary interaction model is:

* Touch
* Tap
* Drag where required
* Short touch interactions

Mouse and keyboard input may be supported for development/debugging, but must not determine the primary interaction design.

## Gameplay Layout

Gameplay must be designed around the portrait viewport.

For the grid-based turn-based RPG:

* The gameplay grid must remain clearly visible in portrait mode.
* Combat UI must not require landscape orientation.
* Player/enemy information should be readable without covering the main gameplay area.
* Action buttons should be positioned for comfortable mobile touch interaction.
* Important combat actions should remain accessible without excessive scrolling.

## Responsive Layout Requirements

When implementing a new screen, scene, HUD, menu, popup, or gameplay UI, the Agent must consider:

1. Portrait viewport size.
2. Different mobile aspect ratios.
3. Touch target size.
4. Safe areas.
5. UI readability.
6. Available gameplay area.

Do not optimize a screen for desktop first and then attempt to squeeze it into portrait mode.

The implementation should be **mobile-first and portrait-first**.

## Development Rule

When implementing or modifying UI:

> **Always treat Mobile Portrait as the source of truth.**

If a design works on desktop but does not work well on a portrait mobile screen, the implementation is considered incorrect.

Desktop support is only for development convenience and must not compromise the mobile portrait experience.

## Agent Acceptance Criteria

Before considering a UI-related task complete, verify:

* [ ] Desktop testing does not replace mobile portrait testing.
* [ ] Game runs in portrait orientation.
* [ ] UI is usable at 9:16.
* [ ] UI does not break on taller portrait screens.
* [ ] No important UI element is clipped.
* [ ] Touch targets are large enough for mobile interaction.
* [ ] Gameplay remains clearly visible.
* [ ] No landscape-only assumption exists in the implementation.
