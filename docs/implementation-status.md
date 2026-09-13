# Implementation Status

What the current build actually does, and where it differs from
`docs/gameplay-spec.md` / `docs/game-design.md`.

**How to read this:** every statement here was verified against source. The code is the
authority for *what exists today*; the spec is the authority for *what the game should
do*. Every entry in §3 is a work item, not a design decision.

---

## Balance v4: finalized design, implementation pending (2026-09-13)

The balance review changed Markdown only. The runtime still uses the legacy formulas
listed below. [The final contract](balance-rework-implementation.md) and
[reproducible calculations](balance-scale-rebase.md) define the pending implementation;
no legacy gap is closed by the document edit.

| Work item | Shipped behavior → finalized target |
|---|---|
| P0 stat reconstruction | **Shipped** (legacy formulas kept): one idempotent rebuild from level + equipped items (`PlayerController.recompute_stats_from_level_and_equipment`), used by boot, level-up, equip/unequip and load → the finalized level_scale/equipment aggregation |
| Combat/scaling | **Shipped (R1)**: shared armor `A/(1+D/A)` and the power-law `G` |
| Equipment | **Shipped (R1)**: inherent per-slot growth, normalized flat budgets, bounded utilities |
| EXP/Gold/economy | **Shipped (R2)**: shared `G`, the joint expected value, BaseItemValue 30 / sell cap 100 |
| Sub Heroes | **Shipped (R2)**: armor-resolved investment growth and collection-based pricing |
| Persistence/boundary | **Shipped (R2)**: backed-up, atomic, re-entrant format 4 migration and the validated Stage 1..1000 / level 1..1000 / il 1..1003 release range |
| Verification | Document analytic/discrete/EXP-only probes → production M1–M8; the R2 half now has production tests (see below), M5/M8 remain R3 |

### R0 shipped: profile, pure formulas, analytic fixtures, comparison table (2026-09-13)

R0 of [the final contract](balance-rework-implementation.md) §8 is implemented and verified
headless. It defines the v4 numbers and the shared math; **no runtime consumer has switched
over**, so every legacy value in §2 below still drives the game.

| Delivered | Where |
|---|---|
| Central v4 parameters: scale, difficulty ramp, encounter exponents, armor/damage bounds, release ranges, player coefficients, slot weights, reference/training enemies, Mini Boss multipliers | `scripts/balance/balance_profile.gd`, `resources/balance/balance_profile_default.tres` |
| Pure `G`, `level_scale`/`item_scale`, `count`, `difficulty`, armor, damage, rounding and boundary functions — all profile-parameterized, no node and no autoload | `scripts/balance/balance_formulas.gd` |
| Analytic reference case (L = il = S, seven Common slots, reference / Mini Boss / training variants) plus the M2 band constants | `tests/fixtures/balance_reference_case.gd` |
| M1 + analytic M2 assertions, read from the profile resource rather than copied numbers | `tests/balance_formulas_smoke_test.gd` |
| Comparison table generated from the profile | `tools/balance_reference_table.gd` → `docs/balance-reference-table.md` |

Verified: `G(1) = 1`, `G` monotonic over 1..1000, exact `r(S)`, a continuous difficulty ramp,
float armor homogeneity, the boundary inputs (A = 0, D = 0, huge D, NaN/∞, `MAX_COMBAT_VALUE`
saturation), unit weight columns, and the S3..1000 bands (work 2.79..5.87, survival
6.17..7.45, exactly 8 actions from S10, Mini Boss 9..10 actions). `G`, `item_scale`, encounter
work, static survival, discrete actions and HP remaining match the §7 document model row for
row on identical inputs.

Not in R0 on purpose: EXP, Gold, price, Sub Hero and persistence parameters join the same
profile in R2 with their consumers, and nothing here is wired into `LevelProvider`, combat,
equipment or the save format yet.

### R1 shipped: hero aggregation, equipment core/affix, enemies/training/Mini Boss (2026-09-13)

