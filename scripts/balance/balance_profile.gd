class_name BalanceProfile
extends Resource

## Single owner of the finalized v4 balance parameters
## ([code]docs/balance-rework-implementation.md[/code]).
##
## Consumers receive this resource by explicit injection: [LevelProvider] holds the export
## and hands it to the systems it already configures, and the static [BalanceFormulas]
## helpers take it as an argument. No gameplay code restates a default and nothing reads
## these numbers from a global — there is no autoload (contract §7).
##
## Scope: this class carries exactly the parameters R0/R1/R2 read — the shared scale, the
## difficulty ramp, the armor/damage bounds, the reference enemies, the equipment weights,
## the affix generation constants, the effective utility caps, and the R2 group: EXP/level
## requirements, kill rewards, stage Gold, item/potion prices and the Sub Hero investment and
## summon pricing. The profile never holds a value nothing reads.

## Canonical balance stat ids. The affix catalogue uses the same three ids;
## [code]player_controller.gd[/code] maps its stat-block key [code]&"max_hp"[/code] onto
## [constant STAT_HP].
const STAT_HP: StringName = &"hp"
const STAT_ATTACK: StringName = &"attack"
const STAT_DEFENSE: StringName = &"defense"
const STAT_IDS: Array[StringName] = [STAT_HP, STAT_ATTACK, STAT_DEFENSE]

## One weight entry per slot of [EquipmentSlot] (Weapon … Amulet).
const SLOT_COUNT: int = 7

## The shipped parameter set. Consumers are handed a profile by [LevelProvider]; this is the
## ONE fallback for the ones that boot without a provider (headless smoke tests, tooling), so
## no consumer ever restates a balance default of its own.
const DEFAULT_PROFILE_PATH: String = "res://resources/balance/balance_profile_default.tres"

static var _default_profile: BalanceProfile


## The default parameter set, loaded once. Never call this from a system that can be handed a
## profile instead — injection is the contract (§7); this keeps a headless entry point honest.
static func get_default() -> BalanceProfile:
	if _default_profile == null:
		_default_profile = load(DEFAULT_PROFILE_PATH) as BalanceProfile
	return _default_profile

@export_group("Release bounds")
## Last authored stage. The release range is 1..max_stage; the stage 1000 clear allows
## replay but never generates 1001 (§1/§9).
@export_range(1, 1000000, 1) var max_stage: int = 1000
@export_range(1, 1000000, 1) var max_character_level: int = 1000
@export_range(1, 1000000, 1) var max_item_level: int = 1003
## Fault-protection line for any combat value (§2). It is not a tuning knob: the largest
## legal configuration in the supported range must pass well below it.
@export var max_combat_value: float = 1000000000000.0
## Persisted Gold/EXP ceiling (§2), deliberately far above the combat line.
@export var max_persistent_value: float = 9000000000000000.0

@export_group("Shared scale")
## `G(x) = ((max(x,1) + growth_offset) / growth_divisor)^growth_exponent` (§2).
@export_range(1, 8, 1) var growth_exponent: int = 4
@export var growth_offset: float = 20.0
@export var growth_divisor: float = 21.0
## σ: the EQUIPMENT share of the reference state's LOG growth, not a share of the stat
## panel. `level_scale` receives `1 - σ`, `item_scale` receives σ (§2/§3.1).
@export_range(0.0, 1.0, 0.01) var equipment_share: float = 0.60

@export_group("Difficulty ramp")
## `difficulty(S)`: a ramp from `difficulty_start` to `difficulty_mid` at
## `difficulty_mid_stage`, a ramp to `difficulty_cap` at `difficulty_cap_stage`, then flat.
## Both boundaries are continuous (§2).
@export var difficulty_start: float = 0.90
@export var difficulty_mid: float = 1.00
@export var difficulty_cap: float = 1.10
@export_range(2, 1000, 1) var difficulty_mid_stage: int = 10
@export_range(2, 1000, 1) var difficulty_cap_stage: int = 100

@export_group("Encounter")
## `count(S) = clamp(base + floor((S-1)/interval), 1, max)`, frozen when the stage is
## built: killing an enemy never re-scales the survivors (§4.2).
@export_range(1, 8, 1) var base_enemy_count: int = 1
@export_range(1, 8, 1) var max_enemy_count: int = 4
@export_range(1, 99, 1) var enemy_count_interval: int = 3
## A larger group is weaker per member; DEF takes no group discount (§4.2).
@export_range(-2.0, 0.0, 0.01) var enemy_hp_count_exponent: float = -0.60
@export_range(-2.0, 0.0, 0.01) var enemy_attack_count_exponent: float = -0.80
## `offset_mult = 1 + step * o` on the CLAMPED real enemy-level offset (§4.2).
@export_range(0.0, 0.5, 0.01) var enemy_offset_step: float = 0.06
## Independent uniform variance band per stat (§4.2).
@export_range(0.0, 2.0, 0.01) var enemy_variance_min: float = 0.85
@export_range(0.0, 2.0, 0.01) var enemy_variance_max: float = 1.15
## Stages 1..this use the fixed training base instead of the compressed normal pool (§4.2).
@export_range(0, 10, 1) var training_stage_limit: int = 2

