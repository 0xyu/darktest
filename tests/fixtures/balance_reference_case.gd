class_name BalanceReferenceCase
extends RefCounted

## Analytic reference case of the v4 balance contract
## ([code]docs/balance-rework-implementation.md[/code] §3.1 fixture, §4.2, §4.3).
##
## L = il = S, all seven slots equipped with Common (rarity 0) items of item level S and no
## affixes, the NORMAL reference enemy, offset = 0 and variance = 1. Under those conditions
## `M_X = G(S)^0.6` and `Flat_X = 0`, so every player stat is exactly `b_X × G(S)`: the case
## isolates the SCALE. It is a mathematical fixture, NOT the mean of random drops, and it
## says nothing about loot quality (contract §3.1).
##
## Every number is read from the injected [BalanceProfile], so re-tuning the profile moves
## this fixture with it instead of leaving a second copy of the curve in a test, in a tool
## or in a document table. It deliberately uses the reference enemy for EVERY stage — the
## stages 1..training_stage_limit base is [method build_training] — so this case stays
## comparable with the §7 document model.
##
## `build()` returns a flat Dictionary:
## [code]stage, is_boss, count, encounter_count, g, level_scale, item_scale,
## player_hp, player_attack, player_defense, player_hp_int, player_attack_int,
## player_defense_int, enemy_hp, enemy_attack, enemy_defense, enemy_hp_int,
## enemy_attack_int, enemy_defense_int, damage_dealt, damage_received,
## work, survival, actions, hp_remaining, cleared, player_defeated[/code]

## M2 acceptance bands (§8). They live here, not in a test and not in the tool, so the
## assertion and the generated table report cannot drift apart.
const WORK_MIN: float = 2.0
## S3..9.
const WORK_MAX_EARLY: float = 6.0
## S10..1000.
const WORK_MAX_LATE: float = 8.0
const SURVIVAL_MIN: float = 4.0
const SURVIVAL_MAX: float = 9.0
## S10..1000 non-boss reference encounters must clear in exactly this many player actions.
const ACTIONS_LATE: int = 8
const BOSS_ACTIONS_MIN: int = 8
const BOSS_ACTIONS_MAX: int = 12
## An encounter that is not cleared within this many player actions counts as a failure
## (§8 M5); the reference case is far below it.
const MAX_SIMULATED_ACTIONS: int = 100
const COMMON_RARITY: int = EquipmentRarity.COMMON
## offset = 0 and variance = 1: the reference case carries no enemy-level risk (§4.2).
const NEUTRAL_VARIANCE: float = 1.0


## The §3.1/§4.2 reference case: reference enemy, offset 0, variance 1, L = il = S.
static func build(profile: BalanceProfile, stage: int, is_boss: bool = false) -> Dictionary:
	return _build(
		profile,
		stage,
		profile.reference_enemy_hp,
		profile.reference_enemy_attack,
		profile.reference_enemy_defense,
		is_boss
	)


## The same case on the fixed stages 1..training_stage_limit base (§4.2). Offset and
## variance stay neutral, so the row shows the training base only.
static func build_training(profile: BalanceProfile, stage: int) -> Dictionary:
	return _build(
		profile,
		stage,
		profile.training_enemy_hp,
		profile.training_enemy_attack,
		profile.training_enemy_defense,
		false
	)


## `work = total_enemy_hp / (player_damage_per_action * E[crit])` — the abstract player-action
## cost of the encounter (§3 of the rebase document). `INF` when the player cannot damage it.
static func encounter_work(
	profile: BalanceProfile,
	total_enemy_hp: float,
	player_damage: float
) -> float:
	var effective_damage: float = player_damage * BalanceFormulas.expected_critical_multiplier(profile)
	if effective_damage <= 0.0:
		return INF
	return total_enemy_hp / effective_damage


## `survival = player_hp / incoming_damage_per_player_action` — the number of full enemy
## volleys a static player survives (§3 of the rebase document).
static func static_survival(player_hp: float, incoming_damage: float) -> float:
	if incoming_damage <= 0.0:
		return INF
	return player_hp / incoming_damage


## M3 semantics on a static board: the player attacks once per action, a defeated enemy
## never retaliates, every SURVIVING enemy attacks once after each player action, and there
## are no criticals, Sub Heroes, healing or distance (§8 M3).
static func simulate_player_actions(
	player_hp: int,
	damage_dealt: int,
	enemy_hp: int,
	damage_received: int,
	enemy_count: int
) -> Dictionary:
	var hp: int = player_hp
	var living: int = maxi(enemy_count, 0)
	var full_hp: int = maxi(enemy_hp, 1)
	var current_hp: int = full_hp
	var dealt: int = maxi(damage_dealt, 1)
	var received: int = maxi(damage_received, 0)
	var actions: int = 0
	while living > 0 and hp > 0 and actions < MAX_SIMULATED_ACTIONS:
		current_hp -= dealt
		actions += 1
		if current_hp <= 0:
			living -= 1
			current_hp = full_hp
		hp -= living * received
	return {"actions": actions, "hp": hp, "cleared": living <= 0 and hp > 0}


## Upper end of the encounter-work band for a stage: the band tightens before
## `difficulty_mid_stage` (§8 M2).
static func get_work_max(profile: BalanceProfile, stage: int) -> float:
	return WORK_MAX_EARLY if maxi(stage, 1) < profile.difficulty_mid_stage else WORK_MAX_LATE


