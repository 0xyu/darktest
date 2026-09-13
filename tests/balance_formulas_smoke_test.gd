extends SceneTree

## Balance v4 smoke test — M1 (pure functions and boundaries) and the analytic half of M2
## of [code]docs/balance-rework-implementation.md[/code] §8.
##
## Run headless:
##   godot --headless --path . -s res://tests/balance_formulas_smoke_test.gd
##
## Every number is read from the AUTHORITATIVE profile resource, so editing
## [code]resources/balance/balance_profile_default.tres[/code] re-runs these checks against
## the new values instead of against a copy of them:
##   * `G(1) = 1`, monotonic over 1..1000, exact `r(S)` ratio, continuous difficulty ramp
##   * float armor homogeneity and the boundary inputs: A = 0, D = 0, huge D, MAX_COMBAT_VALUE
##   * equipment weight columns sum to 1 and the §3.1 `b_X × G(S)` reference identity
##   * S3..9 encounter work 2..6, S10..1000 work 4..8, static survival 4..9, S10+ cleared in
##     exactly 8 actions, Mini Boss 8..12 actions, both surviving
##   * the §6 conservative maximum configuration stays below MAX_COMBAT_VALUE
##
## The discrete action simulation and the random-drop trajectory (M3/M5) are NOT covered
## here; see the generated comparison table in docs/balance-reference-table.md.

const PROFILE_PATH: String = "res://resources/balance/balance_profile_default.tres"
const RELATIVE_TOLERANCE: float = 1e-9
## Stages whose §3.1 identity (`stat == b_X × G(S)`) is checked exactly.
const IDENTITY_STAGES: Array[int] = [1, 2, 3, 10, 20, 100, 500, 1000]
const MAX_REPORTED_ROWS: int = 5