@export_group("Player base")
## Reference bare-level coefficients `b_X` (§3.1). A design baseline, not the measured
## mean of a full set of randomly rolled equipment.
@export var base_hp: float = 121.2
@export var base_attack: float = 51.8
@export var base_defense: float = 5.0
## `rarity_core(r) = 1 + step * r`, r = 0..5 Common..Mythic (§3.1).
@export_range(0.0, 1.0, 0.01) var rarity_core_step: float = 0.08
## Per-slot weights `w_X,s`, indexed by [EquipmentSlot]; every stat column sums to 1 so a
## full set of reference items yields `M_X = G(il)^σ`.
@export var slot_hp_weights: Array[float] = [0.00, 0.15, 0.40, 0.10, 0.20, 0.05, 0.10]
@export var slot_attack_weights: Array[float] = [0.60, 0.00, 0.00, 0.15, 0.00, 0.15, 0.10]
@export var slot_defense_weights: Array[float] = [0.00, 0.25, 0.45, 0.00, 0.20, 0.05, 0.05]

@export_group("Affix generation")
## §3.2: an HP/ATK/DEF affix base is this share of its OWN `b_X` (10 % → 12.12 / 5.18 /
## 0.50), which is what keeps one HP affix worth the same budget as one attack affix.
@export_range(0.0, 1.0, 0.01) var affix_core_base_share: float = 0.10
## `affix.value = affix_base * (1 + step * rarity) * roll * item_scale(il)` — the rarity
## strength, the §3.2 roll band and the item scale of a CORE affix. Utility affixes use the
## same product without the item scale.
@export_range(0.0, 2.0, 0.01) var affix_rarity_step: float = 0.35
@export_range(0.1, 2.0, 0.01) var affix_roll_min: float = 0.80
@export_range(0.1, 2.0, 0.01) var affix_roll_max: float = 1.20

@export_group("Effective utility caps")
## §3.2: the caps apply to the FINAL aggregated value (base + every affix + unique effects),
## never silently to the stored roll. Critical damage is the only one with a floor above 0.
@export_range(0.0, 1.0, 0.01) var critical_chance_cap: float = 0.50
@export_range(1.0, 5.0, 0.05) var critical_damage_min: float = 1.00
@export_range(1.0, 5.0, 0.05) var critical_damage_max: float = 2.50
@export_range(0.0, 1.0, 0.01) var dodge_cap: float = 0.35
@export_range(0.0, 1.0, 0.01) var life_steal_cap: float = 0.10
@export_range(0.0, 1.0, 0.01) var stun_chance_cap: float = 0.15
## `damage_vs_elite` / `damage_vs_boss` each add up to this, separately (§3.2).
@export_range(0.0, 2.0, 0.01) var tier_damage_cap: float = 0.50
## Equipment may raise movement and attack range by at most this much in total; the base
## movement of 3 and range of 1 are combat rules, not balance parameters (AGENTS.md).
@export_range(0, 8, 1) var movement_bonus_cap: int = 2
@export_range(0, 8, 1) var attack_range_bonus_cap: int = 2

@export_group("Player baseline criticals")
## Used by the analytic work metric. Crit ROLLS stay in [CombatSystem]; these are the
## baseline the equipment modifiers stack on, and enemies never crit (§4.1).
@export_range(0.0, 1.0, 0.01) var base_critical_chance: float = 0.05
@export_range(1.0, 5.0, 0.05) var base_critical_damage: float = 1.50

@export_group("Reference enemies")
## The normal reference enemy every generated enemy is compressed around (§4.2).
@export var reference_enemy_hp: float = 150.0
@export var reference_enemy_attack: float = 22.0
@export var reference_enemy_defense: float = 4.0
@export var reference_enemy_exp: float = 100.0
## The fixed stages 1..`training_stage_limit` enemy: offset 0, variance 1 (§4.2).
@export var training_enemy_hp: float = 130.0
@export var training_enemy_attack: float = 12.0
@export var training_enemy_defense: float = 3.0
@export var training_enemy_exp: float = 100.0

@export_group("Mini Boss")
## Every 10th stage is a Mini Boss, using the normal reference enemy at a frozen group
## basis of c = 4 and only these three multipliers, with offset 0 and variance 1 (§4.3).
@export_range(1, 10, 1) var boss_interval: int = 10
@export_range(1, 8, 1) var boss_base_enemy_count: int = 4
@export var boss_hp_multiplier: float = 6.0
@export var boss_attack_multiplier: float = 1.5
@export var boss_defense_multiplier: float = 1.25

@export_group("Experience")
## §5: `need(L) = round(experience_base * count(L) * G(L))`. The `count(L)` factor reuses the
## encounter-size curve, so the requirement grows with the same shape the kills do.
@export var experience_base: float = 100.0
## §5: `catchup(S, L) = clamp(1 + step * (S - L), min, max)`. It keeps a player who fell
## behind from having to farm forever, and never turns a cleared stage into a locked door:
## replaying an old stage still pays.
@export_range(0.0, 1.0, 0.01) var experience_catchup_step: float = 0.10
@export_range(0.0, 10.0, 0.01) var experience_catchup_min: float = 0.25
@export_range(0.0, 10.0, 0.01) var experience_catchup_max: float = 2.0

