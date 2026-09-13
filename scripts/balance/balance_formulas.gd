class_name BalanceFormulas
extends RefCounted

## Pure static formulas of the finalized v4 balance contract
## ([code]docs/balance-rework-implementation.md[/code] §2, §3.1, §4).
##
## Every entry point takes the [BalanceProfile] that owns the numbers, reads no node, no
## autoload and no default profile, so the whole contract can be exercised without a
## running game.
##
## Rounding contract (§2): intermediates stay float64 and are never rounded step by step;
## only the final HP/ATK/DEF, damage and reward values become int64. [method roundi] rounds
## half away from zero, which equals the analytic model's `floor(x + 0.5)` for every
## non-negative value this file produces.

## An empty slot contributes a constant 1 to `M_X` (§3.1).
const EMPTY_SLOT_FACTOR: float = 1.0

## The [PlayerStats] field each balance stat id lands in. ONE table: an affix whose id is
## missing here would be rolled, displayed and priced yet never reach combat.
const PLAYER_STAT_FIELDS: Dictionary = {
	BalanceProfile.STAT_HP: &"max_hp",
	BalanceProfile.STAT_ATTACK: &"attack",
	BalanceProfile.STAT_DEFENSE: &"defense",
	&"critical_chance": &"critical_chance",
	&"critical_damage": &"critical_damage",
	&"dodge": &"dodge",
	&"movement": &"movement_points",
	&"attack_range": &"attack_range",
	&"life_steal": &"life_steal",
	&"damage_vs_elite": &"damage_vs_elite",
	&"damage_vs_boss": &"damage_vs_boss",
	&"stun_chance": &"stun_chance",
}


## `G(x) = ((max(x, 1) + 20) / 21)^4` — real coordinates allowed; only stage, character
## level and item level are integers (§2). Non-finite input is rejected: NaN falls back to
## `G(1) = 1`, +inf saturates at [member BalanceProfile.max_combat_value].
static func g(profile: BalanceProfile, coordinate: float) -> float:
	if profile == null or is_zero_approx(profile.growth_divisor):
		return 0.0
	var safe_coordinate: float = 1.0
	if is_finite(coordinate):
		safe_coordinate = maxf(coordinate, 1.0)
	elif coordinate > 0.0:
		return profile.max_combat_value
	var base: float = (safe_coordinate + profile.growth_offset) / profile.growth_divisor
	var scaled: float = pow(base, float(profile.growth_exponent))
	if not is_finite(scaled):
		return profile.max_combat_value
	return scaled


## `r(S) = G(S+1) / G(S) = ((S+21)/(S+20))^4` — the EXACT per-stage multiplier, not the
## first-order approximation `1 + 4/(S+20)` (§1).
static func stage_ratio(profile: BalanceProfile, stage: int) -> float:
	if profile == null or is_zero_approx(profile.growth_divisor):
		return 0.0
	var safe_stage: float = maxf(float(stage), 1.0)
	var base: float = (safe_stage + profile.growth_offset + 1.0) / (safe_stage + profile.growth_offset)
	return pow(base, float(profile.growth_exponent))


## `level_scale(L) = G(L)^0.40`.
static func level_scale(profile: BalanceProfile, level: int) -> float:
	return pow(g(profile, float(level)), profile.get_level_exponent())


## `item_scale(il) = G(il)^0.60`.
static func item_scale(profile: BalanceProfile, item_level: int) -> float:
	return pow(g(profile, float(item_level)), profile.get_item_exponent())


## `count(S) = clamp(1 + floor((S-1)/3), 1, 4)` — the encounter size frozen at stage build.
static func enemy_count(profile: BalanceProfile, stage: int) -> int:
	if profile == null:
		return 1
	var safe_stage: int = maxi(stage, 1)
	var interval: int = maxi(profile.enemy_count_interval, 1)
	var counted: int = profile.base_enemy_count + (safe_stage - 1) / interval
	return clampi(counted, 1, maxi(profile.max_enemy_count, 1))


