extends SceneTree

## R1 acceptance for the enemy switch (contract §4.2, §4.3):
##
##   * a normal spawn is `base * G(S) * c^-0.60 (HP) / c^-0.80 (ATK) * difficulty(S) *
##     offset_mult * variance`, with DEF taking no group factor at all
##   * stages 1..2 use the fixed training base — offset 0, variance 1 — whatever the pool says
##   * a Mini Boss is the normal REFERENCE enemy on a frozen c = 4 basis times 6 / 1.5 / 1.25,
##     not "one normal enemy times six full encounter HP"
##   * difficulty(S) travels ONCE, on the StageDefinition, and the provider builds the
##     encounter size from the profile

const PROFILE_PATH: String = "res://resources/balance/balance_profile_default.tres"
const MAX_REPORTED_ROWS: int = 6

var _profile: BalanceProfile
var _failures: Array[String] = []
var _checks: int = 0
var _reported: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_profile = load(PROFILE_PATH) as BalanceProfile
	if _profile == null:
		push_error("cannot load %s" % PROFILE_PATH)
		quit(1)
		return
	_test_training_stage()
	_test_normal_spawn()
	_test_group_factor()
	_test_offset_and_variance()
	_test_mini_boss()
	_test_provider_stage_definitions()
	_report()


# ---------------------------------------------------------------------------
# §4.2 training stages
# ---------------------------------------------------------------------------


func _test_training_stage() -> void:
	_check(BalanceFormulas.is_training_stage(_profile, 1), "stage 1 is a training stage")
	_check(BalanceFormulas.is_training_stage(_profile, _profile.training_stage_limit), "the last training stage is one")
	_check(not BalanceFormulas.is_training_stage(_profile, _profile.training_stage_limit + 1), "the stage after the training range is not one")

	var pool_stats := _stats(60, 8, 2)
	for stage in [1, 2]:
		var scaled: EnemyStats = EnemyScaling.build_combat_stats(
			_profile,
			pool_stats,
			stage,
			EnemyScaling.Kind.TRAINING,
			7,
			4,
			[2.0, 2.0, 2.0],
			[9.0, 9.0, 9.0]
		)
		_check(
			scaled.max_hp == int(_profile.training_enemy_hp)
			and scaled.attack == int(_profile.training_enemy_attack)
			and scaled.defense == int(_profile.training_enemy_defense),
			"stage %d fights the fixed training enemy %d/%d/%d, got %d/%d/%d" % [
				stage,
				int(_profile.training_enemy_hp),
				int(_profile.training_enemy_attack),
				int(_profile.training_enemy_defense),
				scaled.max_hp,
				scaled.attack,
				scaled.defense,
			]
		)
		_check(scaled.current_hp == scaled.max_hp, "a training enemy spawns at full HP")


# ---------------------------------------------------------------------------
# §4.2 normal spawns
# ---------------------------------------------------------------------------


func _test_normal_spawn() -> void:
	var pool_stats := _stats(int(_profile.reference_enemy_hp), int(_profile.reference_enemy_attack), int(_profile.reference_enemy_defense))
	for stage in [3, 10, 50, 100, 1000]:
		var scaled: EnemyStats = EnemyScaling.build_combat_stats(
			_profile,
			pool_stats,
			stage,
			EnemyScaling.Kind.NORMAL,
			0,
			1
		)
		_check(
			scaled.max_hp == roundi(BalanceFormulas.enemy_hp(_profile, stage, 1, _profile.reference_enemy_hp, 1.0, 1.0)),
			"stage %d HP follows §4.2, got %d" % [stage, scaled.max_hp]
		)
		_check(
			scaled.attack == roundi(BalanceFormulas.enemy_attack(_profile, stage, 1, _profile.reference_enemy_attack, 1.0, 1.0)),
			"stage %d ATK follows §4.2, got %d" % [stage, scaled.attack]
		)
		_check(
			scaled.defense == roundi(BalanceFormulas.enemy_defense(_profile, stage, _profile.reference_enemy_defense, 1.0, 1.0)),
			"stage %d DEF follows §4.2, got %d" % [stage, scaled.defense]
		)
		_check(scaled.level == stage, "a spawn with offset 0 displays level %d" % stage)


