# Implementation Status

What the current build actually does, and where it differs from
`docs/gameplay-spec.md` / `docs/game-design.md`.

**How to read this:** every statement here was verified against source. The code is the
authority for *what exists today*; the spec is the authority for *what the game should
do*. Every entry in §3 is a work item, not a design decision.

---

## 1. Implemented Systems

| System | Location |
|---|---|
| Grid combat, arena, gates, presentation | `scripts/world/grid_combat.gd`, `scenes/world/grid_combat.tscn` |
| Grid model / pathfinding | `scripts/systems/grid_map_2d.gd` |
| Turn manager / phases | `scripts/systems/turn_manager.gd`, `scripts/combat/turn_state.gd` |
| Damage, targeting, skills resolution | `scripts/combat/combat_system.gd` |
| Skill definitions | `scripts/combat/skill_catalog.gd`, `skill_definition.gd` |
| Magic Tome (global spells, Player-Turn cooldowns) | `scripts/combat/magic_tome.gd`, `magic_tome_catalog.gd`, `magic_skill_definition.gd` |
| Enemy runtime, AI, mini-boss mechanics | `scripts/enemies/enemy_controller.gd` |
| AUTO, farming, game speed | `scripts/systems/auto_combat_controller.gd` |
| Stage manager, gates, spawns, clear/defeat | `scripts/systems/stage_manager.gd` |
| Level generation / scaling / encounters | `scripts/systems/level_provider.gd`, `level_manager.gd`, `enemy_scaling.gd` |
| Stage/area data model | `scripts/data/stage_database.gd`, `stage_data.gd`, `stage_type.gd`, `stage_content.gd` |
| Routing (combat / town) | `scripts/systems/stage_router.gd`, `stage_flow.gd` |
| Player progress + save | `scripts/progress/player_progress.gd`, `stage_progress_save.gd` |
| Character progression (level/EXP/gold/skills) | `scripts/player/player_progression.gd`, `scripts/systems/experience_system.gd`, `gold_system.gd` |
| Player stats & controller | `scripts/player/player_stats.gd`, `player_controller.gd` |
| Equipment, affixes, comparison, inventory, storage | `scripts/items/` |
| Combat statuses (Stun) | `scripts/combat/status_effect_component.gd` |
| Unique item effects | `scripts/items/effects/` |
| Loot tables & generation | `scripts/systems/loot_table.gd`, `loot_generator.gd`, `loot_system.gd` |
| Guaranteed stage drops & Scavenger Shop buyback | `resources/items/beginner_sword.tres`, `scripts/shop/scavenger_shop.gd`, `scripts/ui/scavenger_shop_panel.gd` |
| Sub Heroes (data, catalog, summon, progression, combat) | `scripts/sub_hero/`, `resources/sub_heroes/` |
| UI (combat HUD, town, world map, inventory, item popup, skill panel, shop, assignment, bestiary, dev panel) | `scripts/ui/`, `scenes/ui/` |
| Localization (en / zh_Hant) | `scripts/systems/game_locale.gd` |

### Authored Content Shipped

- One area database: `resources/stage_databases/forest.tres` — Forest, stages **1–10**,
  default type `COMBAT`, overrides at stage 6 (`COMBAT` + Hidden Cache 150 gold +
  repeatable Forest Spring, 25 % max-HP heal), stage 8 (`TOWN`), stage 10 (`BOSS`).
- Fixed levels: `resources/levels/level_001.tres`, `level_002.tres` (Training Wraith,
  1 and 2 enemies), `level_010.tres` (Ashen Oracle), `level_100.tres` (Bloodbound
  Warlord, difficulty 1.05).
- Enemies: 24 generated normal enemies (`resources/enemies/generated/`) plus 3 authored
  Mini Bosses (Ashen Oracle, Gravecaller, Bloodbound Warlord).
- Sub Heroes: 8 authored (`resources/sub_heroes/`).

---

## 2. Current Values That Match the Spec

Verified equal to `gameplay-spec.md`, so no action needed:

- Grid 11×7, orthogonal movement, Manhattan distance, start `(0, 3)`, exit `(10, 3)`.
- Turn rule: 3 movement points + one action; moving never spends the action; the action
  ends the turn; free movement after a clear.
- Attack range 1; crit 5 % / 150 %; player-only crits.
- Damage formula and order (multipliers after defense, minimum 1).
- Skills: Whirlwind 0.8 / Arcane Bolt 1.0 / Execution 1.5, max level 5, +0.1 per level,
  1 skill point per level-up, all skills start unlearned.
- Enemy scaling rates HP 1.20 / ATK 1.16 / DEF 1.15 / gold 1.18 / EXP 1.15, ±15 % variance,
  level offsets `40/15/15/10/10/5/5`, enemy count `clamp(1 + floor((stage-1)/3), 1, 4)`.
  `experience_reward` is stage-scaled at spawn like the other rates, so
  `EnemyEXP = BaseEXP × EnemyLevelMultiplier × EnemyTypeMultiplier × 1.15^(stage-1)` (§10).