## `difficulty(S)`: two continuous ramps, then flat (§2).
static func difficulty(profile: BalanceProfile, stage: int) -> float:
	if profile == null:
		return 1.0
	var safe_stage: float = maxf(float(stage), 1.0)
	var mid_stage: float = maxf(float(profile.difficulty_mid_stage), 2.0)
	if safe_stage <= mid_stage:
		var ramp_span: float = maxf(mid_stage - 1.0, 1.0)
		return lerpf(profile.difficulty_start, profile.difficulty_mid, (safe_stage - 1.0) / ramp_span)
	var cap_stage: float = maxf(float(profile.difficulty_cap_stage), mid_stage + 1.0)
	if safe_stage >= cap_stage:
		return profile.difficulty_cap
	return lerpf(profile.difficulty_mid, profile.difficulty_cap, (safe_stage - mid_stage) / (cap_stage - mid_stage))


## `offset_mult = 1 + 0.06 * o`, applied on the CLAMPED real enemy-level offset (§4.2).
static func enemy_offset_multiplier(profile: BalanceProfile, offset: int) -> float:
	if profile == null:
		return 1.0
	return 1.0 + profile.enemy_offset_step * float(offset)


## Stages 1..`training_stage_limit` use the fixed training base (§4.2).
static func is_training_stage(profile: BalanceProfile, stage: int) -> bool:
	if profile == null:
		return false
	return maxi(stage, 1) <= profile.training_stage_limit


## `HP = base_hp * G(S) * c^-0.60 * difficulty(S) * offset_mult * variance` (§4.2).
static func enemy_hp(
	profile: BalanceProfile,
	stage: int,
	enemy_count_value: int,
	base_hp: float,
	offset_multiplier: float,
	variance: float
) -> float:
	return _enemy_stat(
		profile,
		stage,
		enemy_count_value,
		base_hp * offset_multiplier * variance,
		profile.enemy_hp_count_exponent
	)


## `ATK = base_atk * G(S) * c^-0.80 * difficulty(S) * offset_mult * variance` (§4.2).
static func enemy_attack(
	profile: BalanceProfile,
	stage: int,
	enemy_count_value: int,
	base_attack: float,
	offset_multiplier: float,
	variance: float
) -> float:
	return _enemy_stat(
		profile,
		stage,
		enemy_count_value,
		base_attack * offset_multiplier * variance,
		profile.enemy_attack_count_exponent
	)


## `DEF = base_def * G(S) * difficulty(S) * offset_mult * variance` — no group discount and
## no count factor (§4.2).
static func enemy_defense(
	profile: BalanceProfile,
	stage: int,
	base_defense: float,
	offset_multiplier: float,
	variance: float
) -> float:
	return _enemy_stat(profile, stage, 1, base_defense * offset_multiplier * variance, 0.0)


## Final int64 stat: HP/ATK floor at 1, DEF at 0, and both saturate at
## [member BalanceProfile.max_combat_value] (§2).
static func round_stat(profile: BalanceProfile, value: float, minimum: int) -> int:
	if profile == null:
		return maxi(minimum, 0)
	var rounded: int = roundi(sanitize(profile, value))
	return clampi(rounded, minimum, int(profile.max_combat_value))


## Rejects NaN/Infinity and clamps negatives to 0 before any arithmetic (§2).
static func sanitize(profile: BalanceProfile, value: float) -> float:
	if is_nan(value):
		return 0.0
	if not is_finite(value):
		return profile.max_combat_value if profile != null and value > 0.0 else 0.0
	return maxf(value, 0.0)


## A combat value inside the supported range.
static func is_valid_value(profile: BalanceProfile, value: float) -> bool:
	if profile == null or not is_finite(value):
		return false
	return absf(value) <= profile.max_combat_value


