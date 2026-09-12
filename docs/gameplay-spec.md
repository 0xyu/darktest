# Gameplay Specification

Exact mechanical rules, formulas and tuning values. This is the implementation contract
for `docs/game-design.md`.

**Scope:** rules and numbers only. What the current build actually does — and every place
it differs from this spec — lives in `docs/implementation-status.md`.

**Tuning values** are marked `tunable`: they are balance knobs, not design law. Changing
one is a data change, not a design change.

---

## 1. Combat Grid

| Rule | Value |
|---|---|
| Grid size | **11 columns × 7 rows** (`x = 0..10`, `y = 0..6`) |
| Movement directions | Orthogonal only (up / right / down / left) |
| Diagonal movement | Not allowed |
| Distance metric | Manhattan distance `abs(dx) + abs(dy)` |
| Player start cell | `(0, 3)` — **Stage Starting Point** |
| Exit cell | `(10, 3)` — **Next Stage Point** |

- Both gate cells sit on the gate row (`y = 3`); the row is tunable.
- The Main Player is placed on the Starting Point whenever a **new stage number** is
  generated (boot, advance, defeat retreat). Respawning the same stage does not move it.
- Enemies never spawn on the Starting Point.
- After a clear, the exit is always reachable.

## 2. Turn System

```text
Player turn = move 0..MovementPoints cells + exactly one Action
```

| Rule | Value |
|---|---|
| Movement points per turn | **3** (tunable) |
| Cost per cell | 1 movement point |
| Action | Attack, Skill, or Item — exactly one per turn |
| Movement consumes the Action? | No |
| Does the Action end the turn? | **Yes**, immediately (enemy phase starts) |
| Move after acting? | Not possible |
| Passing | `END TURN` ends the turn without acting |
| After a stage clear | Free movement: unlimited cells, no point cost, until the player advances |

## 3. Movement

- Blocked cells: enemies, occupied cells, non-walkable cells.
- **Destination movement:** the player selects a reachable cell; the hero walks the
  shortest valid path, one movement point per cell. A cell outside the current movement
  range is not a legal destination.
- **Direct movement:** the directional pad steps one cell at a time.
- Movement points are modified by the `movement` affix (tunable per item).

## 4. Attack & Targeting

| Rule | Value |
|---|---|
| Basic attack range | **1** cell (tunable per item) |
| Valid target | Living enemy within Manhattan distance ≤ attack range |
| Selecting an out-of-range enemy | Selection only — the Action is **not** consumed |
| Failed skill use (unlearned / out of range / no target) | Action is **not** consumed |
| Attack against nothing in range | Must not silently consume the Action (see §15 open questions) |

## 5. Damage & Critical Hits

```text
raw      = max(1, attacker.attack - target.defense)
modified = raw × skill_multiplier × modifier_multiplier
final    = max(1, round(modified))
critical = max(1, round(modified × critical_damage))
```

| Rule | Value |
|---|---|
| Multiplier order | Applied **after** defense subtraction |
| Minimum damage | 1 |
| Critical chance (default) | **5 %** (tunable) |
| Critical damage (default) | **150 %** (tunable) |
| Who can crit | Main Player only |
| Enemy critical hits | Never |

## 6. Skills

| Skill | Targeting | Range | Multiplier L1 | Multiplier per level |
|---|---|---|---|---|
| Whirlwind | Area — all living enemies in the 4 orthogonally adjacent cells | 1 | 0.8× | +0.1 |
| Arcane Bolt | Single target | 2 | 1.0× | +0.1 |
| Execution | Single target | 1 | 1.5× | +0.1 |

| Rule | Value |
|---|---|
| Starting skill level | 0 = unlearned and unusable |
| Maximum skill level | **5** |
| Multiplier at L1–L5 (Whirlwind) | 0.8 / 0.9 / 1.0 / 1.1 / 1.2 |
| Multiplier at L1–L5 (Arcane Bolt) | 1.0 / 1.1 / 1.2 / 1.3 / 1.4 |
| Multiplier at L1–L5 (Execution) | 1.5 / 1.6 / 1.7 / 1.8 / 1.9 |
| Skill points | **+1 per Main Player level-up** — no other source |
| Cost per learn / upgrade | 1 skill point |
| Total to max all three skills | 15 skill points |
| Skills share the Action with a basic attack | Yes |

## 7. Items

| Rule | Value |
|---|---|
| Potion effect | Heals **35 %** of max HP (tunable) |
| Potions held at start | **3** |
| Using a potion in combat | Consumes the Action and ends the turn |
| Potion replenishment | Must have a source; potions are also found as loot |

## 8. Enemy AI

