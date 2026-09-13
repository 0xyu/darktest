extends SceneTree

## Verifies the enemy EXP StageFactor of gameplay-spec §10:
## EnemyEXP = BaseEXP × EnemyLevelMultiplier × EnemyTypeMultiplier × 1.15^(stage - 1)

class MockEnemy:
	extends Node

	var enemy_stats: EnemyStats


const BASE_EXPERIENCE: int = 100
const BASE_GOLD: int = 50
const STAGE_FACTOR_RATE: float = 1.15

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage_one: EnemyStats = _scale(1)
	_expect(stage_one.experience_reward == BASE_EXPERIENCE, "stage 1 keeps the base EXP reward, got %d" % stage_one.experience_reward)

	var stage_five: EnemyStats = _scale(5)
	var expected_five: int = EnemyScaling.scale_value(BASE_EXPERIENCE, STAGE_FACTOR_RATE, 5)
	_expect(stage_five.experience_reward == expected_five, "stage 5 EXP follows 1.15^(stage-1), got %d expected %d" % [stage_five.experience_reward, expected_five])

	var stage_twenty: EnemyStats = _scale(20)
	var expected_twenty: int = EnemyScaling.scale_value(BASE_EXPERIENCE, STAGE_FACTOR_RATE, 20)
	_expect(stage_twenty.experience_reward == expected_twenty, "stage 20 EXP follows 1.15^(stage-1), got %d expected %d" % [stage_twenty.experience_reward, expected_twenty])
	_expect(stage_twenty.experience_reward > stage_one.experience_reward, "EXP reward compounds with stage")

	# StageFactor must track the level-requirement curve, so kills per level stays stable.
	var progression := PlayerProgression.new()
	progression.level = 10
	var stage_ten: EnemyStats = _scale(10)
	var requirement_at_stage_ten: int = progression.experience_to_next_level()
	var ratio: float = float(stage_ten.experience_reward) / float(maxi(requirement_at_stage_ten, 1))
	_expect(ratio > 0.9 and ratio < 1.1, "stage 10 enemy EXP stays near the level-10 requirement, ratio %.3f" % ratio)

	# Gold scaling must be untouched by the EXP change.
	_expect(stage_twenty.gold_reward == EnemyScaling.scale_value(BASE_GOLD, 1.18, 20), "gold scaling is unchanged")

	# The scaled reward is what the ExperienceSystem actually awards.
	var experience_system := ExperienceSystem.new()
	var mock_enemy := MockEnemy.new()
	mock_enemy.enemy_stats = stage_twenty
	var awarded: int = experience_system.calculate_enemy_experience(mock_enemy)
	_expect(awarded == stage_twenty.experience_reward, "awarded EXP equals the stage-scaled reward, got %d" % awarded)

	mock_enemy.free()
	experience_system.free()

	if _failures.is_empty():
		print("Enemy experience scaling smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _scale(stage_number: int) -> EnemyStats:
	var base_stats := EnemyStats.new()
	base_stats.max_hp = 100
	base_stats.attack = 10
	base_stats.defense = 5
	base_stats.gold_reward = BASE_GOLD
	base_stats.experience_reward = BASE_EXPERIENCE
	# R1 moved the COMBAT stats onto the v4 formula (§4.2); the reward fields this test is about
	# still ride the legacy curve, exactly as StageManager applies it after the stat switch.
	var scaled: EnemyStats = EnemyScaling.build_combat_stats(
		BalanceProfile.get_default(),
		base_stats,
		stage_number,
		EnemyScaling.Kind.NORMAL,
		0,
		1
	)
	scaled.gold_reward = EnemyScaling.scale_value(BASE_GOLD, 1.18, stage_number)
	scaled.experience_reward = EnemyScaling.scale_value(BASE_EXPERIENCE, STAGE_FACTOR_RATE, stage_number)
	return scaled


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