- Mini Boss every 10th stage; boss level = stage number.
- Special encounters: 3 % base, +1 % per failure, 15 % cap, reset on success, six types,
  random Mini Boss level window, no pity consumption on boss stages.
- EXP requirement `100 × 1.15^(level-1)`; level-up grants +20 HP / +2 ATK / +1 DEF / +1
  skill point.
- Stage gold `50 × 1.18^(stage-1)`; gold type multipliers.
- 7 slots, 6 rarities with 1/2/3/4/5/5 affixes, affix value formula, 5 unique effects and
  their multipliers, item level `max(enemy level, stage)`, item score formula.
- Loot tables and drop chances (25 / 50 / 75 / 100 %), Mini Boss guaranteed drop,
  15 % consumable substitution.
- Stage 10 (`forest_010`, the Ashen Oracle) grants the fixed **Beginner Sword** — Weapon,
  Common, item level 10, Attack +10 — once per save, recorded in the save's
  consumed-content store; replaying the stage grants nothing further.
- Town **Scavenger Shop** with a BUYBACK tab: a discarded or sold item is stocked at its
  Power Score and can be bought back into the bag (or the warehouse when the bag is full).
  Buying back writes nothing to the one-shot store, so it cannot re-arm a stage drop.
- Bag 10 slots, storage effectively unbounded, discard is free, equip is manual only.
- Sub Heroes: 3 slots, 250 gold summon, quality weights 70/25/5, 3 duplicates → +1 level,
  real-time attack interval, damage formula and quality multipliers, enemies never target
  them.
- Every kill — player attack, skill or Sub Hero — finishes through
  `CombatSystem.resolve_defeat()` → `actor_died`, so a Sub Hero kill awards the same EXP,
  gold and loot (same drop chance) as the player's own kill (§15).
- AUTO speeds 0.40 / 0.20 / 0.05 s, x1 default, no decision reset on speed change.
- Farming respawns the same stage after the death presentation and blocks advancement;
  the FARMING × AUTO matrix matches the spec (farming repeats the current stage; AUTO
  with farming off walks to the exit and advances).
- Replay skip and defeat retreat (stage −1, minimum 1, no penalty).
- Authoring model: `StageDatabase` ranges, `LevelConfig` + `LevelTemplate` both producing
  a `StageDefinition`; canonical stage id `forest_006`.
- Content layer (`StageContent`) for chests / springs instead of new stage types.

---

## 3. Deviations From the Spec (work items)

### 3.1 Progression

Closed items are removed from these tables and their number retired, so ids stay stable.

| # | Spec | Current implementation | Impact |
|---|---|---|---|
| 1 | §9/§10 enemy level drives stats and EXP | Enemy level drives the EXP reward factor only; stat scaling uses the stage number and ignores level | The displayed enemy level is misleading at high stages |
| 3 | §17 full persistence | Save holds **map progress only**: `current_stage_number`, `highest_stage_reached`, `completed_stages`, `consumed_content` (`user://save/stage_progress.json`, version 1) | Level, EXP, gold, skill points, skill levels, equipment, bag, storage and Sub Heroes are **reset on restart** — directly violates GDD §13.3 |

### 3.2 Combat & Items

| # | Spec | Current implementation | Impact |
|---|---|---|---|
| 8 | §8 mini-boss mechanics | AOE (range 2, ×0.75), Summoner (1 add), Enrager (×1.5 below 50 % HP) are implemented; the 3-boss pool is picked at random | Matches spec; more Mini Bosses need more mechanics |

### 3.3 AUTO, Farming, Idle

| # | Spec | Current implementation | Impact |
|---|---|---|---|
| 9 | §16 AUTO may use skills, potions and bag items | AUTO never uses skills and never touches the bag; it only drinks from the HUD potion counter at ≤35 % HP (`auto_combat_controller.gd`) | AUTO underperforms manual play by design gap, not by intent |
| 10 | §16 priority includes damage before movement | AUTO ends the turn when movement points reach 0, even with an enemy in attack range | Wasted turns the player would not take |
| 11 | §18 Idle Power / Idle Capability / Farming Efficiency / Recommended Farming Stage | Not implemented in any form | No idle evaluation output exists yet |
| 12 | §18 Idle AI tiers 1–5 | Not implemented; AUTO is a single fixed decision list | Automation cannot improve over time |
| 13 | §15 Sub Hero roles (DPS / Assist) | All 8 Sub Heroes are pure damage; no buff or utility role exists | Assist design is unimplemented |
| 14 | §15 Sub Hero unique effects | The `unique_effect` hook is called on hit but all 8 authored Sub Heroes have `null` | Sub Heroes have no build identity |
| 16 | §15 targeting rules | `Closest to Defeat` is an alias of `Lowest HP` (identical code path) | A documented rule has no distinct behavior |

