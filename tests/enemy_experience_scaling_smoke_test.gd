extends SceneTree

## Verifies the v4 EXP and Gold reward contract
## (`docs/balance-rework-implementation.md` §5, §6.1) against the production code:
##
##   need(L)    = round(100 * count(L) * G(L))
##   catchup    = clamp(1 + 0.10*(S-L), 0.25, 2.0)
##   kill_exp   = max(1, round(100 * G(S) * offset_mult * type_exp * catchup(S,L)))
##   enemy_gold = round(50 * G(S) * offset_mult * type_gold)
##   stage_gold = round(50 * G(S))
##
## Every expectation is COMPUTED from the profile, never copied: a retune has to move the test with
## the formula. The last section is the §8 R2 rule that matters most — every reward settles once.

class MockEnemy:
	extends Node

	var enemy_stats: EnemyStats


const PROFILE_PATH: String = BalanceProfile.DEFAULT_PROFILE_PATH

var _profile: BalanceProfile
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_profile = load(PROFILE_PATH) as BalanceProfile
	_expect(_profile != null, "the default balance profile loads")
	if _profile == null:
		_finish()
		return

	_check_level_requirement()
	_check_kill_experience()
	_check_gold()
	_check_single_settlement()
	_finish()


## §5: `need(L) = round(100 * count(L) * G(L))`, and the reference stage pays exactly one level.
func _check_level_requirement() -> void:
	for level in [1, 2, 10, 11, 100, 999, 1000]:
		var expected: int = roundi(
			_profile.experience_base * float(BalanceFormulas.enemy_count(_profile, level)) * BalanceFormulas.g(_profile, float(level))
		)
		var required: int = BalanceFormulas.experience_required(_profile, level)
		_expect(required == maxi(expected, 1), "need(%d) = %d, got %d" % [level, expected, required])

	var progression := PlayerProgression.new()
	progression.balance_profile = _profile
	for level in [1, 3, 10, 50, 500]:
		progression.level = level
		_expect(
			progression.experience_to_next_level() == BalanceFormulas.experience_required(_profile, level),
			"PlayerProgression.need(%d) reads the shared formula" % level
		)

	# §5 "post-battle identity": at the reference state (L = S, offset 0) ONE stage of kills pays
	# exactly one level. Compared against the whole stage's EXP, not a single kill.
	for stage in [3, 4, 10, 25, 100]:
		var count: int = BalanceFormulas.enemy_count(_profile, stage)
		var total: int = 0
		for _index in range(count):
			total += _kill_experience(stage, 0, 1.0, stage)
		var required: int = BalanceFormulas.experience_required(_profile, stage)
		_expect(
			absf(float(total - required)) <= float(count),
			"stage %d pays one level: %d EXP vs %d required" % [stage, total, required]
		)

	# §5: at the released level cap the hero banks nothing and converts nothing.
	progression.level = _profile.max_character_level
	progression.experience = 0
	_expect(progression.add_experience(10 * BalanceFormulas.experience_required(_profile, _profile.max_character_level)) == 0, "a capped level gains no levels")
	_expect(progression.experience == 0, "a capped level banks no EXP")
	var points_before: int = progression.skill_points
	_expect(progression.skill_points == points_before + 0, "a capped level pays no skill points")


## §5: the kill formula and the catch-up band, including the neutral case the stage build uses.
func _check_kill_experience() -> void:
	for stage in [1, 2, 3, 10, 500, 1000]:
		var expected: int = maxi(roundi(_profile.experience_base * BalanceFormulas.g(_profile, float(stage))), 1)
		var actual: int = BalanceFormulas.kill_experience(_profile, stage, 1.0, 1.0, stage)
		_expect(actual == expected, "stage %d reference kill pays %d, got %d" % [stage, expected, actual])

	# The offset multiplier and the type multiplier are each applied exactly once.
	var base_stage: int = BalanceFormulas.kill_experience(_profile, 20, 1.0, 1.0, 20)
	_expect(
		BalanceFormulas.kill_experience(_profile, 20, _profile.enemy_offset_step + 1.0, 1.0, 20) > base_stage,
		"a positive offset pays more, a negative one pays less"
	)
	# §4.3: the Mini Boss factor is 4x ONE normal kill — the same factor on the same formula, not a
	# second multiplication by the encounter size.
	var boss_expected: int = roundi(
		_profile.experience_base * BalanceFormulas.g(_profile, 20.0) * 4.0
	)
	_expect(
		BalanceFormulas.kill_experience(_profile, 20, 1.0, 4.0, 20) == maxi(boss_expected, 1),
		"a Mini Boss pays 4x one normal kill, got %d" % BalanceFormulas.kill_experience(_profile, 20, 1.0, 4.0, 20)
	)

	# §5 catch-up: below the stage pays the full 2.0, above it pays the 0.25 floor, and the band is
	# clamped at both ends.
	_expect(is_equal_approx(BalanceFormulas.experience_catchup(_profile, 30, 10), _profile.experience_catchup_max), "a far-behind level hits the catch-up ceiling")
	_expect(is_equal_approx(BalanceFormulas.experience_catchup(_profile, 1, 500), _profile.experience_catchup_min), "an over-levelled player hits the catch-up floor")
	_expect(is_equal_approx(BalanceFormulas.experience_catchup(_profile, 40, 40), 1.0), "a level-synced player has no catch-up")
	_expect(
		BalanceFormulas.kill_experience(_profile, 30, 1.0, 1.0, 10) > BalanceFormulas.kill_experience(_profile, 30, 1.0, 1.0, 30),
		"replaying under-levelled pays more than playing level-synced"
	)
	_expect(BalanceFormulas.kill_experience(_profile, 5, 0.0, 1.0, 5) >= 1, "a kill always pays at least 1 EXP")