## A persisted Gold/EXP value inside its own, much higher ceiling (§2).
static func is_valid_persistent_value(profile: BalanceProfile, value: float) -> bool:
	if profile == null or not is_finite(value):
		return false
	return absf(value) <= profile.max_persistent_value


## §4.1 armor: `A / (1 + D/A)`. `A <= 0` returns 0; negative or non-finite inputs are
## clamped first, so no integer `A²` can overflow and no NaN enters the damage chain.
static func armor_damage(profile: BalanceProfile, attack: float, defense: float) -> float:
	if profile == null:
		return 0.0
	var safe_attack: float = sanitize(profile, attack)
	if safe_attack <= 0.0:
		return 0.0
	var safe_defense: float = sanitize(profile, defense)
	var raw: float = safe_attack / (1.0 + safe_defense / safe_attack)
	return raw if is_finite(raw) else 0.0


## §4.1 the ONE damage entry: `max(1, round(modified * (critical ? critical_damage : 1)))`
## with `modified = armor * skill_multiplier * applicable_damage_modifiers`.
##
## A normal attack passes `skill_multiplier = 1`. Negative multiplier inputs clamp to 0 and
## therefore land on the minimum-1 floor, and a saturated chain returns
## [member BalanceProfile.max_combat_value] instead of an overflowing int64.
static func resolve_damage(
	profile: BalanceProfile,
	attack: float,
	defense: float,
	skill_multiplier: float = 1.0,
	damage_modifiers: float = 1.0,
	is_critical: bool = false,
	critical_damage: float = 1.0
) -> int:
	if profile == null:
		return 1
	var modified: float = armor_damage(profile, attack, defense)
	modified *= sanitize(profile, skill_multiplier)
	modified *= sanitize(profile, damage_modifiers)
	if is_critical:
		modified *= maxf(critical_damage, 1.0)
	if not is_finite(modified):
		return int(profile.max_combat_value)
	return clampi(roundi(modified), 1, int(profile.max_combat_value))


## Mean critical factor of the player baseline: 5 % / 150 % → 1.025. Enemies never crit,
## so this multiplies the player's damage only (§4.1).
static func expected_critical_multiplier(profile: BalanceProfile) -> float:
	if profile == null:
		return 1.0
	var chance: float = clampf(profile.base_critical_chance, 0.0, 1.0)
	return 1.0 + chance * maxf(profile.base_critical_damage - 1.0, 0.0)


## `rarity_core(r) = 1 + 0.08*r` (§3.1).
static func rarity_core(profile: BalanceProfile, rarity: int) -> float:
	if profile == null:
		return 1.0
	return 1.0 + profile.rarity_core_step * float(maxi(rarity, 0))


## `slot_factor(s)`: `rarity_core(r) * item_scale(il)` for an equipped item. An EMPTY slot
## uses [constant EMPTY_SLOT_FACTOR] instead.
static func slot_factor(profile: BalanceProfile, rarity: int, item_level: int) -> float:
	return rarity_core(profile, rarity) * item_scale(profile, item_level)


## Seven identical equipped slots — the §3.1 reference fixture, not a random drop set.
static func full_slot_factors(profile: BalanceProfile, rarity: int, item_level: int) -> Array[float]:
	var factors: Array[float] = []
	for slot in range(BalanceProfile.SLOT_COUNT):
		factors.append(slot_factor(profile, rarity, item_level))
	return factors


## `M_X = sum_s(w_X,s * slot_factor(s))` — every slot contributes its OWN item level and
## rarity, never an average item level (§3.1). Slots missing from `slot_factors` count as
## empty.
static func equipment_multiplier(
	profile: BalanceProfile,
	stat_id: StringName,
	slot_factors: Array[float]
) -> float:
	if profile == null:
		return 0.0
	var weights: Array[float] = profile.get_slot_weights(stat_id)
	var total: float = 0.0
	for slot in range(BalanceProfile.SLOT_COUNT):
		var weight: float = weights[slot] if slot < weights.size() else 0.0
		var factor: float = slot_factors[slot] if slot < slot_factors.size() else EMPTY_SLOT_FACTOR
		total += weight * factor
	return total