R1 of [the final contract](balance-rework-implementation.md) §8 is implemented and verified
headless. The **combat numbers** now come from the v4 formulas for the hero, for every piece of
equipment and for every enemy — including training stages and Mini Bosses. Rewards (EXP, Gold,
prices), Sub Hero damage and the save migration are still on the legacy curves, which is R2, so
this state is playable but explicitly **not releasable** (contract §8: no half-switched numbers
reach a player save).

| Delivered | Where |
|---|---|
| §3.1 aggregation `effective_X = round(level_scale(L) * (b_X*M_X + Flat_X))` — per-slot factors, the empty-slot constant, no average item level, one final rounding; §3.2 effective utility caps; §3.3 HP projection | `scripts/balance/balance_formulas.gd`, `scripts/balance/equipment_stat_block.gd` |
| The ONE equipment→stat aggregation, shared by the live rebuild and every preview (compare payload, `PlayerController.preview_equipment_block`) | `scripts/balance/equipment_stat_block.gd` |
| §3.2 affix values: `base * (1 + 0.35r) * roll * item_scale(il)` for HP/ATK/DEF (bases 12.12 / 5.18 / 0.50) and the same product WITHOUT the item scale for utility affixes; the roll band and the bases come from the profile | `scripts/items/equipment_affix.gd`, `scripts/systems/equipment_generator.gd` |
| Hero: one idempotent rebuild from level + gear, level-up keeps the current HP, a swap that would floor a living hero below 1 HP is refused instead of patched with `max(1)` | `scripts/player/player_controller.gd`, `scripts/player/player_stats.gd` |
| §4.2/§4.3 enemies: `G(S)`, the encounter count frozen at stage build, the real level offset, independent per-stat variance, difficulty carried ONCE on the `StageDefinition`; stages 1..2 fixed at 130/12/3; Mini Boss = reference enemy at a frozen c = 4 with ×6 HP / ×1.5 ATK / ×1.25 DEF, offset 0, variance 1 | `scripts/systems/enemy_scaling.gd`, `scripts/systems/level_provider.gd`, `scripts/systems/stage_manager.gd`, `scripts/systems/level_manager.gd` |
| §4.1 ONE armor entry `raw = A/(1 + D/A)`, one final rounding, floor 1 — player attacks, skills and the Magic Tome all resolve through it, and enemies use the same path | `scripts/combat/combat_system.gd` |
| §7 injection: the provider owns the profile, the stage manager resolves it, and the world hands that same instance to the hero and the damage entry | `scripts/systems/level_provider.gd`, `scripts/world/grid_combat.gd` |
| The 24-enemy pool compressed ONCE to the reference band 0.9..1.1, with the old → new record and a guard against a second run | `tools/balance_compress_enemy_pool.gd` → `docs/balance-enemy-pool.md` |
| Reverse-order equipment, mixed gear, empty slots, both scales moving independently, the caps and the utility rolls | `tests/balance_aggregation_smoke_test.gd` (91 checks) |
| Normal spawns, the group factor, offsets and per-stat variance, training stages, Mini Bosses and the provider's stage definitions | `tests/enemy_stat_scaling_smoke_test.gd` (73 checks) |

Verified green: `balance_aggregation`, `enemy_stat_scaling`, `balance_formulas`,
`combat_affix`, `magic_tome`, `stage_progress_save`, `enemy_experience_scaling`,
`player_progress`, `skill_progression`, `subhero_combat`, `subhero_kill_reward`,
`stage_content`, `economy`, `scavenger_shop`, `beginner_sword_drop`. The only test expectations
rewritten were the ones that asserted the REPLACED rules: the spell damage figure (`ATK - DEF`
→ the armor entry) and the affix→stat mapping test (which now checks the aggregation), plus the
in-combat affix fixture, whose enemy needed a maximum HP that survives the taller v4 hero hits.

