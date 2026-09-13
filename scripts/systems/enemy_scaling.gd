class_name EnemyScaling
extends RefCounted

## Turns one enemy's pool base stats into the stats the stage actually spawns (§4.2, §4.3).
##
## The stage-level inputs are applied HERE and only here: [LevelProvider] writes difficulty(S)
## onto the [StageDefinition], [StageManager] freezes the encounter size c when the stage is
## built, and neither of them multiplies anything a second time. The offset, the per-stat
## variance and every group factor are folded into ONE rounding per stat.
##
## Gold and EXP are deliberately NOT part of this switch — they still ride the existing
## `rate^(stage-1)` curve until R2 replaces the reward formulas, which is why
## [method scale_value] is still here.

## Which §4.2 / §4.3 rule set a spawn uses.
enum Kind {
	NORMAL, ## §4.2: compressed pool base, group factor, offset and independent variance
	TRAINING, ## §4.2: fixed training base, offset 0 and variance 1
	MINI_BOSS, ## §4.3: the normal reference enemy on a frozen c = 4 basis, three multipliers
}

## Legacy reward bound, used by [method scale_value] for Gold/EXP until R2.
const MAX_SCALED_VALUE: float = 1000000000000.0


## The three independent per-stat variance factors of §4.2: no variance at all.
static func unity_variance() -> Array[float]:
	return [1.0, 1.0, 1.0]


## The combat stats of one spawn.
##
## `enemy_offset` is the CLAMPED real offset `o = enemy_level - S` (§4.2), not the sampled one:
## the display level and the risk multiplier can never disagree. `encounter_count` is the number
## of enemies the stage opened with, frozen when the stage was built — HP takes `c^-0.60` and
## ATK takes `c^-0.80`, so a bigger group is not simply c times the work, and DEF takes no group
## factor at all. `variance` carries the three independent uniform factors of §4.2 (HP, ATK,
## DEF) and `base_multipliers` the per-entry corrections of the same section, in the same order;
## training stages and Mini Bosses pass [method unity_variance] and no entry corrections.
##
## HP/ATK floor at 1, DEF at 0, and every value saturates at the profile's combat bound (§2).
static func build_combat_stats(
	profile: BalanceProfile,
	base_stats: EnemyStats,
	stage_number: int,
	kind: int,
	enemy_offset: int,
	encounter_count: int,
	variance: Array[float] = [],
	base_multipliers: Array[float] = []
) -> EnemyStats:
	if base_stats == null:
		return null
	var scaled_stats := base_stats.duplicate(true) as EnemyStats
	if profile == null:
		return scaled_stats
	var safe_stage: int = maxi(stage_number, 1)
	# §4.2/§4.3: only a NORMAL spawn carries an offset — "offset 0 and variance 1" is the rule for
	# training stages and Mini Bosses, so the rule is enforced here instead of trusted.
	var safe_offset: int = enemy_offset if kind == Kind.NORMAL else 0
	var count: int = maxi(encounter_count, 1)
	var offset_multiplier: float = BalanceFormulas.enemy_offset_multiplier(profile, safe_offset)

	match kind:
		Kind.TRAINING:
			# §4.2: stages 1..training_stage_limit use the fixed training base with offset 0 and
			# variance 1, so the first stages teach the rules instead of the curve, and every
			# hero fights exactly the same wraith.
			scaled_stats.max_hp = BalanceFormulas.round_stat(profile, profile.training_enemy_hp, 1)
			scaled_stats.attack = BalanceFormulas.round_stat(profile, profile.training_enemy_attack, 1)
			scaled_stats.defense = BalanceFormulas.round_stat(profile, profile.training_enemy_defense, 0)
		Kind.MINI_BOSS:
			# §4.3: the normal REFERENCE enemy on a frozen c = 4 group basis, then only these
			# three multipliers — never "one normal enemy times six full encounter HP". No
			# offset and no variance: a Mini Boss is a fixed, learnable fight.
			var boss_count: int = maxi(profile.boss_base_enemy_count, 1)
			scaled_stats.max_hp = BalanceFormulas.round_stat(
				profile,
				BalanceFormulas.enemy_hp(
					profile,
					safe_stage,
					boss_count,
					profile.reference_enemy_hp * profile.boss_hp_multiplier,
					1.0,
					1.0
				),
				1
			)
			scaled_stats.attack = BalanceFormulas.round_stat(
				profile,
				BalanceFormulas.enemy_attack(
					profile,
					safe_stage,
					boss_count,
					profile.reference_enemy_attack * profile.boss_attack_multiplier,
					1.0,
					1.0
				),
				1
			)
			scaled_stats.defense = BalanceFormulas.round_stat(
				profile,
				BalanceFormulas.enemy_defense(
					profile,
					safe_stage,
					profile.reference_enemy_defense * profile.boss_defense_multiplier,
					1.0,
					1.0
				),
				0
			)
		_:
			scaled_stats.max_hp = BalanceFormulas.round_stat(
				profile,
				BalanceFormulas.enemy_hp(
					profile,
					safe_stage,
					count,
					float(base_stats.max_hp) * _factor_at(base_multipliers, 0),
					offset_multiplier,
					_factor_at(variance, 0)
				),
				1
			)
			scaled_stats.attack = BalanceFormulas.round_stat(
				profile,
				BalanceFormulas.enemy_attack(
					profile,
					safe_stage,
					count,
					float(base_stats.attack) * _factor_at(base_multipliers, 1),
					offset_multiplier,
					_factor_at(variance, 1)
				),
				1
			)
			scaled_stats.defense = BalanceFormulas.round_stat(
				profile,
				BalanceFormulas.enemy_defense(
					profile,
					safe_stage,
					float(base_stats.defense) * _factor_at(base_multipliers, 2),
					offset_multiplier,
					_factor_at(variance, 2)
				),
				0
			)

	scaled_stats.level = maxi(safe_stage + safe_offset, 1)
	scaled_stats.current_hp = scaled_stats.max_hp
	return scaled_stats


## The legacy `rate^(stage-1)` reward curve, still used for Gold and EXP until R2 moves the
## rewards onto `G(S)` (§5, §6).
static func scale_value(base_value: int, growth_rate: float, stage_number: int) -> int:
	if base_value <= 0:
		return 0
	var safe_rate: float = maxf(growth_rate, 0.0)
	var exponent: int = maxi(stage_number - 1, 0)
	var scaled_value: float = float(base_value) * pow(safe_rate, exponent)
	if is_nan(scaled_value) or scaled_value <= 0.0:
		return 0
	if is_inf(scaled_value) or scaled_value > MAX_SCALED_VALUE:
		return int(MAX_SCALED_VALUE)
	return maxi(roundi(scaled_value), 1)


## One entry of a per-stat factor array (variance or per-entry correction). A missing,
## non-finite or non-positive entry means "no factor": a zero multiplier would produce a statless
## enemy, which no rule of §4.2 asks for.
static func _factor_at(factors: Array[float], index: int) -> float:
	if index < 0 or index >= factors.size():
		return 1.0
	var factor: float = factors[index]
	if not is_finite(factor) or factor <= 0.0:
		return 1.0
	return factor