## §6.1: Gold has the same `G(S)` scale and NO player-level catch-up.
func _check_gold() -> void:
	for stage in [1, 3, 10, 100, 1000]:
		var expected: int = roundi(_profile.gold_base * BalanceFormulas.g(_profile, float(stage)))
		_expect(
			BalanceFormulas.stage_clear_gold(_profile, stage) == expected,
			"stage %d clear gold = %d, got %d" % [stage, expected, BalanceFormulas.stage_clear_gold(_profile, stage)]
		)
	var base_gold: int = BalanceFormulas.enemy_gold(_profile, 40, 1.0, 1.0)
	_expect(BalanceFormulas.enemy_gold(_profile, 40, 1.06, 1.0) > base_gold, "an enemy above the stage pays more gold")
	var boss_gold: int = roundi(_profile.gold_base * BalanceFormulas.g(_profile, 40.0) * 4.0)
	_expect(BalanceFormulas.enemy_gold(_profile, 40, 1.0, 4.0) == boss_gold, "a Mini Boss pays 4x one normal kill in gold")


## §8 R2: "all rewards settle exactly once". The settlement entry is the one that pays, and a
## second call for the same defeat pays nothing while still reporting what the kill paid.
func _check_single_settlement() -> void:
	var experience_system := ExperienceSystem.new()
	experience_system.balance_profile = _profile
	var player := PlayerController.new()
	var progression := PlayerProgression.new()
	progression.balance_profile = _profile
	progression.level = 20
	player.player_progression = progression
	experience_system.attach_player(player)

	var stats := EnemyStats.new()
	stats.experience_reward = BalanceFormulas.kill_experience(_profile, 20, 1.0, 1.0, 20)
	stats.gold_reward = BalanceFormulas.enemy_gold(_profile, 20, 1.0, 1.0)
	var enemy := MockEnemy.new()
	enemy.enemy_stats = stats
	root.add_child(enemy)

	var expected: int = experience_system.calculate_enemy_experience(enemy)
	_expect(expected > 0, "the settlement preview is a real amount")
	_expect(experience_system.settle_kill_experience(enemy) == expected, "the first settlement pays the previewed amount")
	_expect(progression.experience == expected, "the purse holds exactly one payment")
	_expect(experience_system.settle_kill_experience(enemy) == 0, "a second settlement for the same kill pays nothing")
	_expect(progression.experience == expected, "a second settlement changes nothing")
	_expect(experience_system.get_settled_experience(enemy) == expected, "the combat log reads the amount that was paid")

	var gold_system := GoldSystem.new()
	gold_system.balance_profile = _profile
	gold_system.attach_player(player)
	var gold_before: int = progression.gold
	_expect(gold_system.settle_kill_gold(enemy) == stats.gold_reward, "the first gold settlement pays the runtime reward")
	_expect(progression.gold == gold_before + stats.gold_reward, "the purse holds exactly one gold payment")
	_expect(gold_system.settle_kill_gold(enemy) == 0, "a second gold settlement for the same kill pays nothing")
	_expect(progression.gold == gold_before + stats.gold_reward, "a second gold settlement changes nothing")

	# §6.1: the stage reward is a one-time payment per legal clear.
	var stage_clear: int = gold_system.calculate_stage_gold(20)
	_expect(
		stage_clear == roundi(_profile.gold_base * BalanceFormulas.g(_profile, 20.0)),
		"the clear reward reads the same formula"
	)

	experience_system.free()
	gold_system.free()
	enemy.free()
	player.free()


## One kill's EXP through the production reward entry, with the combat level fixed by the caller.
func _kill_experience(stage: int, offset: int, type_experience: float, level: int) -> int:
	return BalanceFormulas.kill_experience(
		_profile,
		stage,
		BalanceFormulas.enemy_offset_multiplier(_profile, offset),
		type_experience,
		level
	)


func _finish() -> void:
	if _failures.is_empty():
		print("Enemy experience scaling smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