var _profile: BalanceProfile
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_profile = load(PROFILE_PATH) as BalanceProfile
	if _profile == null:
		push_error("Could not load %s" % PROFILE_PATH)
		quit(1)
		return
	_test_release_bounds()
	_test_scale_identity()
	_test_difficulty_ramp()
	_test_armor_boundaries()
	_test_equipment_weights()
	_test_reference_scale_identity()
	_test_reference_case_bands()
	_test_combat_value_bound()

	if _failures.is_empty():
		print("Balance formula smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_release_bounds() -> void:
	_check(_profile.max_stage == 1000, "release range ends at stage 1000")
	_check(_profile.max_character_level == 1000, "character range ends at level 1000")
	_check(_profile.max_item_level == 1003, "item level range ends at 1003")
	_check(
		is_equal_approx(_profile.max_combat_value, 1e12),
		"MAX_COMBAT_VALUE is the 1e12 fault line"
	)
	_check(
		_profile.max_persistent_value > _profile.max_combat_value,
		"the persisted Gold/EXP ceiling is not the combat ceiling"
	)
	_check(
		BalanceFormulas.is_valid_value(_profile, _profile.max_combat_value),
		"a value on the combat line is still valid"
	)
	_check(
		not BalanceFormulas.is_valid_value(_profile, _profile.max_combat_value * 2.0),
		"a combat value past 1e12 is rejected"
	)
	_check(not BalanceFormulas.is_valid_value(_profile, NAN), "NaN is rejected")
	_check(not BalanceFormulas.is_valid_value(_profile, INF), "Infinity is rejected")
	_check(
		BalanceFormulas.is_valid_persistent_value(_profile, _profile.max_persistent_value),
		"a value on the persistence line is still valid"
	)
	_check(
		not BalanceFormulas.is_valid_persistent_value(_profile, _profile.max_persistent_value * 10.0),
		"a persisted value past 9e15 is rejected"
	)


func _test_scale_identity() -> void:
	_check(BalanceFormulas.g(_profile, 1.0) == 1.0, "G(1) == 1 exactly")
	_check(is_equal_approx(BalanceFormulas.item_scale(_profile, 1), 1.0), "item_scale(1) == 1")
	_check(is_equal_approx(BalanceFormulas.level_scale(_profile, 1), 1.0), "level_scale(1) == 1")
	_check(
		_close(_profile.get_level_exponent(), 0.40) and _close(_profile.get_item_exponent(), 0.60),
		"level/item exponents are 0.40/0.60"
	)
	var previous: float = BalanceFormulas.g(_profile, 1.0)
	var ratio_failures: int = 0
	var monotonicity_failures: int = 0
	for stage in range(1, _profile.max_stage + 1):
		var current: float = BalanceFormulas.g(_profile, float(stage + 1))
		if current <= previous:
			monotonicity_failures += 1
		var expected_ratio: float = pow(
			(float(stage) + _profile.growth_offset + 1.0) / (float(stage) + _profile.growth_offset),
			float(_profile.growth_exponent)
		)
		if not _close(BalanceFormulas.stage_ratio(_profile, stage), expected_ratio):
			ratio_failures += 1
		if not _close(current / previous, expected_ratio):
			ratio_failures += 1
		previous = current
	_check(monotonicity_failures == 0, "G is strictly increasing over stages 1..1000")
	_check(ratio_failures == 0, "r(S) matches G(S+1)/G(S) and the closed form for 1..1000")
	# The exact per-stage ratio is not the first-order approximation the design review
	# had to correct.
	_check(
		not _close(BalanceFormulas.stage_ratio(_profile, 1), 1.0 + 4.0 / 21.0),
		"r(S) is the exact ratio, not 1 + 4/(S+20)"
	)


func _test_difficulty_ramp() -> void:
	_check(_close(BalanceFormulas.difficulty(_profile, 1), 0.90), "difficulty(1) == 0.90")
	_check(
		_close(BalanceFormulas.difficulty(_profile, 10), 1.00),
		"difficulty at the first boundary is 1.00"
	)
	_check(
		_close(BalanceFormulas.difficulty(_profile, 100), 1.10),
		"difficulty at the second boundary is 1.10"
	)
	_check(
		_close(BalanceFormulas.difficulty(_profile, 1000), 1.10),
		"difficulty stays flat after stage 100"
	)
	var previous: float = BalanceFormulas.difficulty(_profile, 1)
	var regressions: int = 0
	var jumps: int = 0
	# The steepest legal per-stage step is the first ramp's; a boundary discontinuity would
	# exceed it.
	var largest_step: float = (
		(_profile.difficulty_mid - _profile.difficulty_start)
		/ maxf(float(_profile.difficulty_mid_stage) - 1.0, 1.0)
	)
	for stage in range(2, _profile.max_stage + 1):
		var current: float = BalanceFormulas.difficulty(_profile, stage)
		if current < previous:
			regressions += 1
		if current - previous > largest_step + 1e-12:
			jumps += 1
		previous = current
	_check(regressions == 0, "difficulty never decreases")
	_check(jumps == 0, "difficulty is continuous at both ramp boundaries")


func _test_armor_boundaries() -> void:
	_check(BalanceFormulas.armor_damage(_profile, 0.0, 0.0) == 0.0, "A = 0 deals 0 armor damage")
	_check(BalanceFormulas.armor_damage(_profile, -5.0, -5.0) == 0.0, "negative A/D clamp to 0")
	_check(_close(BalanceFormulas.armor_damage(_profile, 100.0, 0.0), 100.0), "D = 0 deals A")
	_check(_close(BalanceFormulas.armor_damage(_profile, 100.0, 100.0), 50.0), "A = D halves A")
	_check(
		BalanceFormulas.resolve_damage(_profile, 100.0, 5000000.0) == 1,
		"a huge DEF still leaves the minimum of 1"
	)
	_check(
		BalanceFormulas.resolve_damage(_profile, 0.0, 0.0) == 1,
		"the minimum-1 floor also applies to a 0-attack actor"
	)
	_check(
		BalanceFormulas.armor_damage(_profile, 300000000.0, 700000000.0) > 0.0
		and _close(
			BalanceFormulas.armor_damage(_profile, 300000000.0, 700000000.0),
			1000000.0 * BalanceFormulas.armor_damage(_profile, 300.0, 700.0)
		),
		"the float armor function is homogeneous"
	)
	_check(BalanceFormulas.armor_damage(_profile, NAN, 10.0) == 0.0, "NaN attack deals 0")
	_check(
		is_finite(BalanceFormulas.armor_damage(_profile, 100.0, INF))
		and BalanceFormulas.armor_damage(_profile, 100.0, INF) >= 0.0,
		"an infinite DEF saturates instead of producing NaN damage"
	)
	_check(
		BalanceFormulas.resolve_damage(_profile, 100.0, INF) == 1,
		"an infinite DEF still lands on the minimum-1 floor"
	)
	_check(
		BalanceFormulas.resolve_damage(_profile, INF, 0.0) == int(_profile.max_combat_value),
		"a saturated damage chain stops at MAX_COMBAT_VALUE"
	)
	# One rounding at the end (§4.1), not one per multiplier.
	var attack: float = 1000.0
	var defense: float = 250.0
	var raw: float = BalanceFormulas.armor_damage(_profile, attack, defense)
	_check(
		BalanceFormulas.resolve_damage(_profile, attack, defense, 0.8) == maxi(roundi(raw * 0.8), 1),
		"skill damage is rounded once, after every multiplier"
	)
	_check(
		BalanceFormulas.resolve_damage(_profile, attack, defense, 1.0, 1.0, true, 1.5)
		== maxi(roundi(raw * 1.5), 1),
		"a critical applies critical damage before the single rounding"
	)
	_check(
		BalanceFormulas.resolve_damage(_profile, attack, defense, 0.0) == 1,
		"a zero multiplier lands on the minimum-1 floor"
	)
	_check(
		_close(
			BalanceFormulas.expected_critical_multiplier(_profile),
			1.0 + _profile.base_critical_chance * (_profile.base_critical_damage - 1.0)
		),
		"the expected critical multiplier comes from the profile baseline"
	)


func _test_equipment_weights() -> void:
	_check(
		_profile.slot_hp_weights.size() == EquipmentSlot.AMULET + 1
		and _profile.slot_attack_weights.size() == EquipmentSlot.AMULET + 1
		and _profile.slot_defense_weights.size() == EquipmentSlot.AMULET + 1,
		"every slot weight column has one entry per equipment slot"
	)
	for stat_id in BalanceProfile.STAT_IDS:
		var weights: Array[float] = _profile.get_slot_weights(stat_id)
		var total: float = 0.0
		for weight in weights:
			total += weight
		_check(
			_close(total, 1.0),
			"the %s slot weights sum to 1 (got %.12f)" % [stat_id, total]
		)
	_check(
		_close(BalanceFormulas.rarity_core(_profile, EquipmentRarity.COMMON), 1.0),
		"rarity_core(Common) == 1"
	)
	_check(
		BalanceFormulas.item_scale(_profile, 50) > BalanceFormulas.item_scale(_profile, 49),
		"item_scale is monotonic in item level"
	)


func _test_reference_scale_identity() -> void:
	for stage: int in IDENTITY_STAGES:
		var row: Dictionary = BalanceReferenceCase.build(_profile, stage)
		var reference: float = BalanceFormulas.g(_profile, float(stage))
		var expected_hp: float = _profile.base_hp * reference
		var expected_attack: float = _profile.base_attack * reference
		var expected_defense: float = _profile.base_defense * reference
		_check(
			_close(float(row["player_hp"]), expected_hp)
			and _close(float(row["player_attack"]), expected_attack)
			and _close(float(row["player_defense"]), expected_defense),
			"stage %d: the 7-slot Common fixture yields exactly b_X × G(S)" % stage
		)


func _test_reference_case_bands() -> void:
	var work_low: float = INF
	var work_high: float = -INF
	var work_low_stage: int = 0
	var work_high_stage: int = 0
	var survival_low: float = INF
	var survival_high: float = -INF
	var survival_low_stage: int = 0
	var survival_high_stage: int = 0
	var work_failures: Array[String] = []
	var survival_failures: Array[String] = []
	var action_failures: Array[String] = []
	var defeat_failures: Array[String] = []
	for stage in range(3, _profile.max_stage + 1):
		var row: Dictionary = BalanceReferenceCase.build(_profile, stage)
		var work: float = float(row["work"])
		var survival: float = float(row["survival"])
		if work < work_low:
			work_low = work
			work_low_stage = stage
		if work > work_high:
			work_high = work
			work_high_stage = stage
		if survival < survival_low:
			survival_low = survival
			survival_low_stage = stage
		if survival > survival_high:
			survival_high = survival
			survival_high_stage = stage
		if not BalanceReferenceCase.is_work_in_band(_profile, stage, work):
			_report(work_failures, "stage %d: encounter work %.3f is outside 2..%.1f" % [
				stage, work, BalanceReferenceCase.get_work_max(_profile, stage)
			])
		if not BalanceReferenceCase.is_survival_in_band(survival):
			_report(survival_failures, "stage %d: static survival %.3f is outside 4..9" % [
				stage, survival
			])
		if stage >= _profile.difficulty_mid_stage:
			if int(row["actions"]) != BalanceReferenceCase.ACTIONS_LATE:
				_report(action_failures, "stage %d: cleared in %d actions, expected %d" % [
					stage, int(row["actions"]), BalanceReferenceCase.ACTIONS_LATE
				])
			if bool(row["player_defeated"]):
				_report(defeat_failures, "stage %d: the reference player did not survive" % stage)
	_check(work_failures.is_empty(), "encounter work stays inside the M2 band")
	_check(survival_failures.is_empty(), "static survival stays inside the M2 band")
	_check(action_failures.is_empty(), "S10..1000 reference encounters clear in 8 actions")
	_check(defeat_failures.is_empty(), "the reference player survives every S10..1000 encounter")
	for failure in work_failures + survival_failures + action_failures + defeat_failures:
		_failures.append(failure)

	var boss_action_failures: Array[String] = []
	var boss_defeat_failures: Array[String] = []
	for stage in range(_profile.boss_interval, _profile.max_stage + 1, _profile.boss_interval):
		var row: Dictionary = BalanceReferenceCase.build(_profile, stage, true)
		var actions: int = int(row["actions"])
		if actions < BalanceReferenceCase.BOSS_ACTIONS_MIN or actions > BalanceReferenceCase.BOSS_ACTIONS_MAX:
			_report(boss_action_failures, "Mini Boss S%d: %d actions, expected %d..%d" % [
				stage, actions, BalanceReferenceCase.BOSS_ACTIONS_MIN, BalanceReferenceCase.BOSS_ACTIONS_MAX
			])
		if bool(row["player_defeated"]):
			_report(boss_defeat_failures, "Mini Boss S%d: the reference player did not survive" % stage)
	_check(boss_action_failures.is_empty(), "Mini Bosses need 8..12 player actions")
	_check(boss_defeat_failures.is_empty(), "the reference player survives every Mini Boss")
	for failure in boss_action_failures + boss_defeat_failures:
		_failures.append(failure)

	for stage in range(1, _profile.training_stage_limit + 1):
		var row: Dictionary = BalanceReferenceCase.build_training(_profile, stage)
		_check(
			bool(row["cleared"]),
			"stage %d: the training enemy is clearable with the starting reference player" % stage
		)
	print(
		"Reference case S3..%d: work %.3f (S%d) .. %.3f (S%d); survival %.3f (S%d) .. %.3f (S%d)."
		% [
			_profile.max_stage,
			work_low, work_low_stage, work_high, work_high_stage,
			survival_low, survival_low_stage, survival_high, survival_high_stage,
		]
	)


func _test_combat_value_bound() -> void:
	var max_scale: float = pow(BalanceFormulas.g(_profile, float(_profile.max_stage)), _profile.get_level_exponent())
	max_scale *= pow(BalanceFormulas.g(_profile, float(_profile.max_item_level)), _profile.get_item_exponent())
	var affix_budget: float = 1.4 + 7.0 * 0.1 * 2.75 * 1.2
	var maximum_stat: float = 0.0
	for stat_id in BalanceProfile.STAT_IDS:
		var value: float = _profile.get_base_stat(stat_id) * affix_budget * max_scale
		maximum_stat = maxf(maximum_stat, value)
		_check(
			BalanceFormulas.is_valid_value(_profile, value),
			"the maximum legal %s stays below MAX_COMBAT_VALUE" % stat_id
		)
	_check(
		BalanceFormulas.is_valid_value(_profile, maximum_stat * 1.9 * 1.5 * 2.5),
		"the maximum legal damage chain stays below MAX_COMBAT_VALUE"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report(bucket: Array[String], message: String) -> void:
	if bucket.size() < MAX_REPORTED_ROWS:
		bucket.append(message)
	elif bucket.size() == MAX_REPORTED_ROWS:
		bucket.append("… more rows of the same kind were suppressed")


func _close(left: float, right: float, tolerance: float = RELATIVE_TOLERANCE) -> bool:
	if not is_finite(left) or not is_finite(right):
		return false
	return absf(left - right) <= tolerance * maxf(absf(left), absf(right)) + 1e-12
