# Game Design Document

What the game is, how it should feel, and which decisions drive it.

## Companion Documents

- `docs/gameplay-spec.md` — exact mechanical rules, formulas and tuning values.
- `docs/implementation-status.md` — what the current build actually does, and where it
  deviates from this design.

**Authority:** this document defines **intent**, the spec defines **exact rules**, and the
implementation document records **current code truth**. When they disagree, the gap list
in `implementation-status.md` is the work queue — not a reason to change this design.

---

# 1. Game Overview

## Genre

- RPG
- Grid-based, turn-based combat
- Loot-driven progression
- Auto-combat
- Idle / Farming
- Dark Fantasy

## Platform

- Primary: mobile, portrait, designed around 9:16
- Supports other portrait mobile ratios and tablets
- Desktop is primarily for development / testing

---

# 2. Core Gameplay Loop

```text
Manual Combat
    ↓
Loot
    ↓
Build / Upgrade
    ↓
Push Higher Stages
    ↓
Develop Sub Heroes
    ↓
Automate Previously Cleared Content
    ↓
Farm Resources
    ↓
Improve Builds
    ↓
Push Further
```

Ultimate progression:

```text
Manual Play → AUTO → Autonomous Idle
```

The Main Player handles new and difficult content. Developed Sub Heroes eventually
automate content the player has already mastered.

Core player fantasy:

> The Main Player pushes into new territory while developed Sub Heroes farm territory
> the player has already conquered.

The intended feeling:

> The content I once struggled with can now run itself, allowing my Main Player to push
> even further.

---

# 3. Design Pillars

## 3.1 Equipment-Driven Progression

Equipment is the primary long-term source of combat power. Players make decisions based
on stats, affixes, rarity, unique effects, build synergy, and Main Player vs Sub Hero
requirements. A single Power Score must not determine equipment value.

## 3.2 Main Player

The Main Player is the primary active character, responsible for manual combat, new
content, stage pushing, bosses and Mini Bosses, build experimentation, and tactical
decisions.

## 3.3 Sub Heroes

Sub Heroes are secondary characters providing additional combat power, support,
long-term progression and autonomous farming. A developed DPS Sub Hero can eventually
farm previously conquered content independently.

## 3.4 Manual vs Automation

```text
Manual → AUTO → Sub Hero Idle
```

- **Manual:** highest player control and tactical value.
- **AUTO:** removes repetitive input while the Main Player still participates.
- **Idle:** Sub Heroes independently handle repetitive content.

Automation reduces repetitive work without replacing the value of active progression.

## 3.5 Loot

Loot stays a major source of excitement: better equipment, higher rarity, interesting
affixes, unique effects, and build-changing combinations.

---

# 4. World & Stage Structure

## 4.1 Global Stage Progression

One global stage number. Numbers never reset between regions.

```text
Forest: Stage 1–10
Next Region: Stage 11+
Later Regions: continue global numbering
```

## 4.2 Stage Types

| Type | Purpose |
|---|---|
| Combat | Main gameplay: enter an arena, defeat enemies, reach the exit |
| Town | Safe management area: equipment, storage, skills, Sub Heroes, other progression |
| Boss | Powerful boss encounter: higher difficulty, stronger rewards, unique mechanics |

## 4.3 Stage States

World map stages are Locked, Ready, Current or Completed. The map communicates
progression and navigation.

---

# 5. Combat System

## 5.1 Grid

**11 × 7 grid**, `X: 0–10`, `Y: 0–6`. Movement is up / down / left / right only —
diagonal movement is not allowed. Distance uses Manhattan distance.

## 5.2 Stage Positions

```text
Main Player start:  X = 0,  Y = 3
Normal exit:        X = 10, Y = 3
```

## 5.3 Turn System

```text
Player Turn → Enemy Turn → Player Turn → ...
```

A player turn provides **3 Movement Points + 1 Action**. Actions are Attack, Skill or
Item. Movement never consumes the Action.

## 5.4 Movement

The Main Player cannot move through enemies or blocked / occupied cells. Two modes:

- **Destination movement** — select a reachable destination; the shortest valid path
  within available Movement Points is used.