```text
1. Target the Main Player
2. Compute reachable cells within movement points
3. Move to the reachable cell that minimises distance to the Main Player
4. Attack if the Main Player is within attack range
5. End turn
```

- One enemy acts at a time, in spawn order.
- Enemies never crit, never use skills, never retreat, never switch targets.
- Enemy movement points: 2–3 (tunable per enemy).
- **Mini Boss mechanics** (each Mini Boss has at least one):

| Mechanic | Behavior |
|---|---|
| Area Attacker | Closes to its ability range (2) and fires an area attack at ×0.75 damage |
| Summoner | Summons its adds on the first turn |
| Enrager | One-time attack multiplier (×1.5) below 50 % HP |

- **Presentation rule:** an enemy's turn ends when its strike resolves, so its animation
  overlaps the start of the player's turn. During that overlap the Main Player may act
  from its current cell, but may not move to another cell until the animation finishes.
  The lock must never outlive the strike, and must not apply to automated walking.

## 9. Enemy Scaling, Levels & Count

```text
stat(stage) = base_stat × growth_rate^(stage - 1) × difficulty_multiplier
              × per-entry stat multiplier
              ± 15 % per-spawn variance
```

| Stat | Growth per stage |
|---|---|
| HP | ×1.20 (tunable) |
| Attack | ×1.16 (tunable) |
| Defense | ×1.15 (tunable) |
| Gold | ×1.18 (tunable) |

| Rule | Value |
|---|---|
| Enemy level | stage level + offset, minimum 1 |
| Offset distribution | `0: 40 %`, `±1: 15 %`, `±2: 10 %`, `±3: 5 %` |
| Stat variance | ±15 %, rolled per spawn, per stat |
| Difficulty multiplier | Per stage (default 1.0), applies to HP/attack/defense |
| Enemy count | `clamp(1 + floor((stage - 1) / 3), 1, 4)` — tunable |

**Enemy level is a real gameplay value.** It must drive enemy stat scaling and EXP
rewards (§10); it is not display-only.

## 10. EXP, Levels & Gold

```text
EXP requirement = round(100 × 1.15^(level - 1))

EnemyEXP = BaseEXP
         × EnemyLevelMultiplier        # 1 + 0.10 × (EnemyLevel - 1)
         × EnemyTypeMultiplier
         × StageFactor                 # 1.15^(Stage - 1)
```

| Rule | Value |
|---|---|
| `base_exp` | Per enemy definition (`experience_reward`) |
| `level_factor` | `1 + 0.10 × (enemy_level - 1)` |
| `StageFactor` | **1.15^(stage - 1)** (tunable) — tracks the level-requirement curve, so kills per level stays stable as enemy power compounds |
| Type multipliers | normal 1.0, elite 2.0, special 2.5, mini boss 4.0, treasure 1.5, gold 1.5, cursed 2.0 |
| EXP must not stall | Player levelling must keep pace with compounding enemy power |

| Level-up grant | Value |
|---|---|
| Max HP | +20 |
| Attack | +2 |
| Defense | +1 |
| Skill points | +1 |
| Talent tree / stat allocation | None — skill points are the only choice |

```text
stage gold = base_stage_gold × 1.18^(stage - 1)      # base_stage_gold = 50, tunable
enemy gold = base_gold × type_multiplier
```

Gold uses: Sub Hero summons, Sub Hero progression, town services.

## 11. Mini Bosses & Special Encounters

| Rule | Value |
|---|---|
| Mini Boss cadence | **Every 10th stage** (`stage % 10 == 0`), guaranteed |
| Boss level | The stage number |
| Guaranteed loot | Mini Boss table, minimum Rare (see §13) |
| Special encounter base chance | **3 %** (tunable) |
| Chance after a failed roll | **+1 %** (tunable) |
| Maximum chance | **15 %** (tunable) |
| After a successful roll | Reset to base |
| Pity scope | Session-scoped; guaranteed-Mini-Boss stages do not consume pity |
| Roll timing | When a stage is generated, before enemies spawn |
| Types | Elite, Treasure Monster, Special Monster, Random Mini Boss, Gold Monster, Cursed Monster |
| Type selection | Uniform among the six |
| Random Mini Boss level | `[stage - 20, stage]` with 80 % probability, otherwise `[1, stage - 21]` |
| Non-boss special enemies | Reuse a normal enemy, renamed and retyped |

## 12. Equipment

### Slots

Weapon, Helmet, Armor, Gloves, Boots, Ring, Amulet. Consumables are slot-less.

### Rarity