### 3.4 Equipment, Loot, Economy

| # | Spec | Current implementation | Impact |
|---|---|---|---|
| 17 | §13/§14 item actions Equip / Keep / Sell / Discard | `Equip`, `Discard` and **`Sell`** all exist; `Store`/`Withdraw` (warehouse) approximates `Keep`. Sell is offered by the town surfaces only — the Scavenger Shop's SELL tab and the item popup from the warehouse — and pays the §19 price | Closed for the town surfaces; the in-combat inventory deliberately offers no Sell |
| 18 | §14 comparison during loot presentation | The drop popup only reveals the item; comparison lives in the inventory item popup | Loot decisions require opening the inventory |
| 19 | §13 rarity as a build lever | Rarity biases value via a multiplier, but no rarity-exclusive affix or effect exists beyond the unique-effect chance | Higher rarity is mostly a numbers upgrade |
| 26 | §13/§14 buyback | The buyback book is **session-scoped**: it holds the items the player gave up this session and is emptied by a restart | Consequence of row 3 — the bag is not persisted either, so a surviving book would hold an item nobody owns. The once-per-save drop record itself IS persisted |

### 3.5 World, Town, Content

| # | Spec / GDD | Current implementation | Impact |
|---|---|---|---|
| 20 | GDD §4.1 regions continue global numbering | Only Forest 1–10 is authored; stage 11+ is area-less endless content | The world map shows one area; more regions are needed for the designed progression |
| 21 | GDD §13.1 town for equipment, storage, skills, Sub Heroes, progression | Town has exactly 3 facilities: warehouse, skill mentor and scavenger shop | Town is still a shell of the designed management area |
| 22 | GDD §13.2 gold for summons, Sub Hero progression, town services | Gold is spent on Sub Hero summons and scavenger-shop buybacks; no equipment shop, no upgrades | Gold has two sinks |
| 23 | GDD §4.3 stage states Locked / Ready / Current / Completed | Implemented as `LOCKED` / `READY` / `DONE` / `HERE`; unlock rule = previous stage cleared or `stage ≤ highest_stage_reached` | Naming differs; behavior matches |
| 24 | — | The bestiary is a character-sprite atlas browser, not an enemy stat codex (`enemy_bestiary_panel.gd`) | Not a spec conflict, but the label overstates it |
| 25 | §11 special-encounter rolls | Fixed-`LevelConfig` stages (1, 2, 10, 100) skip the roll entirely and do not advance pity | Authored stages are exempt from the pity model |

---

## 4. Blocked On Design Decisions

These cannot be closed by implementation alone — they need an answer first
(`docs/gameplay-spec.md` §20).

| Item | What is needed |
|---|---|
| Equipment vendor stock | A forward vendor — one that sells gear TO the player — does not exist. Its stock policy (item level, stock size, restock cadence, affix rolling) must be decided before one ships; the §19 buy price is already specified |
| Inventory capacity | A capacity rule. The build uses a 10-item bag plus effectively unbounded storage; the spec leaves capacity TBD |
| Idle Power / Idle Capability / Idle AI tiers | Scheduling, plus a defined player-facing output (where Stable Farming Stage, Maximum Push Stage and the recommended farming stage are shown) |
| Assist Sub Heroes | Buff / utility role design — all 8 Sub Heroes are pure damage today |
| Enemy level's stat effect | How strongly the per-spawn level offset should move HP / attack / defense on top of stage-based scaling |
| Potion replenishment | The potion source beyond the 3 starting uses and loot drops |

---

## 5. Verification Entry Points

UI harness suites (`tools/ui_harness/run_ui_harness.ps1 -Suite <name> -Quiet`):

```text
test_combat_log_panel      test_combat_log_wiring     test_development_panel
test_enemy_attack_move_lock test_game_locale          test_grid_click_actions
test_inventory_panel       test_item_popup            test_stage_content
test_magic_tome            test_stage_exit_advance    test_stage_flow
test_stage_progression     test_stage_range           test_stage_save
test_subhero_assignment    test_subhero_row           test_subhero_shop
test_town_view             test_world_map
```

Headless smoke tests (`res://tests/*_smoke_test.gd`):

```text
area_stage_data   player_progress   skill_progression   stage_content
stage_database    stage_progress_save   stage_router
subhero_combat    subhero_data   subhero_progression   subhero_runtime
subhero_summon    enemy_experience_scaling   subhero_kill_reward
beginner_sword_drop   scavenger_shop   economy
combat_affix      item_registry   magic_tome
```

Run only the suite covering a change. Never run the full harness unless asked.