Explicitly NOT in R1 (deliberately still legacy, so no reward is half-switched): enemy EXP and
Gold scaling, item prices and the economy expectations, Sub Hero damage and investment
coordinates, the v4 save migration. `EquipmentInstance.get_equipment_score()` remains a display
value only — it is not a power verdict and must stop feeding AUTO re-equip and pricing in R2.
The compare CARD still renders the raw affix deltas it always did; the same-source effective
preview exists as data (`PlayerController.preview_equipment_block`, `EquipmentStatBlock.compare`)
and gets its UI surface in the R3 acceptance pass. `docs/gameplay-spec.md` still describes the
legacy numbers; its text is updated with the release pass in R3.

### R2 shipped: EXP/Gold/prices/Sub Heroes, one settlement, v4 migration (2026-09-13)

R2 of [the final contract](balance-rework-implementation.md) §8 is implemented and verified
headless. **Every runtime number now comes from the v4 formulas**: the hero, the enemies, the
rewards, the prices and the Sub Heroes. The v3 → v4 save migration ships with the atomic,
re-entrant conversion the contract requires, so the switch can no longer strand an existing save.

| Delivered | Where |
|---|---|
| §5 `need(L) = round(100 * count(L) * G(L))`, `catchup(S,L) = clamp(1 + 0.10*(S-L), 0.25, 2.0)`, `kill_exp = max(1, round(100 * G(S) * offset_mult * type_exp * catchup))`; the level cap banks no EXP and pays no skill point | `scripts/balance/balance_formulas.gd`, `scripts/player/player_progression.gd`, `scripts/systems/experience_system.gd` |
| §6.1 `stage_clear_gold = round(50 * G(S))`, `enemy_gold = round(base_gold * G(S) * offset_mult * type_gold)`; the legacy `rate^(stage-1)` reward curve is DELETED (`EnemyScaling.scale_value` is gone) and the rewards are written onto the runtime once, at stage build, with the same offset multiplier the combat stats use | `scripts/systems/enemy_scaling.gd`, `scripts/systems/gold_system.gd`, `scripts/systems/stage_manager.gd` |
| §8 "all rewards settle exactly once": the EXP and the Gold each have ONE settlement entry keyed by the enemy's runtime instance id, and the combat log reads the amount that was actually paid instead of recomputing it | `scripts/systems/experience_system.gd`, `scripts/systems/gold_system.gd`, `scripts/world/grid_combat.gd` |
| §6.1 prices on the shared scale: `item_level_multiplier = G(il)`, `Buy = max(floor(Value*4), Sell+1, 1)`, `Sell = max(1, floor(min(Value*0.25, 100 * StageExpectedSell)))`; `StageExpectedSell` uses the **enumerated joint** `E[RarityMultiplier * AffixMultiplier]` over the real catalogue | `scripts/economy/item_economy.gd`, `scripts/economy/economy_config.gd`, `scripts/balance/balance_formulas.gd` |
| §6.2 Sub Heroes: `investment_level = 1 + (hero_level-1)/(8*p_i)`, `combat_level = min(main_level, investment)`, `hero_attack = base_damage * quality_multiplier * G(combat_level)` resolved through the §4.1 armor entry, and `summon_cost = max(250, ceil(10 * G(min(1000, 1 + owned_draws/24))))` priced BEFORE the draw from the whole collection | `scripts/sub_hero/sub_hero_combat_manager.gd`, `scripts/sub_hero/sub_hero_summon_service.gd`, `scripts/ui/sub_hero_shop_panel.gd` |
| §9 v3 → v4 migration: the EXP as a level FRACTION, the Gold at the highest unlocked stage's own ratio (log domain), every item's identity/roll/unique effect kept with derived values recomputed, authored and negative affixes rebuilt from a signed base, out-of-range records clamped into the release range with the legacy values stored in `legacy_snapshot` | `scripts/progress/balance_migration_v4.gd`, `scripts/progress/stage_progress_save.gd` |
| §9 backup and atomicity: the untouched original is copied to `<save>.v3.bak` exactly once, the converted payload is written to a scratch file and only then moved into place, and the rewritten file carries `version 4` / `balance_version 4` so a second load converts nothing | `scripts/progress/stage_progress_save.gd` |