| Tier | Affixes | Affix value multiplier | Unique effect |
|---|---|---|---|
| Common | 1 | 1.00× | — |
| Uncommon | 2 | 1.35× | — |
| Rare | 3 | 1.70× | — |
| Epic | 4 | 2.05× | — |
| Legendary | 5 | 2.40× | 25 % chance |
| Mythic | 5 | 2.75× | Guaranteed |

- Item level = `max(enemy level, stage number)`.
- Rarity affects affix count, affix strength, unique-effect chance and presentation.
- Mythic is a special-source tier, not part of the normal rarity roll.
- Item score = `item_level × (1 + rarity × 0.25) + Σ|affix value| × (100 if percentage else 1)`
  — used only as a comparison signal, never as the sole measure of value.

### Affixes

| Affix | Base value | Roll weight |
|---|---|---|
| Attack | 5 | 1.2 |
| Defense | 4 | 1.2 |
| HP | 20 | 1.1 |
| Dodge | 3 % | 0.9 |
| Critical Chance | 3 % | 0.8 |
| Critical Damage | 15 % | 0.7 |
| Life Steal | 3 % | 0.6 |
| Damage vs Elite | 5 % | 0.55 |
| Movement | 1 | 0.45 |
| Damage vs Boss | 5 % | 0.45 |
| Attack Range | 1 | 0.25 |

```text
affix value = base × (1 + (item_level - 1) × 0.08)
                    × (1 + rarity_index × 0.35)
                    × random(0.80 .. 1.20)
```

- A stat appears at most once per item.
- **Every listed affix must affect combat.** Affixes that only display are a defect.

### Unique Effects

| Effect | Value |
|---|---|
| Combo — every 3rd attack | damage ×2.0 |
| Critical Heal | critical hit heals 5 % of max HP |
| Momentum — after moving ≥2 cells | damage ×1.75 |
| Back Attack | damage ×2.0 |
| Poison Execution — versus a poisoned target | damage ×1.5 |

Multipliers from all equipped items multiply together.

## 13. Loot

| Source | Drop chance | Guaranteed | Minimum rarity | Rarity weights (C/U/R/E/L/M) |
|---|---|---|---|---|
| Normal enemy | 25 % | 0 | Common | 60 / 25 / 10 / 4 / 1 / 0 |
| Elite | 50 % | 0 | Uncommon | 0 / 45 / 35 / 15 / 5 / 0 |
| Special encounter | 75 % | 0 | Rare | 0 / 20 / 40 / 30 / 10 / 0 |
| Mini Boss | 100 % | 1 | Rare | 0 / 0 / 55 / 30 / 13 / 2 |

- One enemy drops at most one item per clear.
- **15 %** of successful drops become a potion instead of equipment (tunable).
- Rarity weights are stage-independent; item level scales with stage.
- Authored stage content (chests, springs, caches) may also grant gold, healing or items.

| Rule | Value |
|---|---|
| Bag capacity | **TBD** — not yet a design commitment (see §19) |
| Overflow | Bag → storage → drop lost (report it to the player) |
| Storage | Long-term, effectively unbounded |
| Discard | Free, no gold return |
| Sell | Required action: sells an item for gold. Price model **TBD** (see §19) |
| Auto-equip | Never automatic; equipping is a player decision |

## 14. Loot Presentation & Comparison

```text
enemy dies → item rolls → added to bag (or storage)
    → rarity reveal (frame, name, rarity, item level, affix lines)
    → "NEW BEST ITEM" when the item beats the equipped item
```

- The reveal must not block or pause combat.
- Comparison shows the equipped item and the new item side by side with per-stat deltas
  and a score delta. Power Score alone must not decide.