- **Direct movement** — one cell at a time via directional controls, for precise
  positioning.

## 5.5 Basic Attack

Default range: **1 cell**. An enemy outside range may still be selected; selecting an
unreachable enemy does not consume the Action.

## 5.6 Damage

```text
Max(1, Attack - Defense)
```

Skills and modifiers multiply the resulting damage.

## 5.7 Critical Hits

```text
Critical Chance: 5%
Critical Damage: 150%
```

Critical hits need stronger visual and audio feedback.

---

# 6. Skills

Each skill has a range, an area, a damage multiplier, a possible special behavior, and a
skill level.

```text
Level 0 = Unlearned
Maximum Level = 5
```

Each Main Player level-up grants **1 Skill Point**. Each skill level adds **+0.1** to the
damage multiplier.

| Skill | Targeting | Range | Base multiplier |
|---|---|---|---|
| Whirlwind | Area: four orthogonally adjacent cells | 1 | 0.8× |
| Arcane Bolt | Single target | 2 | 1.0× |
| Execution | Single target | 1 | 1.5× |

---

# 7. Enemy System

## 7.1 Enemy AI

Predictable and reliable beats clever:

```text
1. Find Main Player
2. Determine reachable cells
3. Move toward Main Player
4. Attack if in range
5. End Turn
```

Complexity must not come at the expense of reliability.

## 7.2 Enemy Design

Variety comes from HP, attack, defense, movement, range, skills and special mechanics.
Higher stages introduce mechanics, not only larger stats.

## 7.3 Enemy Scaling

```text
HP      ×1.20 per stage
Attack  ×1.16 per stage
Defense ×1.15 per stage
Gold    ×1.18 per stage
```

Individual enemy stats may vary approximately **±15 %**.

## 7.4 Enemy Levels

```text
Current stage: 40%
±1 stage:      15%
±2 stages:     10%
±3 stages:      5%
```

## 7.5 Enemy Count

Early stages hold 1 enemy; later stages add more, up to **4** in a normal encounter.
Count must stay readable on the portrait battlefield.

## 7.6 Mini Bosses

Every 10th stage contains a guaranteed Mini Boss that introduces mechanics rather than
larger numbers — for example Area Attacker, Summoner, Enrager.

## 7.7 Special Encounters

```text
Base chance:      3%
After a failure:  +1%
Maximum:          15%
```

Special encounters create unusual situations and different / better rewards.

---

# 8. Player Progression

Main Player progression: Level, EXP, Equipment, Skills, Affixes, Unique effects.
Equipment remains the primary long-term power source.

## 8.1 Character Level

Core stats: HP, Attack, Defense, Movement, Attack Range, Critical Chance, Critical
Damage, Dodge, Life Steal.

Level-up provides an HP increase, an Attack increase, a Defense increase, and a Skill
Point.

## 8.2 EXP

```text
EXP requirement: 100 × 1.15^(Level - 1)

EnemyEXP = BaseEXP
         × EnemyLevelMultiplier
         × EnemyTypeMultiplier
         × 1.15^(Stage - 1)
```

**EXP rewards grow with stage and enemy level.** Player levelling must not stall while
enemy power keeps compounding.

---

# 9. Equipment & Loot

## 9.1 Slots

Weapon, Helmet, Armor, Gloves, Boots, Ring, Amulet.

## 9.2 Rarity

Common, Uncommon, Rare, Epic, Legendary, Mythic.

Normal drop weights:

```text
Common     60%
Uncommon   25%
Rare       10%
Epic        4%
Legendary   1%
Mythic      special sources only
```

Higher rarity means stronger stat potential and better build opportunities.

## 9.3 Affixes

Attack, Defense, HP, Critical Chance, Critical Damage, Movement, Attack Range, Dodge,
Life Steal, Damage against Elite, Damage against Boss.

## 9.4 Unique Effects

| Effect | Behavior |
|---|---|
| Combo | Every third attack deals increased damage |
| Critical Heal | Critical attacks restore HP |
| Momentum | Moving at least two cells before attacking increases damage |
| Back Attack | Attacking from behind increases damage |
| Poison Execution | Attacking poisoned enemies increases damage |