## The encounter-work band membership of one reference row.
static func is_work_in_band(profile: BalanceProfile, stage: int, work: float) -> bool:
	return work >= WORK_MIN and work <= get_work_max(profile, stage)


## The static-survival band membership of one reference row.
static func is_survival_in_band(survival: float) -> bool:
	return survival >= SURVIVAL_MIN and survival <= SURVIVAL_MAX


static func _build(
	profile: BalanceProfile,
	stage: int,
	base_hp: float,
	base_attack: float,
	base_defense: float,
	is_boss: bool
) -> Dictionary:
	var safe_stage: int = maxi(stage, 1)
	var slot_factors: Array[float] = BalanceFormulas.full_slot_factors(
		profile,
		COMMON_RARITY,
		safe_stage
	)
	var player_hp: float = _player_stat(profile, BalanceProfile.STAT_HP, safe_stage, slot_factors)
	var player_attack: float = _player_stat(profile, BalanceProfile.STAT_ATTACK, safe_stage, slot_factors)
	var player_defense: float = _player_stat(profile, BalanceProfile.STAT_DEFENSE, safe_stage, slot_factors)

	# §4.3: a Mini Boss uses the frozen group basis c = 4 for its own stats, then fights as a
	# single actor — it is not a normal encounter with six times the full encounter HP.
	var count: int = profile.boss_base_enemy_count if is_boss else BalanceFormulas.enemy_count(profile, safe_stage)
	var encounter_count: int = 1 if is_boss else count
	var offset_multiplier: float = BalanceFormulas.enemy_offset_multiplier(profile, 0)
	var enemy_hp: float = BalanceFormulas.enemy_hp(
		profile,
		safe_stage,
		count,
		base_hp,
		offset_multiplier,
		NEUTRAL_VARIANCE
	)
	var enemy_attack: float = BalanceFormulas.enemy_attack(
		profile,
		safe_stage,
		count,
		base_attack,
		offset_multiplier,
		NEUTRAL_VARIANCE
	)
	var enemy_defense: float = BalanceFormulas.enemy_defense(
		profile,
		safe_stage,
		base_defense,
		offset_multiplier,
		NEUTRAL_VARIANCE
	)
	if is_boss:
		enemy_hp *= profile.boss_hp_multiplier
		enemy_attack *= profile.boss_attack_multiplier
		enemy_defense *= profile.boss_defense_multiplier

	# Static metrics use the unrounded floats; the discrete simulation uses the final
	# int64 stats, exactly like the runtime (§2).
	var work: float = encounter_work(
		profile,
		float(encounter_count) * enemy_hp,
		BalanceFormulas.armor_damage(profile, player_attack, enemy_defense)
	)
	var survival: float = static_survival(
		player_hp,
		float(encounter_count) * BalanceFormulas.armor_damage(profile, enemy_attack, player_defense)
	)

	var player_hp_int: int = BalanceFormulas.round_stat(profile, player_hp, 1)
	var player_attack_int: int = BalanceFormulas.round_stat(profile, player_attack, 1)
	var player_defense_int: int = BalanceFormulas.round_stat(profile, player_defense, 0)
	var enemy_hp_int: int = BalanceFormulas.round_stat(profile, enemy_hp, 1)
	var enemy_attack_int: int = BalanceFormulas.round_stat(profile, enemy_attack, 1)
	var enemy_defense_int: int = BalanceFormulas.round_stat(profile, enemy_defense, 0)
	var damage_dealt: int = maxi(
		roundi(BalanceFormulas.armor_damage(profile, float(player_attack_int), float(enemy_defense_int))),
		1
	)
	var damage_received: int = maxi(
		roundi(BalanceFormulas.armor_damage(profile, float(enemy_attack_int), float(player_defense_int))),
		1
	)
	var simulation: Dictionary = simulate_player_actions(
		player_hp_int,
		damage_dealt,
		enemy_hp_int,
		damage_received,
		encounter_count
	)
	var remaining_hp: int = int(simulation["hp"])
	return {
		"stage": safe_stage,
		"is_boss": is_boss,
		"count": count,
		"encounter_count": encounter_count,
		"g": BalanceFormulas.g(profile, float(safe_stage)),
		"level_scale": BalanceFormulas.level_scale(profile, safe_stage),
		"item_scale": BalanceFormulas.item_scale(profile, safe_stage),
		"player_hp": player_hp,
		"player_attack": player_attack,
		"player_defense": player_defense,
		"player_hp_int": player_hp_int,
		"player_attack_int": player_attack_int,
		"player_defense_int": player_defense_int,
		"enemy_hp": enemy_hp,
		"enemy_attack": enemy_attack,
		"enemy_defense": enemy_defense,
		"enemy_hp_int": enemy_hp_int,
		"enemy_attack_int": enemy_attack_int,
		"enemy_defense_int": enemy_defense_int,
		"damage_dealt": damage_dealt,
		"damage_received": damage_received,
		"work": work,
		"survival": survival,
		"actions": int(simulation["actions"]),
		"hp_remaining": float(remaining_hp) / float(maxi(player_hp_int, 1)),
		"cleared": bool(simulation["cleared"]),
		"player_defeated": remaining_hp <= 0,
	}


static func _player_stat(
	profile: BalanceProfile,
	stat_id: StringName,
	level: int,
	slot_factors: Array[float]
) -> float:
	var multiplier: float = BalanceFormulas.equipment_multiplier(profile, stat_id, slot_factors)
	return BalanceFormulas.player_stat_value(profile, stat_id, level, multiplier)