@export_group("Gold")
## §6.1: `stage_clear_gold = round(gold_base * G(S))`. One clear pays this once; a stage that
## could be farmed before can still be farmed.
@export var gold_base: float = 50.0

@export_group("Item economy")
## §6.1: `item_level_multiplier = G(il)` replaces the legacy `1.18^(il-1)`, so prices and the
## gold curve share ONE scale. `BaseItemValue` is 30 rather than the legacy 32, which is what
## keeps a normal equipment sale at 5..18 % of the stage's combat Gold.
@export_range(0.0, 10000.0, 1.0) var base_item_value: float = 30.0
@export_range(0.0, 1.0, 0.01) var vendor_sell_multiplier: float = 0.25
## §6.1: `Sell = max(1, floor(min(Value * sell_multiplier, sell_cap_stages *
## StageExpectedSell)))`. The cap clips windfalls; it is not an inflation control.
@export_range(1.0, 1000.0, 1.0) var sell_cap_stages: float = 100.0
## §6.1: `Buys = max(floor(Value * 4), Sell + 1, 1)`.
@export_range(1.0, 100.0, 0.1) var vendor_buy_multiplier: float = 4.0
## `AffixMultiplier = clamp(1 + scale * SUM(roll_ratio * economic_weight), min, max)`.
@export_range(0.0, 1.0, 0.01) var affix_value_scale: float = 0.15
@export_range(1.0, 10.0, 0.1) var affix_multiplier_min: float = 1.0
@export_range(1.0, 10.0, 0.1) var affix_multiplier_max: float = 3.0
## The drop-rarity distribution the §6.1 joint expectation is computed over. It is the §13
## normal-enemy weight table, and it decides both which rarity multiplier and how MANY affixes
## an item carries — which is exactly why the two cannot be averaged separately.
@export var calibration_rarity_weights: Array[float] = [0.60, 0.25, 0.10, 0.04, 0.01, 0.0]
## Mean `roll_ratio` of a rolled affix: the §3.2 roll band is uniform, so half of the 0..1
## normalized band is the expectation.
@export_range(0.0, 1.0, 0.01) var mean_roll_ratio: float = 0.5

@export_group("Sub Heroes")
## §6.2: `investment_level_i = 1 + (hero_level_i - 1) / (pool_size * p_i)` — 24 expected draws
## per hero, so a low-probability hero does not need several times the summons for the same
## growth.
@export_range(1, 64, 1) var sub_hero_pool_size: int = 8
@export_range(1, 64, 1) var sub_hero_draws_per_level: int = 24
## `price_coordinate = min(cap, 1 + owned_draws / draws_per_level)` and
## `summon_cost = max(floor_cost, ceil(gold_base_cost * G(price_coordinate)))`. The cap keeps an
## oversized legacy collection from overflowing the price computation.
@export_range(1, 100000, 1) var summon_price_coordinate_cap: int = 1000
## 10 gold at the coordinate's `G`: the first tier of investment costs about 240 Gold, while the
## 250 floor keeps the early-game gate the shop already has.
@export_range(0.0, 10000.0, 1.0) var summon_gold_coordinate_cost: float = 10.0
@export_range(0, 1000000, 1) var summon_gold_floor: int = 250
## §6.2: the rarity quality multipliers the Sub Hero already shipped with (Common / Rare /
## Legendary). The base damage and the real-time interval stay authored per hero.
@export var sub_hero_quality_multipliers: Array[float] = [1.0, 1.1, 1.2]


## `G(L)^0.40` — the level share of the reference growth.
func get_level_exponent() -> float:
	return 1.0 - equipment_share


## `G(il)^0.60` — the equipment share of the reference growth.
func get_item_exponent() -> float:
	return equipment_share


## The `b_X` coefficient of a stat id, or 0.0 for an unknown id (loudly).
func get_base_stat(stat_id: StringName) -> float:
	match stat_id:
		STAT_HP:
			return base_hp
		STAT_ATTACK:
			return base_attack
		STAT_DEFENSE:
			return base_defense
	push_warning("BalanceProfile: unknown stat id %s" % stat_id)
	return 0.0


## A copy of the per-slot weight column of a stat id, so a caller can never mutate the
## profile through the returned array.
func get_slot_weights(stat_id: StringName) -> Array[float]:
	match stat_id:
		STAT_HP:
			return slot_hp_weights.duplicate()
		STAT_ATTACK:
			return slot_attack_weights.duplicate()
		STAT_DEFENSE:
			return slot_defense_weights.duplicate()
	push_warning("BalanceProfile: unknown stat id %s" % stat_id)
	return []


## The §6.2 quality multiplier of a [enum SubHeroQuality] value, or 1.0 for an unknown one.
func get_sub_hero_quality_multiplier(quality: int) -> float:
	if quality < 0 or quality >= sub_hero_quality_multipliers.size():
		return 1.0
	return maxf(sub_hero_quality_multipliers[quality], 0.0)