## `effective_X = level_scale(L) * (b_X * M_X + Flat_X)`, unrounded. `flat_total` already
## carries `item_scale` (§3.1) and is added exactly once.
static func player_stat_value(
	profile: BalanceProfile,
	stat_id: StringName,
	level: int,
	multiplier: float,
	flat_total: float = 0.0
) -> float:
	if profile == null:
		return 0.0
	return level_scale(profile, level) * (profile.get_base_stat(stat_id) * multiplier + flat_total)


static func _enemy_stat(
	profile: BalanceProfile,
	stage: int,
	enemy_count_value: int,
	base_with_modifiers: float,
	count_exponent: float
) -> float:
	if profile == null:
		return 0.0
	var safe_count: float = float(maxi(enemy_count_value, 1))
	var safe_stage: int = maxi(stage, 1)
	var value: float = base_with_modifiers * g(profile, float(safe_stage))
	value *= pow(safe_count, count_exponent)
	value *= difficulty(profile, safe_stage)
	if not is_finite(value):
		return profile.max_combat_value
	return maxf(value, 0.0)


## Whether a stat id is one of the three core stats, whose affix carries `item_scale` (§3.2).
static func is_core_stat(stat_id: StringName) -> bool:
	return stat_id in BalanceProfile.STAT_IDS


## §3.2 `affix.value = affix_base * (1 + rarity_step * r) * roll * item_scale(il)` for a CORE
## affix, and the same product WITHOUT the item scale for every utility affix: a probability or
## an extra movement point must not grow with the item level. `affix_base` comes from the affix
## catalogue, so this function owns the scaling while the catalogue owns the weights.
static func affix_value(
	profile: BalanceProfile,
	affix_base: float,
	item_level: int,
	rarity: int,
	roll: float,
	is_core: bool
) -> float:
	if profile == null:
		return 0.0
	var value: float = affix_base * (1.0 + profile.affix_rarity_step * float(maxi(rarity, 0)))
	value *= roll
	if is_core:
		value *= item_scale(profile, item_level)
	return maxf(value, 0.0)