func _test_group_factor() -> void:
	var pool_stats := _stats(int(_profile.reference_enemy_hp), int(_profile.reference_enemy_attack), int(_profile.reference_enemy_defense))
	var solo: EnemyStats = EnemyScaling.build_combat_stats(_profile, pool_stats, 40, EnemyScaling.Kind.NORMAL, 0, 1)
	var group: EnemyStats = EnemyScaling.build_combat_stats(_profile, pool_stats, 40, EnemyScaling.Kind.NORMAL, 0, 4)
	var expected_hp_ratio: float = pow(4.0, _profile.enemy_hp_count_exponent)
	var expected_attack_ratio: float = pow(4.0, _profile.enemy_attack_count_exponent)
	_check(
		absf(float(group.max_hp) / float(solo.max_hp) - expected_hp_ratio) < 0.01,
		"a group of 4 keeps %.4f of the per-enemy HP" % expected_hp_ratio
	)
	_check(
		absf(float(group.attack) / float(solo.attack) - expected_attack_ratio) < 0.01,
		"a group of 4 keeps %.4f of the per-enemy ATK" % expected_attack_ratio
	)
	_check(
		absf(float(group.defense) / float(solo.defense) - 1.0) < 0.01,
		"DEF takes no group discount (%.2f vs %.2f)" % [group.defense, solo.defense]
	)
	_check(BalanceFormulas.enemy_count(_profile, 1) == 1, "stage 1 opens with one enemy")
	_check(BalanceFormulas.enemy_count(_profile, 10) == 4, "stage 10 opens with four")
	_check(BalanceFormulas.enemy_count(_profile, 1000) == _profile.max_enemy_count, "the count never exceeds the profile maximum")


func _test_offset_and_variance() -> void:
	var pool_stats := _stats(100, 20, 4)
	var neutral: EnemyStats = EnemyScaling.build_combat_stats(_profile, pool_stats, 100, EnemyScaling.Kind.NORMAL, 0, 1)
	for offset in [-2, 3]:
		var shifted: EnemyStats = EnemyScaling.build_combat_stats(_profile, pool_stats, 100, EnemyScaling.Kind.NORMAL, offset, 1)
		var expected: float = BalanceFormulas.enemy_offset_multiplier(_profile, offset)
		_check(
			absf(float(shifted.max_hp) / float(neutral.max_hp) - expected) < 0.01,
			"offset %+d scales HP by %.2f" % [offset, expected]
		)
		_check(shifted.level == 100 + offset, "offset %+d displays level %d" % [offset, 100 + offset])

	# §4.2: each stat draws its OWN factor, so a low HP roll does not drag the attack roll.
	var rolled: EnemyStats = EnemyScaling.build_combat_stats(_profile, pool_stats, 100, EnemyScaling.Kind.NORMAL, 0, 1, [0.85, 1.15, 1.0])
	_check(
		absf(float(rolled.max_hp) / float(neutral.max_hp) - 0.85) < 0.01,
		"the HP factor applies to HP only (%.2f)" % (float(rolled.max_hp) / float(neutral.max_hp))
	)
	_check(
		absf(float(rolled.attack) / float(neutral.attack) - 1.15) < 0.01,
		"the ATK factor applies to ATK only (%.2f)" % (float(rolled.attack) / float(neutral.attack))
	)
	_check(
		absf(float(rolled.defense) / float(neutral.defense) - 1.0) < 0.01,
		"an untouched DEF factor leaves DEF exactly where it was"
	)
	var clamped: EnemyStats = EnemyScaling.build_combat_stats(_profile, pool_stats, 100, EnemyScaling.Kind.NORMAL, 0, 1, [0.0, -1.0, 0.0])
	_check(clamped.max_hp == neutral.max_hp and clamped.attack == neutral.attack, "a non-positive variance factor counts as no variance")


# ---------------------------------------------------------------------------
# §4.3 Mini Boss
# ---------------------------------------------------------------------------


