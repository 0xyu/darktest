extends SceneTree

## M5 smoke test (§8): the progression simulator must be driven by the PRODUCTION formulas and be
## reproducible, so a report can never come from a second, private copy of the balance model.
##
## It runs a short trajectory set (fast enough for the normal verification pass) and checks the
## rules the model claims to obey:
##   * a stage's kills pay the §5 reward the runtime writes, catch-up included exactly once;
##   * the §5 post-battle identity (L = S pays exactly one level);
##   * a clear hands its remaining HP to the next stage while a defeat refills it;
##   * the same seed produces the same report, and a different seed does not;
##   * the M5 bands that the tool gates on agree with the M2 fixture's own bands;
##   * gear is acquired through the real loot generator and the fixed §8 policy.
##
## Run headless: godot --headless --path . -s res://tests/balance_progression_sim_smoke_test.gd

const FAST_CONFIGURATION: Dictionary = {"seeds": 4, "max_stage": 120}

var _profile: BalanceProfile
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_profile = BalanceProfile.get_default()
	_test_reward_entry()
	_test_band_agreement()
	_test_drop_slot_coverage()
	_test_simulation_is_production_driven()

	if _failures.is_empty():
		print("balance_progression_sim_smoke_test: PASS")
	else:
		print("balance_progression_sim_smoke_test: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


# ---------------------------------------------------------------------------
# §5: the reward a spawn carries, and the identity the level curve is built on
# ---------------------------------------------------------------------------


func _test_reward_entry() -> void:
	var spawn := EnemyData.new()
	var base := EnemyStats.new()
	base.max_hp = int(_profile.reference_enemy_hp)
	base.attack = int(_profile.reference_enemy_attack)
	base.defense = int(_profile.reference_enemy_defense)
	spawn.base_stats = base
	# §5: the STORED reward is `100 * G(S) * offset_mult * type_exp` and carries NO catch-up, so
	# the settlement (which knows the player's level) applies `catchup(S, L)` exactly once. Before
	# the R3 simulation found it, this value was built at level 1 — `catchup(S, 1)` saturates at
	# 2.0 from S11 — and the settlement multiplied the real catch-up on top of it.
	for stage in [3, 10, 11, 50, 500]:
		for offset in [0, -3, 3]:
			var scaled: EnemyStats = EnemyScaling.build_combat_stats(
				_profile, base, stage, EnemyScaling.Kind.NORMAL, offset, 1,
				EnemyScaling.unity_variance()
			)
			var offset_multiplier: float = BalanceFormulas.enemy_offset_multiplier(_profile, offset)
			var neutral: int = BalanceFormulas.kill_experience(
				_profile, stage, offset_multiplier, 1.0, stage
			)
			_expect(
				scaled.experience_reward == neutral,
				"S%d offset %d stores the catch-up-free reward (%d vs %d)" % [
					stage, offset, scaled.experience_reward, neutral
				]
			)
			var catchup: float = BalanceFormulas.experience_catchup(_profile, stage, 1)
			if catchup > 1.0:
				_expect(
					scaled.experience_reward < BalanceFormulas.round_reward(
						_profile, float(neutral) * catchup, 1
					),
					"S%d must not bake the level-1 catch-up into the stored reward" % stage
				)

	# §5 "post-battle identity": at the reference state (L = S, offset 0) one stage of kills pays
	# exactly one level, which is what keeps a clean trajectory at L = S + 1.
	for stage in [3, 7, 25, 100, 400]:
		var count: int = BalanceFormulas.enemy_count(_profile, stage)
		var total: int = 0
		for _index in range(count):
			total += BalanceFormulas.kill_experience(_profile, stage, 1.0, 1.0, stage)
		var required: int = BalanceFormulas.experience_required(_profile, stage)
		_expect(
			absi(total - required) <= count,
			"stage %d pays one level: %d EXP vs %d required" % [stage, total, required]
		)


# ---------------------------------------------------------------------------
# The M5 constants must agree with the fixture the M2 bands live in
# ---------------------------------------------------------------------------


func _test_band_agreement() -> void:
	_expect(
		is_equal_approx(
			BalanceProgressionSimulator.SWAP_SURVIVAL_MIN, BalanceReferenceCase.SURVIVAL_MIN
		),
		"the §8 M5 swap condition uses the M2 static-survival floor"
	)
	_expect(
		BalanceProgressionSimulator.MAX_ACTIONS_PER_ENCOUNTER == BalanceReferenceCase.MAX_SIMULATED_ACTIONS,
		"the §8 M5 encounter failure limit is the M2/M3 action limit"
	)
	_expect(
		BalanceProgressionSimulator.REPLAYS_PER_ADVANCE == BalanceProgressionSimulator.TARGET_REPLAYS_PER_ADVANCE,
		"the replay budget and the target it is gated on are one value"
	)
	_expect(
		BalanceProgressionSimulator.BUDGET_PUSHES == 2,
		"an advance is within budget when the first push or the push after one replay budget clears it"
	)
	# The M5 strategy uses the shipped AUTO potion rule instead of banning potions (§8's text bans
	# them, the game's automation does not), so the model's three potion values are the LIVE
	# defaults: the starting stock and the heal ratio from PlayerController, the drink threshold
	# from AutoCombatController.
	var live_player := PlayerController.new()
	var live_auto := AutoCombatController.new()
	_expect(
		BalanceProgressionSimulator.STARTING_POTIONS == live_player.healing_item_count,
		"the model's starting potion stock is PlayerController.healing_item_count (%d)" % live_player.healing_item_count
	)
	_expect(
		is_equal_approx(BalanceProgressionSimulator.POTION_HEAL_RATIO, live_player.healing_item_heal_ratio),
		"the model's potion heal ratio is PlayerController.healing_item_heal_ratio (%.2f)" % live_player.healing_item_heal_ratio
	)
	_expect(
		is_equal_approx(BalanceProgressionSimulator.POTION_DRINK_THRESHOLD, live_auto.healing_item_threshold),
		"the model's drink threshold is AutoCombatController.healing_item_threshold (%.2f)" % live_auto.healing_item_threshold
	)
	_expect(live_auto.use_healing_items, "the shipped AUTO does drink potions")
	live_player.free()
	live_auto.free()


# ---------------------------------------------------------------------------
# §8 M5 remediation: a drop covers an EMPTY equipment slot
# ---------------------------------------------------------------------------


func _test_drop_slot_coverage() -> void:
	var generator := LootGenerator.new(4242)
	var table := LootTable.create_normal()
	# With a coverage list every equipment drop lands in one of the listed slots: without it the
	# early game arrives at the S10 challenge with empty slots, because covering seven slots at
	# random is a coupon-collector problem (~30 drops) and the first nine stages offer ~18 kills.
	for _round in range(40):
		var loot: Array[EquipmentInstance] = generator.generate_from_table(table, 10, [0, 3])
		for item in loot:
			if item.is_consumable():
				continue
			_expect(
				item.get_slot() == EquipmentSlot.WEAPON or item.get_slot() == EquipmentSlot.GLOVES,
				"a covered drop uses one of the empty slots (got %d)" % item.get_slot()
			)
	# An empty coverage list keeps the plain random slot, which the caller relies on once the hero
	# has all seven slots filled.
	var random_slots: Dictionary = {}
	for _round in range(40):
		for item in generator.generate_from_table(table, 10):
			if not item.is_consumable():
				random_slots[item.get_slot()] = true
	_expect(
		random_slots.size() > 2,
		"without a coverage list the slot stays random (saw %d slots)" % random_slots.size()
	)


# ---------------------------------------------------------------------------
# The simulation itself
# ---------------------------------------------------------------------------


func _test_simulation_is_production_driven() -> void:
	var report: Dictionary = BalanceProgressionSimulator.run(_profile, FAST_CONFIGURATION)
	_expect(not report.is_empty(), "the simulator returns a report")
	_expect(int(report["stages"]) > 0, "the report counts the stage challenges it ran")
	_expect(
		int(report["drops"]) > 0,
		"real drops were generated through LootGenerator"
	)
	_expect(
		int(report["swaps"]) > 0,
		"the fixed §8 policy equipped replacements"
	)
	_expect(int(report["deaths"]) > 0, "the run met at least one defeat and recovered from it")

	var actions: Dictionary = report["actions"]
	_expect(
		int(actions["normal_samples"]) > 0 and int(actions["boss_samples"]) > 0,
		"normal encounters and Mini Bosses both produced attack-action samples"
	)
	_expect(
		float(actions["normal_median"]) >= 1.0,
		"a normal win costs at least one attack action"
	)
	var level: Dictionary = report["level"]
	_expect(
		int(level["samples"]) == int(report["stages"]),
		"every challenge contributed a battle-start level sample"
	)
	var loadout: Dictionary = report["loadout"]
	# §3.1: even the worst real loadout is at or above the reference fixture (rarity_core ≥ 1 and
	# every affix is a non-negative bonus), which is exactly why the reference is a LOWER bound.
	_expect(
		float(loadout["attack_ratio_p10"]) >= 1.0,
		"a real loadout never falls below the reference fixture's attack (P10 %.2f)" % float(loadout["attack_ratio_p10"])
	)
	_expect(
		float(loadout["entry_hp_ratio_median"]) > 0.0 and float(loadout["entry_hp_ratio_median"]) <= 1.0,
		"battle-start HP is a fraction of the maximum"
	)

	# Reproducible: the same seeds produce the same report, a different seed does not.
	var repeat: Dictionary = BalanceProgressionSimulator.run(_profile, FAST_CONFIGURATION)
	_expect(
		_report_fingerprint(repeat) == _report_fingerprint(report),
		"the same configuration reproduces the same report"
	)
	var shifted: Dictionary = BalanceProgressionSimulator.run(
		_profile, {"seeds": 4, "max_stage": 120, "first_seed": 5001}
	)
	_expect(
		_report_fingerprint(shifted) != _report_fingerprint(report),
		"a different seed produces a different trajectory"
	)
	# The tool's own gate reads the report keys it prints; a missing key would silently disable a
	# target, so every key the gate reads is asserted here.
	var targets: Dictionary = BalanceProgressionSimulator.evaluate_targets(report)
	for key in [
		"slot_fill_before_s10", "success_after_s20", "success_window", "normal_actions",
		"boss_actions", "level_tracking", "replay_budget",
	]:
		_expect(targets.has(key), "the release gate evaluates '%s'" % key)


## A short, order-stable description of a report, used to compare two runs.
func _report_fingerprint(report: Dictionary) -> String:
	return "%d/%d/%d/%d/%d" % [
		int(report["stages"]),
		int(report["swaps"]),
		int(report["drops"]),
		int(report["deaths"]),
		int(round(float(report["level"]["samples"]))),
	]


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