Unique effects exist to enable different builds.

## 9.5 Loot Rewards

Combat may reward equipment, EXP, gold and potions. Target equipment drop rates:

```text
Normal Enemy:       25%
Elite:              50%
Special Encounter:  75%
Mini Boss:         100%
```

A successful equipment roll may instead produce a consumable such as a potion.

## 9.6 Loot Presentation

Item information shown: name, slot, rarity, main stats, affixes, unique effects, and a
comparison with the equipped item. Actions: Equip, Keep, Sell, Discard.

Comparison must not rely exclusively on Power Score.

## 9.7 Inventory

The player has equipment slots, a limited inventory, and long-term storage. Storage is
for rare equipment, build-specific equipment, future-use equipment and unusual items.

---

# 10. Sub Heroes

Sub Heroes are secondary combat characters operating automatically during combat and are
never directly controlled. Up to **3** Sub Heroes.

| Role | Purpose |
|---|---|
| DPS | Damage, faster farming, long-term autonomous combat |
| Assist | Buffs the Main Player, utility, support builds |

## 10.1 Progression

Sub Heroes have quality, level, combat power, attack behavior, equipment / build
potential, and idle capability.

```text
Common:     70%
Rare:       25%
Legendary:   5%
```

Duplicates contribute to progression — for example **3 duplicate copies → +1 Level**.

## 10.2 DPS Sub Hero Philosophy

A DPS Sub Hero requires meaningful investment (equipment, levels, build optimization,
progression) before becoming a reliable autonomous fighter. The reward is autonomous
farming capability.

---

# 11. Automation: AUTO / Farming / Idle

## 11.1 AUTO

AUTO controls the Main Player automatically: target selection, pathfinding, movement,
attack, skill usage, healing item usage.

```text
Priority
1. Survival
2. Target selection
3. Damage
4. Movement efficiency
```

AUTO provides convenience without always outperforming a skilled player.

Target speeds, **x1 default**:

```text
x1:       0.40s
x2:       0.20s
FASTEST:  0.05s
```

Speed affects Main Player AUTO decision timing.

## 11.2 Farming Mode

FARMING and AUTO are separate toggles:

- **FARMING ON** — stay on the cleared stage, respawn its enemies and repeat farming,
  with or without AUTO.
- **FARMING OFF + AUTO** — walk to the exit and advance to the next stage.
- **FARMING OFF + manual** — the player walks to the exit and advances.

Farming is how a conquered stage is converted into repeatable income.

## 11.3 Replay

Previously completed stages can be replayed for rewards. If the next stage is already
completed, the player may leave through the exit even while enemies remain. Old content
must not become unnecessarily tedious.

## 11.4 Defeat

When the Main Player is defeated, the player retreats according to progression rules,
long-term progression is preserved, and play can continue.

---

# 12. Idle & Farming Evaluation

## 12.1 Idle Power

Idle Power is an internal / explanatory metric for a Sub Hero's autonomous combat
strength, based on DPS, survivability, sustain, automation efficiency and build quality.

```text
Sub Hero Build
    ↓
DPS / Survivability / Sustain / Automation Efficiency
    ↓
Idle Power
    ↓
Stage Evaluation
    ↓
Idle Capability
```

Idle Power does **not** directly equal a stage number.

## 12.2 Idle Capability

Idle Capability is evaluated against specific stage conditions, producing two results:

- **Stable Farming Stage** — the highest stage the Sub Hero repeatedly clears with high
  reliability.
- **Maximum Push Stage** — the highest stage it can potentially defeat, with lower
  success rate, longer combat, lower efficiency and higher failure risk.

```text
Stable Farming Stage ≤ Maximum Push Stage
```

## 12.3 Farming Efficiency

Farming quality considers success rate, battle duration, recovery time, resource
consumption, reward value, and battles completed over time.

```text
Farming Efficiency = Success Rate × Reward / Time
```

The highest stage is not necessarily the best farming stage.

## 12.4 Recommended Farming Stage