## The hero's whole aggregated stat block (§3.1, §3.2), keyed by the [PlayerStats] field each
## stat id lands in ([constant PLAYER_STAT_FIELDS]).
##
## `slot_factors` carries one entry per [EquipmentSlot] — `rarity_core(r) * item_scale(il)` for
## an equipped item and [constant EMPTY_SLOT_FACTOR] for an empty one — and `flat_totals`
## carries the affix sums keyed by balance stat id, already scaled by `item_scale` at roll time.
## Every slot contributes its OWN item level; a single average item level is never substituted
## (§3.1). `base_stats` is the hero's authored stat block and supplies the base of the utility
## stats that are gameplay rules rather than balance numbers (movement 3, attack range 1).
##
## Core stats round exactly once, at the end, with the floors of §2 (HP/ATK ≥ 1, DEF ≥ 0). The
## §3.2 caps are applied HERE and only here — to the effective value, never to a stored roll.
static func stat_block(
	profile: BalanceProfile,
	level: int,
	slot_factors: Array[float],
	flat_totals: Dictionary = {},
	base_stats: Dictionary = {}
) -> Dictionary:
	if profile == null:
		return {}
	var hp: float = player_stat_value(
		profile,
		BalanceProfile.STAT_HP,
		level,
		equipment_multiplier(profile, BalanceProfile.STAT_HP, slot_factors),
		float(flat_totals.get(BalanceProfile.STAT_HP, 0.0))
	)
	var attack: float = player_stat_value(
		profile,
		BalanceProfile.STAT_ATTACK,
		level,
		equipment_multiplier(profile, BalanceProfile.STAT_ATTACK, slot_factors),
		float(flat_totals.get(BalanceProfile.STAT_ATTACK, 0.0))
	)
	var defense: float = player_stat_value(
		profile,
		BalanceProfile.STAT_DEFENSE,
		level,
		equipment_multiplier(profile, BalanceProfile.STAT_DEFENSE, slot_factors),
		float(flat_totals.get(BalanceProfile.STAT_DEFENSE, 0.0))
	)
	return {
		&"max_hp": round_stat(profile, hp, 1),
		&"attack": round_stat(profile, attack, 1),
		&"defense": round_stat(profile, defense, 0),
		# Critical chance and damage stack on the §3.2 baseline of the profile; every other
		# utility stat stacks on the base the hero was authored with.
		&"critical_chance": clampf(
			profile.base_critical_chance + float(flat_totals.get(&"critical_chance", 0.0)),
			0.0,
			profile.critical_chance_cap
		),
		&"critical_damage": clampf(
			profile.base_critical_damage + float(flat_totals.get(&"critical_damage", 0.0)),
			profile.critical_damage_min,
			profile.critical_damage_max
		),
		&"dodge": clampf(
			_base_stat(base_stats, &"dodge") + float(flat_totals.get(&"dodge", 0.0)),
			0.0,
			profile.dodge_cap
		),
		&"life_steal": clampf(
			_base_stat(base_stats, &"life_steal") + float(flat_totals.get(&"life_steal", 0.0)),
			0.0,
			profile.life_steal_cap
		),
		&"damage_vs_elite": clampf(
			_base_stat(base_stats, &"damage_vs_elite") + float(flat_totals.get(&"damage_vs_elite", 0.0)),
			0.0,
			profile.tier_damage_cap
		),
		&"damage_vs_boss": clampf(
			_base_stat(base_stats, &"damage_vs_boss") + float(flat_totals.get(&"damage_vs_boss", 0.0)),
			0.0,
			profile.tier_damage_cap
		),
		&"stun_chance": clampf(
			_base_stat(base_stats, &"stun_chance") + float(flat_totals.get(&"stun_chance", 0.0)),
			0.0,
			profile.stun_chance_cap
		),
		# Movement and attack range are integers: the equipment INCREMENT is capped, the base is
		# a combat rule, and the §3.2 floors are applied after the addition.
		&"movement_points": maxi(
			roundi(_base_stat(base_stats, &"movement_points"))
			+ mini(roundi(float(flat_totals.get(&"movement", 0.0))), profile.movement_bonus_cap),
			0
		),
		&"attack_range": maxi(
			roundi(_base_stat(base_stats, &"attack_range"))
			+ mini(roundi(float(flat_totals.get(&"attack_range", 0.0))), profile.attack_range_bonus_cap),
			1
		),
	}


## §3.3 HP projection across a rebuild. An unchanged maximum keeps the current HP exactly where
## it was — that is what makes a repeated recompute a no-op — and a moved maximum keeps the same
## FRACTION of it, floored, never above the new maximum. A dead hero stays dead.
##
## The result may be 0 for a living hero whose maximum shrank far enough (the fraction floors
## away): the caller must REFUSE that change instead of healing or killing the hero, which is
## why nothing here patches the value up to 1.
static func project_current_hp(previous_max_hp: int, previous_current_hp: int, new_max_hp: int) -> int:
	if previous_current_hp <= 0:
		return 0
	if previous_max_hp <= 0 or new_max_hp == previous_max_hp:
		return previous_current_hp
	var projected: float = float(previous_current_hp) * float(new_max_hp) / float(previous_max_hp)
	if not is_finite(projected):
		return 0
	return clampi(floori(projected), 0, maxi(new_max_hp, 0))


static func _base_stat(base_stats: Dictionary, field: StringName) -> float:
	return float(base_stats.get(field, 0.0))