func _test_mini_boss() -> void:
	var boss_count: int = maxi(_profile.boss_base_enemy_count, 1)
	for stage in [10, 20, 1000]:
		var heavy_pool := _stats(4000, 900, 500)
		var light_pool := _stats(1, 1, 0)
		var boss: EnemyStats = EnemyScaling.build_combat_stats(_profile, heavy_pool, stage, EnemyScaling.Kind.MINI_BOSS, 3, 1, [0.5, 0.5, 0.5], [4.0, 4.0, 4.0])
		var other: EnemyStats = EnemyScaling.build_combat_stats(_profile, light_pool, stage, EnemyScaling.Kind.MINI_BOSS, -3, 2)
		_check(
			boss.max_hp == other.max_hp and boss.attack == other.attack and boss.defense == other.defense,
			"stage %d Mini Boss stats come from the reference enemy, not from the pool entry" % stage
		)
		var expected_hp: int = roundi(BalanceFormulas.enemy_hp(
			_profile,
			stage,
			boss_count,
			_profile.reference_enemy_hp * _profile.boss_hp_multiplier,
			1.0,
			1.0
		))
		var expected_attack: int = roundi(BalanceFormulas.enemy_attack(
			_profile,
			stage,
			boss_count,
			_profile.reference_enemy_attack * _profile.boss_attack_multiplier,
			1.0,
			1.0
		))
		var expected_defense: int = roundi(BalanceFormulas.enemy_defense(
			_profile,
			stage,
			_profile.reference_enemy_defense * _profile.boss_defense_multiplier,
			1.0,
			1.0
		))
		_check(boss.max_hp == expected_hp, "stage %d Mini Boss HP is %d, got %d" % [stage, expected_hp, boss.max_hp])
		_check(boss.attack == expected_attack, "stage %d Mini Boss ATK is %d, got %d" % [stage, expected_attack, boss.attack])
		_check(boss.defense == expected_defense, "stage %d Mini Boss DEF is %d, got %d" % [stage, expected_defense, boss.defense])
		_check(boss.level == stage, "a Mini Boss displays the stage it guards")


# ---------------------------------------------------------------------------
# §7 / §4.2 provider responsibilities
# ---------------------------------------------------------------------------


func _test_provider_stage_definitions() -> void:
	var provider := LevelProvider.new()
	root.add_child(provider)
	_check(provider.get_balance_profile() != null, "the provider resolves a balance profile")
	_check(
		provider.get_balance_profile() == BalanceProfile.get_default(),
		"without an injected profile the provider hands out the shipped default"
	)

	for stage in [1, 2, 10, 100, 500, 1000]:
		var definition: StageDefinition = provider.get_stage_definition(stage)
		_check(definition != null, "the provider builds stage %d" % stage)
		if definition == null:
			continue
		_check(
			is_equal_approx(definition.difficulty_multiplier, BalanceFormulas.difficulty(_profile, stage)),
			"stage %d carries difficulty %.4f once, got %.4f" % [
				stage,
				BalanceFormulas.difficulty(_profile, stage),
				definition.difficulty_multiplier,
			]
		)
	var stage_ten: StageDefinition = provider.get_stage_definition(10)
	_check(stage_ten.is_mini_boss_stage, "stage 10 is a Mini Boss stage")
	var stage_twenty_nine: StageDefinition = provider.get_stage_definition(29)
	_check(
		stage_twenty_nine.enemy_entries.size() == BalanceFormulas.enemy_count(_profile, 29),
		"stage 29 opens with count(29) = %d entries, got %d" % [
			BalanceFormulas.enemy_count(_profile, 29),
			stage_twenty_nine.enemy_entries.size(),
		]
	)
	var training: StageDefinition = provider.get_stage_definition(1)
	_check(
		not training.enemy_entries.is_empty() and training.enemy_entries[0].enemy_definition != null,
		"the authored first stage still spawns the training enemy"
	)
	provider.free()


func _stats(hp: int, attack: int, defense: int) -> EnemyStats:
	var stats := EnemyStats.new()
	stats.max_hp = hp
	stats.attack = attack
	stats.defense = defense
	stats.experience_reward = 100
	stats.gold_reward = 50
	return stats


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(description)
	if _reported < MAX_REPORTED_ROWS:
		_reported += 1
		push_error(description)


func _report() -> void:
	if _failures.is_empty():
		print("Enemy stat scaling smoke test passed (%d checks)." % _checks)
		quit(0)
		return
	print("Enemy stat scaling smoke test FAILED: %d of %d checks." % [_failures.size(), _checks])
	quit(1)