The recommendation depends on the current farming objective — EXP, gold, equipment or
other resources — so it does not necessarily equal the highest Stable Farming Stage.

## 12.5 Idle AI

Automation capability improves through AI tiers:

| Tier | Capability |
|---|---|
| 1 | Basic attack + target selection |
| 2 | Active skill usage + basic rotation |
| 3 | Improved rotation, target selection, basic adaptation |
| 4 | Resource management, automatic healing, advanced decisions |
| 5 | Complete Idle AI: efficient rotation, enemy-aware decisions |

AI Tier is one component of Idle Power and must not completely determine Idle Capability.

---

# 13. Town, Gold & Persistent Progression

## 13.1 Town

Town is a safe management area for equipment, storage, skills, Sub Heroes and other
progression systems.

## 13.2 Gold

Gold is a progression currency used for Sub Hero summons, Sub Hero progression, town
services and other progression systems.

## 13.3 Persistent Progression

These persist between sessions: Main Player level, EXP, gold, skills, equipment,
inventory, storage, Sub Heroes, Sub Hero progression, stage progression, important
unlocks.

**Long-term character development must never be reset by a normal session restart.**

---

# 14. Build, Difficulty & Mobile Direction

## 14.1 Build Philosophy

Multiple viable builds should exist:

| Build | Focus |
|---|---|
| Critical | Critical Chance, Critical Damage, single-target damage |
| Mobility | Movement, positioning, Momentum |
| Sustain | HP, Defense, Life Steal, healing |
| Range | Attack Range, ranged skills, position control |
| Execution | Single-target damage, Elite/Boss damage, finishing weakened enemies |
| Idle Sustain | Survivability, sustain, automation reliability, farming stability |

Idle optimization must not simply mean maximizing DPS.

## 14.2 Difficulty

Difficulty increases through enemy stats, count, variety and mechanics, elites, Mini
Bosses, bosses and stage composition. Avoid relying exclusively on stat inflation.

Desired player reaction:

> I need a better build or better strategy.

## 14.3 Player Decisions

Attack or reposition? Basic attack or skill? Which enemy to kill first? Move closer or
stay safe? Which equipment to use? Keep or discard unusual equipment? Push or farm?
Invest in the Main Player or in a Sub Hero? Optimize DPS or stability? Which stage gives
the best farming efficiency?

## 14.4 Mobile UX

Prioritize large touch targets, clear enemy selection, clear reachable cells, simple
skill buttons, readable damage numbers, strong combat feedback, minimal unnecessary text,
clear stage progression, and clear AUTO / Farming / Idle status.

## 14.5 Visual Direction

**Dark Fantasy + Pixel Art**: gothic / medieval, strong silhouettes, high contrast,
dramatic lighting, pixel-art characters, environments and combat effects, strong rarity
presentation. All UI and assets must feel visually consistent.

---

# 15. Priority & Design Red Lines

## 15.1 Feature Priority

**Tier 1 — Core Gameplay:** grid combat, Main Player, equipment, loot, stage progression,
enemy variety, skills.

**Tier 2 — Long-Term Progression:** Sub Heroes, AUTO, farming, idle capability, Mini
Bosses, world map, town.

**Tier 3 — Expansion:** more builds, regions, bosses, unique effects, stage events,
idle-specific progression.

New features must reinforce Tier 1.

## 15.2 Design Red Lines

1. Equipment is the primary long-term progression system.
2. The Main Player remains the primary active character.
3. Grid-based turn-based combat remains the core gameplay.
4. Manual gameplay remains meaningful.
5. AUTO reduces repetitive input but does not replace the Main Player.
6. Sub Heroes provide secondary power and autonomous progression.
7. DPS Sub Heroes can eventually become independent farming units.
8. Idle Power does not directly equal a stage number.
9. Stable Farming and Maximum Push are the important player-facing results, not Idle
   Power.
10. Idle evaluation considers DPS, survivability, sustain and automation efficiency.
11. Farming should be stable and efficient.
12. Stage pushing should provide progression and discovery.
13. Long-term progression persists.
14. Higher stages introduce gameplay challenges, not only larger numbers.
15. New systems must reinforce the core gameplay loop.
