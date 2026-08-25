class_name EnemyScaling
extends RefCounted

## Applies stage-based exponential growth to a fresh copy of enemy stats.
const MAX_SCALED_VALUE: float = 1000000000000.0


static func scale_stats(
	base_stats: EnemyStats,
	stage_number: int,
	hp_growth_rate: float,
	attack_growth_rate: float,
	defense_growth_rate: float,
	gold_growth_rate: float
) -> EnemyStats:
	var scaled_stats := base_stats.duplicate(true) as EnemyStats
	var safe_stage: int = maxi(stage_number, 1)
	scaled_stats.level = maxi(base_stats.level, 1)
	scaled_stats.max_hp = scale_value(base_stats.max_hp, hp_growth_rate, safe_stage)
	scaled_stats.current_hp = scaled_stats.max_hp
	scaled_stats.attack = scale_value(base_stats.attack, attack_growth_rate, safe_stage)
	scaled_stats.defense = scale_value(base_stats.defense, defense_growth_rate, safe_stage)
	scaled_stats.gold_reward = scale_value(base_stats.gold_reward, gold_growth_rate, safe_stage)
	scaled_stats.clamp_current_hp()
	return scaled_stats


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