Verified green: `balance_migration_v4` (new), `enemy_experience_scaling` (rewritten for §5/§6.1),
`economy` (rewritten for §6.1), `subhero_summon` (rewritten for the derived price),
`subhero_combat` (§6.2 coordinate + the armor entry), plus unchanged
`balance_formulas`, `balance_aggregation`, `enemy_stat_scaling`, `combat_affix`, `magic_tome`,
`player_progress`, `subhero_kill_reward`, `subhero_runtime`, `subhero_progression`, `subhero_data`,
`stage_progress_save`, `stage_content`, `skill_progression`, `scavenger_shop`,
`beginner_sword_drop`, `item_registry`, and the UI suites `test_stage_save`, `test_subhero_shop`,
`test_item_popup`.

Three production bugs were found and fixed by the R2 work rather than by the document:
`item_level_multiplier` used `G(il)^0.6` instead of `G(il)` (prices were ~45 % low at il 11 and
worse above); `BalanceFormulas.affix_value` clamped a negative authored value to 0, which silently
deleted every cursed item's drawback; and the converted payload was not stamped with the new
version, so the migration re-applied itself on every load.

**Deviation from the contract's constant (§6.1).** The contract's `2.136384474` and its `k ≥ 83.85`
bound were derived by the probe in `balance-scale-rebase.md` §7, whose script samples with the
**combat roll weights** `(1.2, 1.2, 1.1, .9, .8, .7, .6, .55, .45, .45, .25, .35)`. §6.1 specifies
`Σ(roll_ratio × economic_weight)`, and the catalogue's own economic column is
`(1.0, 0.9, 0.8, 1.5, 1.4, 1.3, 2.5, 2.0, 2.0, 1.5, 1.8, 2.2)`. Implemented as specified — the
clamp applied per item, over every ordered draw without replacement — the joint expectation is
**2.2376738**, confirmed by two independent computations (the production recurrence and a
brute-force enumeration of all 95 040 five-affix sequences, asserted equal in
`tests/economy_smoke_test.gd`). The document's own probe instead averages the weight SUM first and
clamps afterwards, which is what produces 2.136384474 for its (roll-weight) column.

`sell_cap_stages` is **100**, unchanged: the contract's own bound with the corrected mean is
`k ≥ 35 × 3 × 1.706 / 2.2376738 ≈ 80.05`, so 100 clears it with more margin than the document
claimed. `tests/economy_smoke_test.gd` asserts that bound against the profile rather than against a
copied constant. The document's probe script should use the economic weights and clamp per item
before its table is regenerated.

Explicitly NOT in R2: M5 (the 100-seed × S1..1000 progression simulation) and M8 (AUTO speeds,
Boss drops, the UI preview-vs-equipped comparison surface), which are R3, and the
`docs/gameplay-spec.md` rewrite that goes with the release pass. The compare card still renders raw
affix deltas; `EquipmentInstance.get_equipment_score()` is still a display value that no longer
feeds a price, but AUTO re-equip still needs its R3 verdict swap.

## 1. Implemented Systems

| System | Location |
|---|---|
| Grid combat, arena, gates, presentation | `scripts/world/grid_combat.gd`, `scenes/world/grid_combat.tscn` |
| Grid model / pathfinding | `scripts/systems/grid_map_2d.gd` |
| Click-to-navigate (persistent destination, blocker handling) | `scripts/systems/navigation_controller.gd` |
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
| Player progress + save (map progress, items, Sub Heroes, character numbers) | `scripts/progress/player_progress.gd`, `stage_progress_save.gd` |
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

## 2. Current Shipped Values (legacy balance baseline)

Verified equal to `gameplay-spec.md`, so no action needed:

- Grid: 11×7 inner field (`x = 1..11`, `y = 0..6`) with one gate cell on each side of row 4
  (`x = 0` Starting Cell, `x = 12` Next Stage Cell); the outer columns are unusable on every
  other row. Orthogonal movement, Manhattan distance, forward arrival `(1, 3)`, backward
  arrival `(11, 3)`, gate cells excluded from enemy spawn.
- Turn rule: 3 movement points + one action; moving never spends the action; the action
  ends the turn; free movement after a clear.
- Attack range 1; crit 5 % / 150 %; player-only crits.
- Damage formula and order (multipliers after defense, minimum 1).
- Skills: Whirlwind 0.8 / Arcane Bolt 1.0 / Execution 1.5, max level 5, +0.1 per level,
  1 skill point per level-up, all skills start unlearned.
- Enemy scaling rates HP 1.20 / ATK 1.16 / DEF 1.15 / gold 1.18 / EXP 1.15, ±15 % variance,
  level offsets `40/15/15/10/10/5/5`, enemy count `clamp(1 + floor((stage-1)/3), 1, 4)`.
  `experience_reward` is stage-scaled at spawn like the other rates, so
  `EnemyEXP = BaseEXP × EnemyLevelMultiplier × EnemyTypeMultiplier × 1.15^(stage-1)` (legacy §10; superseded in the v4 target).
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
- Backward transition: stepping onto the Starting Cell returns to the previous stage and
  arrives one cell left of the Next Stage Cell (the defeat retreat uses the same arrival).
  Refused on stage 1 and while FARMING or AUTO is on; needs no clear and no particular turn.
- Authoring model: `StageDatabase` ranges, `LevelConfig` + `LevelTemplate` both producing
  a `StageDefinition`; canonical stage id `forest_006`.
- Content layer (`StageContent`) for chests / springs instead of new stage types.

---

## 3. Deviations From the Spec (work items)

### 3.1 Progression

Closed items are removed from these tables and their number retired, so ids stay stable.

| # | Spec | Current implementation | Impact |
|---|---|---|---|
| 1 | §9/§10 offset multiplier 1+0.06×(enemy_level-stage) affects stats and rewards | Enemy level drives only the legacy EXP factor; stats ignore it | Design resolved; implementation pending |

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
| 26 | §13/§14 buyback | The buyback book is **session-scoped**: it holds the items the player gave up this session and is emptied by a restart | No longer a consequence of row 3 (the bag and warehouse ARE persisted now), it is an independent gap. The once-per-save drop record IS persisted |

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

| Potion replenishment | The potion source beyond the 3 starting uses and loot drops |

---

## 5. Verification Entry Points

UI harness suites (`tools/ui_harness/run_ui_harness.ps1 -Suite <name> -Quiet`):

```text
test_combat_log_panel      test_combat_log_wiring     test_development_panel
test_enemy_attack_move_lock test_game_locale          test_grid_click_actions
test_grid_navigation       test_inventory_panel      test_item_popup
test_stage_content         test_magic_tome           test_stage_exit_advance
test_stage_flow            test_stage_progression    test_stage_range
test_stage_save            test_subhero_assignment   test_subhero_row
test_subhero_shop          test_town_view            test_world_map
```

Headless smoke tests (`res://tests/*_smoke_test.gd`):

```text
area_stage_data   balance_formulas   balance_aggregation   balance_migration_v4
player_progress   skill_progression  stage_content     stage_database
stage_progress_save   stage_router   subhero_combat    subhero_data
subhero_progression   subhero_runtime   subhero_summon   enemy_experience_scaling
enemy_stat_scaling   subhero_kill_reward   beginner_sword_drop
scavenger_shop    economy   combat_affix      item_registry   magic_tome
```

Generated reference table (reads `resources/balance/balance_profile_default.tres` and
rewrites `docs/balance-reference-table.md`):

```text
godot --headless --path . -s res://tools/balance_reference_table.gd
```

One-time enemy pool compression (contract §4.2 — refuses to run a second time):

```text
godot --headless --path . -s res://tools/balance_compress_enemy_pool.gd
```

Run only the suite covering a change. Never run the full harness unless asked.