- Item actions: **Equip, Keep, Sell, Discard.** (Sell's price model is still TBD.)

## 15. Sub Heroes

| Rule | Value |
|---|---|
| Combat slots | **3** |
| Control | Fully automatic, never directly controlled |
| Roles | DPS (damage, farming), Assist (buffs, utility) |
| Summon cost | 250 gold (tunable) |
| Quality weights | Common 70 % / Rare 25 % / Legendary 5 % (tunable) |
| Duplicate progression | 3 duplicates → +1 level |
| Attack model | Independent real-time cooldown per Sub Hero (`attack_interval`) |
| Damage | `attack_damage × (1 + 0.10 × (level - 1)) × quality_multiplier` |
| Quality multipliers | Common 1.00 / Rare 1.10 / Legendary 1.20 |
| Targeting | Lowest HP by default; Boss First for boss-oriented Sub Heroes |
| Attacks during enemy turns | Yes — they are not turn participants |
| Main Player is the only enemy target | Yes |
| Kills made by Sub Heroes | Must award EXP, gold and loot like any other kill |
| Investment before autonomous farming | Equipment, levels, build quality |

## 16. AUTO, Farming, Replay, Defeat

### AUTO decision order (per player turn)

```text
1. Stop if the Main Player is defeated
2. If no movement points remain, end the turn
3. Select a target: nearest living enemy, tie-break lowest HP,
   skipping enemies that cannot be reached into range
4. Drink a potion if HP ratio ≤ 0.35 and one is available
5. Attack if the target is in range
6. Otherwise path toward the target, attack if it lands in range, else end the turn
```

- Priority: **survival → target selection → damage → movement efficiency.**
- AUTO is allowed to use attacks, skills and potions.
- AUTO must never permanently soft-lock combat, and must not outperform a skilled player
  in every situation.
- If AUTO was on before a defeat, it stays on.

| Speed | Decision delay |
|---|---|
| x1 (default) | 0.40 s |
| x2 | 0.20 s |
| FASTEST | 0.05 s |

Changing speed must not reset the current turn, and must not change global engine time.

### Farming

FARMING and AUTO are independent toggles, and both already exist in the game.

| FARMING | AUTO | Behavior after a clear |
|---|---|---|
| ON | ON | Repeat the current stage — enemies respawn and idle farming continues |
| ON | OFF | Stay on the cleared stage and respawn its enemies; manual play continues |
| OFF | ON | Walk to the exit, then advance to the next stage automatically |
| OFF | OFF | The player walks to the exit and advances manually |

- Respawn happens only after the last enemy's death presentation finishes.
- While FARMING is on, stage advancement is blocked.

### Advance, replay, defeat

- Advancing requires standing on the exit cell, then confirming `NEXT STAGE`.
- With AUTO on and farming off, AUTO walks to the exit and advances automatically.
- **Replay:** if the next stage is already completed, standing on the exit is enough to
  leave during the player's turn, even with enemies alive. Abandoning a fight is not a
  clear.
- **Defeat:** the Main Player retreats one stage (minimum stage 1) and continues. No gold,
  EXP, item or progress loss.

## 17. Persistence Contract

Saved between sessions:

- Stage progression: current stage, highest stage reached, completed stages, consumed
  authored content
- Main Player: level, EXP, gold, skill points, skill levels
- Equipment, bag contents, storage contents
- Owned Sub Heroes, their levels, quality and slot assignments
- Important unlocks

Session-scoped (not saved): special-encounter pity, combat state, current stage runtime
state.

## 18. Idle Evaluation Model

```text
Idle Power      = f(DPS, survivability, sustain, automation efficiency, build quality)
Idle Capability = Stage Evaluation(Idle Power, stage conditions)

Stable Farming Stage ≤ Maximum Push Stage
Farming Efficiency = Success Rate × Reward / Time
```

| Output | Meaning |
|---|---|
| Stable Farming Stage | Highest stage cleared repeatedly with high reliability |
| Maximum Push Stage | Highest stage defeatable at all — slower, riskier, less efficient |
| Recommended Farming Stage | Best stage for the current objective (EXP / gold / equipment / other) — not necessarily the highest stable stage |

**Idle AI tiers** (automation capability, one input to Idle Power):

| Tier | Capability |
|---|---|
| 1 | Basic attack + target selection |
| 2 | Skill usage + basic rotation |
| 3 | Improved rotation, target selection, adaptation |
| 4 | Resource management, automatic healing, advanced decisions |
| 5 | Complete Idle AI: efficient rotation, enemy-aware decisions |

## 19. Open Questions

**Resolved and now part of this spec:**

- EXP stage growth (§10) — `StageFactor = 1.15^(stage - 1)`.
- Farming × AUTO behavior (§16) — the four-mode matrix, already implemented.

**Still open:**

1. **Sell price model** — Sell is a required item action (§14), but an item's gold value is
   TBD, so it cannot be implemented yet. Needs: the value formula, which item properties
   drive it (rarity, item level, affix count, unique effect), and whether selling is
   available from combat or only in town.
2. **Inventory capacity** — TBD. The shipped build uses a small bag plus effectively
   unbounded storage; capacity must be decided before it is treated as a rule.
3. **Enemy level's effect on stats** — the per-spawn level offset is rolled today; confirm
   how strongly it should move HP / attack / defense on top of stage-based scaling (§9).
4. **Assist Sub Heroes and Idle AI tiers** — designed (§15, §18) but unscheduled; confirm
   they are Tier 2 scope before implementation.
5. **Potion replenishment** — potions must come from somewhere beyond the starting stock
   and loot drops (§7): confirm town purchase, stage resupply, or loot only.
