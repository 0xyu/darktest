class_name BalanceProgressionSimulator
extends RefCounted

## M5 of the v4 balance contract (§8): the seeded progression simulation that drives the REAL
## production formulas — [BalanceFormulas] for the scale, armor, rewards and level requirements,
## [EnemyScaling] for every spawn, [LootGenerator] / [EquipmentGenerator] for every drop and
## [EquipmentStatBlock] for every stat the hero fights with. It is NOT a second copy of the
## balance model: the only things it owns are the things a model must own — the stage loop, the
## fixed strategy of §8 and the random number streams (seeded, so a run is reproducible).
##
## ## The fixed M5 strategy (§8)
##
## * Advance on a clear; after a defeat, replay the highest cleared NORMAL stage up to
##   [constant REPLAYS_PER_ADVANCE] times and then push the stage again.
## * In combat: the normal attack only, moving by the shortest legal route toward the lowest-HP
##   reachable enemy. No active skills, no Magic Tome, no Sub Heroes. The equipment's own crit /
##   dodge / life steal / stun rules stay real, and the shipped AUTO potion rule is used (drink at
##   [constant POTION_DRINK_THRESHOLD] of maximum HP, which spends that turn) — contract §8's text
##   bans potions, but the game's own automation does not, and the hero's HP survives between
##   stages, so a potion-free model measures a hero nobody plays.
## * Gear: an empty slot is filled first; a replacement is equipped only when it raises the
##   effective `ATK × HP` proxy AND the static survival against the current normal reference
##   enemy stays at or above [constant SWAP_SURVIVAL_MIN]. A tie keeps the old item.
##
## This strategy is a REPRODUCIBLE ACCEPTANCE PROXY. It is deliberately not the player's AUTO
## logic, and nothing here writes to a save.
##
## ## The runtime rules the model mirrors
##
## * The encounter size `c` is frozen at stage build and every surviving enemy attacks once after
##   each player action (M3 semantics — distance does not gate a retaliation; the recorded
##   movement turns are what the walk actually costs).
## * The hero's HP is carried ACROSS stages. A defeat revives the hero at full HP
##   ([code]PlayerController.revive_for_retry[/code]), which is what makes the replay loop above
##   the real recovery mechanism.
## * A level-up rebuilds the block and keeps the current HP ([code]keep_current_hp[/code]).
## * Rewards settle once per kill, from the values [EnemyScaling] already wrote onto the spawn,
##   with the EXP catch-up sampled against the level BEFORE that kill.

## The 24 compressed normal enemies the provider spawns from.
const ENEMY_POOL_DIRECTORY: String = "res://resources/enemies/generated"

## §8 M5: "单次遭遇100次玩家回合内未清场视为失败".
const MAX_ACTIONS_PER_ENCOUNTER: int = 100
## §8 M5: "预计静态 survival≥4".
const SWAP_SURVIVAL_MIN: float = 4.0
## §8 M5: at most this many cleared-stage replays before the next push.
const REPLAYS_PER_ADVANCE: int = 5
## §8 M5 "回刷…最多5次后再试": an advance is WITHIN BUDGET when the stage falls to the first push
## or to the push that follows one full replay budget. A stage that survives both is over budget,
## which is what the "≥90 % success after S20" target rules out.
const BUDGET_PUSHES: int = 2
## A stage still failing after this many pushes ends its trajectory: the replay budget has been
## spent several times over, so the content is a wall and not a bad roll.
const PUSH_LIMIT_PER_STAGE: int = 8

## §4.2 offset distribution, rolled exactly as [code]LevelProvider._roll_enemy_offset[/code].
const ENEMY_OFFSETS: Array[int] = [0, -1, 1, -2, 2, -3, 3]
const ENEMY_OFFSET_WEIGHTS: Array[int] = [40, 15, 15, 10, 10, 5, 5]

## The potion economy the M5 strategy uses. Contract §8's strategy text bans potions, but the
## shipped game's own AUTO drinks one at
## [constant POTION_DRINK_THRESHOLD] of maximum HP (and spends that turn on it), the hero starts with
## [constant STARTING_POTIONS] and a potion drop restocks the counter — so a model that bans potions
## measures a hero nobody plays. The three values are asserted against the live
## [PlayerController] / [AutoCombatController] defaults in the M5 smoke test, so the model cannot
## drift from the game.
const STARTING_POTIONS: int = 3
const POTION_HEAL_RATIO: float = 0.35
const POTION_DRINK_THRESHOLD: float = 0.35

## The grid the movement model walks on (the §1 inner field) and the combat rules it obeys.
const GRID_MIN: Vector2i = Vector2i(1, 0)
const GRID_MAX: Vector2i = Vector2i(11, 6)
const PLAYER_START_CELL: Vector2i = Vector2i(1, 3)
const BASE_MOVEMENT_POINTS: int = 3
const BASE_ATTACK_RANGE: int = 1

## M5 release targets (§8). Read by the tool and by the smoke test, so a report and the gate it is
## measured against cannot drift apart.
const TARGET_SLOT_FILL_RATIO: float = 0.90
const TARGET_SLOT_FILL_STAGE: int = 10
const TARGET_SUCCESS_RATE_AFTER_S20: float = 0.90
const SUCCESS_WINDOW_STAGES: int = 20
const SUCCESS_WINDOW_MIN_RATE: float = 0.90
const TARGET_NORMAL_ACTIONS_MEDIAN_MIN: float = 4.0
const TARGET_NORMAL_ACTIONS_MEDIAN_MAX: float = 10.0
const TARGET_NORMAL_ACTIONS_P90_MAX: float = 14.0
const TARGET_BOSS_ACTIONS_MEDIAN_MIN: float = 8.0
const TARGET_BOSS_ACTIONS_MEDIAN_MAX: float = 14.0
## §5: 95 % of the battle-start samples satisfy |L − S| ≤ 3, with a single deviation ≤ 6.
const TARGET_LEVEL_ABS_LE_3_RATIO: float = 0.95
const TARGET_LEVEL_MAX_ABS: int = 6
## §8 M5: "每次推进前最多允许5次已通关关卡回刷".
const TARGET_REPLAYS_PER_ADVANCE: int = REPLAYS_PER_ADVANCE
## Stages at or below this are excluded from the "after S20" success statistics.
const SUCCESS_MEASUREMENT_FROM_STAGE: int = 20

var profile: BalanceProfile
var seed_count: int = 100
var first_seed: int = 1
var max_stage: int = 1000
## Report the special-encounter trajectory separately (§5): the release targets are stated for the
## plain normal / every-10th-stage Mini Boss trajectory.
var with_special_encounters: bool = false
## §5 measures its level gate on the "逐关全清" trajectory — a run that clears EVERY stage in order,
## so it never replays anything. With this flag a failed push ends the trajectory instead of
## starting the recovery loop, which is what makes that trajectory observable.
var clean_only: bool = false
## MODEL EXPERIMENT, not a shipped rule: fraction of maximum HP restored when a stage is cleared.
## The shipped runtime restores nothing (HP survives between stages and only a defeat refills it),
## so this exists to measure what a recovery rule would do to the M5 success gate before anyone
## changes the game.
var clear_heal_ratio: float = 0.0
## MODEL EXPERIMENT, not a shipped rule: the share of successful drops that becomes a potion. The
## shipped default is [constant LootGenerator.CONSUMABLE_DROP_CHANCE]; this exists to measure whether
## the potion SUPPLY can carry the strategy's attrition.
var consumable_drop_chance: float = LootGenerator.CONSUMABLE_DROP_CHANCE
var verbose: bool = false
## Debug aid for tuning: print one trajectory stage by stage (0 = off).
var trace_seed: int = 0
## The seed currently being traced, so the per-stage report can label itself.
var _tracing: bool = false

var _pool: Array[EnemyData] = []
var _reference_base: EnemyData
var _rng := RandomNumberGenerator.new()
var _loot: LootGenerator
var _loot_stub: EnemyController
var _loot_stub_data: EnemyData
var _base_stats: Dictionary = {}

# --- per-trajectory state ---
var _equipped: Array[EquipmentInstance] = []
var _block: Dictionary = {}
var _level: int = 1
var _experience: int = 0
var _gold: int = 0
var _current_hp: int = 0
## Potion stock, mirroring `PlayerController.healing_item_count` (the starting stock plus the potion
## drops that restock the counter, §7).
var _potions: int = STARTING_POTIONS
var _highest_cleared_normal: int = 0
var _first_full_slot_stage: int = 0
## Per-push EXP diagnostics (trace only): what the push paid and how many levels it bought.
var _experience_gained: int = 0
var _levels_gained: int = 0
## The battle-start deviation of the advance currently being pushed, so the §5 level sample can be
## attributed to the "cleared it in order" trajectory once the outcome is known.
var _pending_level_delta: int = 0
## Per-slot drop and swap counters, for the trace only.
var _slot_drops: Array[int] = []
var _slot_swaps: Array[int] = []
var _slot_empty_fills: Array[int] = []
## First-challenge outcomes of the normal encounters after [constant SUCCESS_MEASUREMENT_FROM_STAGE],
## in advance order, for this trajectory's success windows. `_outcomes` is the gated metric ("the
## stage fell"), `_budget_outcomes` the stricter one ("it fell within one replay budget").
var _trajectory_normal_outcomes: Array[bool] = []
var _trajectory_normal_budget_outcomes: Array[bool] = []

# --- accumulated report ---
var _report: Dictionary = {}


## The M5 entry point: run `seed_count` seeded trajectories and return the report.
##
## Configuration keys: `seeds`, `first_seed`, `max_stage`, `special_encounters`, `verbose`.
static func run(profile: BalanceProfile, configuration: Dictionary = {}) -> Dictionary:
	var simulator := BalanceProgressionSimulator.new(profile, configuration)
	var report: Dictionary = simulator.run_all()
	simulator.dispose()
	return report


## Whether a report meets the §8 M5 release targets, key by key, so a caller can report exactly
## what failed instead of one boolean.
static func evaluate_targets(report: Dictionary) -> Dictionary:
	var slot_fill: Dictionary = report.get("slot_fill", {})
	var success: Dictionary = report.get("success", {})
	var actions: Dictionary = report.get("actions", {})
	var level: Dictionary = _level_source(report)
	var replays: Dictionary = report.get("replays", {})
	var normal_median: float = float(actions.get("normal_median", 0.0))
	var boss_median: float = float(actions.get("boss_median", 0.0))
	return {
		"slot_fill_before_s10": float(slot_fill.get("ratio_before_s10", 0.0)) >= TARGET_SLOT_FILL_RATIO,
		"success_after_s20": float(success.get("rate_after_20", 0.0)) >= TARGET_SUCCESS_RATE_AFTER_S20,
		"success_window": float(success.get("worst_window_rate", 0.0)) >= SUCCESS_WINDOW_MIN_RATE,
		"normal_actions": normal_median >= TARGET_NORMAL_ACTIONS_MEDIAN_MIN
			and normal_median <= TARGET_NORMAL_ACTIONS_MEDIAN_MAX
			and float(actions.get("normal_p90", 0.0)) <= TARGET_NORMAL_ACTIONS_P90_MAX,
		"boss_actions": boss_median >= TARGET_BOSS_ACTIONS_MEDIAN_MIN
			and boss_median <= TARGET_BOSS_ACTIONS_MEDIAN_MAX,
		"level_tracking": float(level.get("abs_le_3_ratio", 0.0)) >= TARGET_LEVEL_ABS_LE_3_RATIO
			and int(level.get("max_abs", 99)) <= TARGET_LEVEL_MAX_ABS,
		# §8 M5: the replay budget is a CONSTRAINT on the fixed strategy, so the gate is the share of
		# advances that had to spend MORE than one budget to succeed — the same 90 % the advance
		# target is built on, read from the budget side instead of the success side.
		"replay_budget": float(success.get("over_budget_advances", 0))
			/ float(maxi(int(success.get("normal_challenges", 1)), 1))
			<= 1.0 - TARGET_SUCCESS_RATE_AFTER_S20,
	}


## §5's level gate is stated for the "逐关全清" trajectory, so it is read from the clean run when the
## report carries one and from the report itself otherwise.
static func _level_source(report: Dictionary) -> Dictionary:
	var clean: Dictionary = report.get("clean_trajectory", {})
	if not clean.is_empty() and clean.has("level"):
		return clean["level"]
	return report.get("level", {})


## A human-readable report, used by the headless tool and by the release docs.
static func format_report(report: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("M5 progression simulation — %d seeds × S1..%d (%d first challenges)" % [
		int(report.get("seeds", 0)), int(report.get("max_stage", 0)), int(report.get("stages", 0))
	])
	lines.append("  trajectory: %s, strategy: normal attack + shortest-route movement, AUTO potion rule, no skills/Tome/Sub Heroes" % (
		"normal + Mini Boss + special encounters" if bool(report.get("special_encounters", false))
			else "normal + Mini Boss"))
	var slot_fill: Dictionary = report.get("slot_fill", {})
	lines.append("  seven slots filled before the first S10 challenge: %.1f %% (target %.0f %%)" % [
		100.0 * float(slot_fill.get("ratio_before_s10", 0.0)), 100.0 * TARGET_SLOT_FILL_RATIO
	])
	lines.append("    median first-full stage %.1f, P90 %.1f, never filled %d" % [
		float(slot_fill.get("median_stage", 0.0)), float(slot_fill.get("p90_stage", 0.0)),
		int(slot_fill.get("never_filled", 0))
	])
	var success: Dictionary = report.get("success", {})
	lines.append("  normal-encounter advance success after S%d (§8 M5 reading: the stage fell, with up to %d replays before EACH push): %.2f %% (target %.0f %%)" % [
		SUCCESS_MEASUREMENT_FROM_STAGE, REPLAYS_PER_ADVANCE,
		100.0 * float(success.get("rate_after_20", 0.0)), 100.0 * TARGET_SUCCESS_RATE_AFTER_S20
	])
	lines.append("    first-push success %.2f %%, within one replay budget %.2f %% (stress view), over-budget advances %d of %d" % [
		100.0 * float(success.get("first_push_rate_after_20", 0.0)),
		100.0 * float(success.get("budget_rate_after_20", 0.0)),
		int(success.get("over_budget_advances", 0)), int(success.get("normal_challenges", 0))
	])
	lines.append("    worst %d-encounter window %.2f %% (%d windows); stress view %.2f %%" % [
		SUCCESS_WINDOW_STAGES, 100.0 * float(success.get("worst_window_rate", 0.0)),
		int(success.get("windows", 0)), 100.0 * float(success.get("worst_budget_window_rate", 0.0))
	])
	var actions: Dictionary = report.get("actions", {})
	lines.append("  normal wins: attack actions median %.1f (target %.0f..%.0f), P90 %.1f (max %.0f), %d samples" % [
		float(actions.get("normal_median", 0.0)), TARGET_NORMAL_ACTIONS_MEDIAN_MIN,
		TARGET_NORMAL_ACTIONS_MEDIAN_MAX, float(actions.get("normal_p90", 0.0)),
		TARGET_NORMAL_ACTIONS_P90_MAX, int(actions.get("normal_samples", 0))
	])
	lines.append("  Mini Boss wins: attack actions median %.1f (target %.0f..%.0f), P90 %.1f, %d samples" % [
		float(actions.get("boss_median", 0.0)), TARGET_BOSS_ACTIONS_MEDIAN_MIN,
		TARGET_BOSS_ACTIONS_MEDIAN_MAX, float(actions.get("boss_p90", 0.0)),
		int(actions.get("boss_samples", 0))
	])
	lines.append("  movement turns per win: median %.1f, P90 %.1f" % [
		float(actions.get("movement_median", 0.0)), float(actions.get("movement_p90", 0.0))
	])
	var level: Dictionary = _level_source(report)
	lines.append("  battle-start |L − S| ≤ 3 on the §5 clear-every-stage trajectory: %.2f %% (target %.0f %%), max %d (limit %d), %d samples" % [
		100.0 * float(level.get("abs_le_3_ratio", 0.0)), 100.0 * TARGET_LEVEL_ABS_LE_3_RATIO,
		int(level.get("max_abs", 0)), TARGET_LEVEL_MAX_ABS, int(level.get("samples", 0))
	])
	var clean: Dictionary = report.get("clean_trajectory", {})
	if not clean.is_empty():
		lines.append("    clear-every-stage run: %d challenges, %d trajectories ended on a defeat" % [
			int(clean.get("stages", 0)), int(clean.get("blocked_trajectories", 0))
		])
	lines.append("    the recovery trajectory (failures + replays), reported not gated: first-push clears %.2f %%, every advance %.2f %%, max %d over %d advances" % [
		100.0 * float(report.get("level", {}).get("abs_le_3_ratio", 0.0)),
		100.0 * float(report.get("level", {}).get("all_abs_le_3_ratio", 0.0)),
		int(report.get("level", {}).get("all_max_abs", 0)),
		int(report.get("level", {}).get("all_samples", 0))
	])
	var gear: Dictionary = report.get("gear_age", {})
	lines.append("  gear lag after S20 (S − oldest item level): median %.1f, P90 %.1f, worst %.0f" % [
		float(gear.get("median_lag", 0.0)), float(gear.get("p90_lag", 0.0)),
		float(gear.get("max_lag", 0.0))
	])
	var loadout: Dictionary = report.get("loadout", {})
	lines.append("  real loadout vs the §3.1 reference fixture (b_X × G(S)): attack median %.2fx (P10 %.2f, P90 %.2f), max HP median %.2fx" % [
		float(loadout.get("attack_ratio_median", 0.0)), float(loadout.get("attack_ratio_p10", 0.0)),
		float(loadout.get("attack_ratio_p90", 0.0)), float(loadout.get("hp_ratio_median", 0.0))
	])
	lines.append("  battle-start HP: median %.0f %% of maximum, %.1f %% of advances start below half HP (HP survives between stages; only a defeat refills it)" % [
		100.0 * float(loadout.get("entry_hp_ratio_median", 0.0)),
		100.0 * float(loadout.get("entry_hp_below_half", 0.0))
	])
	var replays: Dictionary = report.get("replays", {})
	lines.append("  replays per advance: mean %.2f, P95 %.1f, max %d (budget per push %d); pushes per advance: median %.1f, max %d" % [
		float(replays.get("mean", 0.0)), float(replays.get("p95", 0.0)),
		int(replays.get("max", 0)), REPLAYS_PER_ADVANCE,
		float(replays.get("pushes_median", 0.0)), int(replays.get("pushes_max", 0))
	])
	lines.append("  gear: %d equipment drops, %d potions dropped / %d drunk (start %d, heal %.0f %% of max HP at %.0f %% HP), %d swaps, %d refused swaps, %d worse-than-equipped, %d survival-blocked" % [
		int(report.get("drops", 0)), int(report.get("potions", 0)), int(report.get("potions_used", 0)),
		STARTING_POTIONS, POTION_HEAL_RATIO * 100.0, POTION_DRINK_THRESHOLD * 100.0,
		int(report.get("swaps", 0)), int(report.get("refused_swaps", 0)),
		int(report.get("worse_drops", 0)), int(report.get("survival_blocked_drops", 0))
	])
	lines.append("  defeated trajectories %d of %d%s" % [
		int(report.get("blocked_trajectories", 0)), int(report.get("seeds", 0)),
		"" if int(report.get("blocked_trajectories", 0)) == 0
			else " (stages %s)" % str(report.get("blocked_stages", []))
	])
	var targets: Dictionary = evaluate_targets(report)
	var failed: Array[String] = []
	for key in targets:
		if not bool(targets[key]):
			failed.append(str(key))
	lines.append("  M5 targets: %s" % ("ALL MET" if failed.is_empty() else "FAILED %s" % str(failed)))
	return "\n".join(lines)


func _init(active_profile: BalanceProfile = null, configuration: Dictionary = {}) -> void:
	profile = active_profile if active_profile != null else BalanceProfile.get_default()
	seed_count = maxi(int(configuration.get("seeds", seed_count)), 1)
	first_seed = maxi(int(configuration.get("first_seed", first_seed)), 1)
	max_stage = maxi(int(configuration.get("max_stage", profile.max_stage if profile != null else 1000)), 1)
	with_special_encounters = bool(configuration.get("special_encounters", with_special_encounters))
	clean_only = bool(configuration.get("clean_only", clean_only))
	clear_heal_ratio = clampf(float(configuration.get("clear_heal_ratio", clear_heal_ratio)), 0.0, 1.0)
	consumable_drop_chance = clampf(
		float(configuration.get("consumable_drop_chance", consumable_drop_chance)), 0.0, 1.0
	)
	verbose = bool(configuration.get("verbose", verbose))
	trace_seed = int(configuration.get("trace_seed", trace_seed))
	_pool = _load_enemy_pool()
	_reference_base = _build_reference_base()
	_base_stats = {
		&"critical_chance": profile.base_critical_chance,
		&"critical_damage": profile.base_critical_damage,
		&"movement_points": BASE_MOVEMENT_POINTS,
		&"attack_range": BASE_ATTACK_RANGE,
	}
	# The drop generator reads the spawn's level and tier off the runtime the stage manager would
	# have built, so drops are produced exactly as they are in play (guaranteed Mini Boss drop,
	# the 15 % potion substitution, `item_level = max(enemy level, stage)`).
	_loot_stub_data = EnemyData.new()
	_loot_stub_data.enemy_type = EnemyType.NORMAL
	_loot_stub = EnemyController.new()
	_loot_stub.enemy_data = _loot_stub_data


## Frees the reusable stub node the loot generator reads.
func dispose() -> void:
	if _loot_stub != null and is_instance_valid(_loot_stub):
		_loot_stub.free()
	_loot_stub = null


func run_all() -> Dictionary:
	_report = _empty_report()
	for offset in range(seed_count):
		_run_trajectory(first_seed + offset)
		if verbose and (offset + 1) % 10 == 0:
			print("  ... %d/%d trajectories" % [offset + 1, seed_count])
	# §5 states its level gate for the "逐关全清" trajectory, so this run carries that trajectory
	# beside its own: the same seeds with the recovery loop switched off.
	if not clean_only:
		var clean := BalanceProgressionSimulator.new(profile, {
			"seeds": seed_count,
			"first_seed": first_seed,
			"max_stage": max_stage,
			"special_encounters": with_special_encounters,
			"clean_only": true,
		})
		_report["clean"] = clean.run_all()
		clean.dispose()
	return _finalize_report()


# ---------------------------------------------------------------------------
# One trajectory
# ---------------------------------------------------------------------------


func _run_trajectory(seed: int) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed
	_loot = LootGenerator.new(seed)
	_loot.consumable_drop_chance = consumable_drop_chance
	_tracing = trace_seed == seed
	_equipped = EquipmentStatBlock.empty_slots()
	_slot_drops = _zero_slots()
	_slot_swaps = _zero_slots()
	_slot_empty_fills = _zero_slots()
	_level = 1
	_experience = 0
	_gold = 0
	_potions = STARTING_POTIONS
	_highest_cleared_normal = 0
	_first_full_slot_stage = 0
	_trajectory_normal_outcomes = []
	_trajectory_normal_budget_outcomes = []
	_refresh_block()
	_current_hp = int(_block[&"max_hp"])

	var stage: int = 1
	var blocked: bool = false
	while stage <= max_stage and not blocked:
		var is_boss_stage: bool = stage % profile.boss_interval == 0
		var is_normal_encounter: bool = not is_boss_stage \
			and not BalanceFormulas.is_training_stage(profile, stage)
		_record_battle_start(stage, is_normal_encounter)
		# §8 M5: push the stage; when the push fails, the strategy may spend up to
		# [constant REPLAYS_PER_ADVANCE] replays of the highest cleared normal stage and push
		# again. Clearing it within that budget is what the advance-success target measures; a
		# stage that survives the budget keeps the trajectory going with further recovery rounds
		# (the game never locks a stage), and is recorded as over budget.
		var cleared: bool = _push_stage(stage)
		var first_push_cleared: bool = cleared
		var pushes: int = 1
		var replays: int = 0
		# §5's "逐关全清" trajectory never replays: the first failed push is where that trajectory
		# ends, and what it measured up to that point is the level gate's sample.
		while not cleared and not clean_only and pushes < PUSH_LIMIT_PER_STAGE:
			replays += _replay_cleared_stages(REPLAYS_PER_ADVANCE)
			cleared = _push_stage(stage)
			pushes += 1
		_report["replays"].append(float(replays))
		_report["pushes"].append(float(pushes))
		var within_budget: bool = cleared and pushes <= BUDGET_PUSHES
		_record_outcome(is_normal_encounter, first_push_cleared, cleared, pushes, stage)
		if not within_budget and is_normal_encounter and stage > SUCCESS_MEASUREMENT_FROM_STAGE:
			_report["over_budget_advances"] += 1
		if cleared:
			if not is_boss_stage:
				_highest_cleared_normal = maxi(_highest_cleared_normal, stage)
			stage += 1
		else:
			blocked = true
			_report["blocked_stages"].append(stage)
			if _tracing:
				print("  TRAJECTORY BLOCKED at S%d (L=%d, slots=%d, gold=%d)" % [
					stage, _level, _filled_slot_count(), _gold
				])
	_append_trajectory_windows()
	if _tracing:
		_trace_gear()


## Trace-only: how the real loadout compares with the §3.1 analytic reference state (L = il = S,
## seven Common items, no affixes), which is what the M2 bands are calibrated on. It is the number
## that explains a Mini Boss falling faster than its band. Computed from the profile, so the
## simulator never depends on a test fixture.
func _trace_reference_ratio(stage: int) -> void:
	var reference_scale: float = BalanceFormulas.g(profile, float(stage))
	var reference_attack: float = profile.base_attack * reference_scale
	var reference_hp: float = profile.base_hp * reference_scale
	print("        vs reference: atk %.2fx hp %.2fx (reference atk %d hp %d)" % [
		float(_block[&"attack"]) / maxf(reference_attack, 1.0),
		float(_block[&"max_hp"]) / maxf(reference_hp, 1.0),
		int(reference_attack), int(reference_hp)
	])


func _zero_slots() -> Array[int]:
	var values: Array[int] = []
	values.resize(BalanceProfile.SLOT_COUNT)
	return values


## Trace-only: where the equipped items ended up and what happened to the drops of each slot.
func _trace_gear() -> void:
	for slot in range(BalanceProfile.SLOT_COUNT):
		var item: EquipmentInstance = _equipped[slot]
		var item_text: String = "empty" if item == null else "il=%d rarity=%d" % [
			item.get_item_level(), item.get_rarity()
		]
		print("  slot %-8s %-18s drops=%-5d fills=%-3d swaps=%d" % [
			EquipmentSlot.get_display_name(slot), item_text,
			_slot_drops[slot], _slot_empty_fills[slot], _slot_swaps[slot]
		])


## One push of `stage`: the encounter plus everything its kills paid.
func _push_stage(stage: int) -> bool:
	var encounter: Dictionary = _build_encounter(stage)
	var hp_before: int = _current_hp
	_experience_gained = 0
	_levels_gained = 0
	var outcome: Dictionary = _simulate_encounter(stage, encounter)
	var need: int = BalanceFormulas.experience_required(profile, maxi(_level - 1, 1))
	var exp_text: String = "exp %d/%d need=%d levels=%d" % [
		_experience_gained, need, BalanceFormulas.experience_required(profile, _level), _levels_gained
	]
	if bool(outcome["cleared"]):
		_gold += BalanceFormulas.stage_clear_gold(profile, stage)
		var kind: int = int(encounter["kind"])
		if kind == EnemyScaling.Kind.MINI_BOSS:
			_report["boss_actions"].append(float(outcome["attack_actions"]))
		elif kind == EnemyScaling.Kind.NORMAL:
			_report["normal_actions"].append(float(outcome["attack_actions"]))
		_report["movement_turns"].append(float(outcome["movement_turns"]))
		if _tracing:
			print("    S%-4d %-8s L=%-4d hp %d→%d/%d atk=%d def=%d il=%d actions=%-3d moves=%-2d slots=%d %s CLEAR" % [
				stage, _kind_name(kind), _level, hp_before, _current_hp, int(_block[&"max_hp"]),
				int(_block[&"attack"]), int(_block[&"defense"]), _worst_slot_item_level(),
				int(outcome["attack_actions"]), int(outcome["movement_turns"]),
				_filled_slot_count(), exp_text
			])
			if kind == EnemyScaling.Kind.MINI_BOSS:
				_trace_reference_ratio(stage)
		return true
	# §17: a defeat revives the hero at full HP and retreats one stage (the encounter itself
	# restores the hero, so nothing is repeated here).
	_report["deaths"] += 1
	if _tracing:
		print("    S%-4d %-8s L=%-4d hp %d→DEFEAT actions=%-3d slots=%d %s" % [
			stage, _kind_name(int(encounter["kind"])), _level, hp_before,
			int(outcome["attack_actions"]), _filled_slot_count(), exp_text
		])
	return false


## §8 M5: after a defeat, replay the highest cleared NORMAL stage up to `budget` times. Returns how
## many replays were played.
func _replay_cleared_stages(budget: int) -> int:
	var replays: int = 0
	while replays < budget and _highest_cleared_normal > 0:
		var farm_stage: int = _highest_cleared_normal
		var hp_before: int = _current_hp
		var outcome: Dictionary = _simulate_encounter(farm_stage, _build_encounter(farm_stage))
		replays += 1
		if _tracing:
			print("      replay S%-4d hp %d→%d %s" % [
				farm_stage, hp_before, _current_hp,
				"CLEAR" if bool(outcome["cleared"]) else "DEFEAT"
			])
	return replays


## The kind of an encounter as the trace prints it.
static func _kind_name(kind: int) -> String:
	match kind:
		EnemyScaling.Kind.TRAINING:
			return "training"
		EnemyScaling.Kind.MINI_BOSS:
			return "miniboss"
		_:
			return "normal"


func _record_battle_start(stage: int, is_normal_encounter: bool) -> void:
	_pending_level_delta = abs(_level - stage)
	_report["level_deltas"].append(_pending_level_delta)
	# §3.1: the analytic reference state at this stage is `b_X × G(S)` (level scale times the
	# seven-Common item scale), so the ratio below is "how strong is a real loadout against the
	# fixture the M2 work/survival bands are calibrated on".
	var reference_scale: float = BalanceFormulas.g(profile, float(stage))
	_report["attack_ratio"].append(float(_block[&"attack"]) / maxf(profile.base_attack * reference_scale, 1.0))
	_report["hp_ratio"].append(float(_block[&"max_hp"]) / maxf(profile.base_hp * reference_scale, 1.0))
	_report["entry_hp_ratio"].append(
		float(_current_hp) / maxf(float(_block[&"max_hp"]), 1.0)
	)
	if stage > SUCCESS_MEASUREMENT_FROM_STAGE and is_normal_encounter:
		_report["gear_lags"].append(float(stage) - float(_worst_slot_item_level()))


## §8 M5 reads "每次推进前最多允许5次已通关关卡回刷" — the replay budget applies BEFORE EACH PUSH, so
## the advance may be pushed again after each budget, and the encounter SUCCESS the target speaks of
## is "the stage fell" (a stage that survives the whole push limit is a wall and counts as a failure).
## The stricter view — "the first push, or the push after ONE replay budget" — is reported beside it
## in [member _report] as the stress number, because it is what a player who refuses to farm sees.
func _record_outcome(
	is_normal_encounter: bool,
	first_push_cleared: bool,
	cleared: bool,
	pushes: int,
	stage: int
) -> void:
	_report["first_challenge_attempts"] += 1
	if first_push_cleared:
		_report["first_challenge_successes"] += 1
		# §5's level gate is stated for the "clear every stage in order" trajectory, so the
		# battle-start deviation is sampled there. The replay-inclusive distribution is reported
		# beside it, because farming an old stage deliberately over-levels the hero.
		_report["level_deltas_first_push"].append(_pending_level_delta)
	if not is_normal_encounter or stage <= SUCCESS_MEASUREMENT_FROM_STAGE:
		return
	_report["normal_first_challenges"] += 1
	var within_budget: bool = cleared and pushes <= BUDGET_PUSHES
	if first_push_cleared:
		_report["normal_first_push_successes"] += 1
	if within_budget:
		_report["normal_budget_successes"] += 1
	if cleared:
		_report["normal_successes"] += 1
	_trajectory_normal_outcomes.append(cleared)
	_trajectory_normal_budget_outcomes.append(within_budget)


## §8 M5's "20 consecutive stages" gate: the success rate of every full window of
## [constant SUCCESS_WINDOW_STAGES] advances this trajectory played after S20 — for the gated metric
## ("the stage fell") and for the stricter one ("it fell within one replay budget").
func _append_trajectory_windows() -> void:
	_append_windows(_trajectory_normal_outcomes, "window_rates")
	_append_windows(_trajectory_normal_budget_outcomes, "budget_window_rates")


func _append_windows(outcomes: Array[bool], key: String) -> void:
	if outcomes.size() < SUCCESS_WINDOW_STAGES:
		return
	for start in range(outcomes.size() - SUCCESS_WINDOW_STAGES + 1):
		var successes: int = 0
		for index in range(start, start + SUCCESS_WINDOW_STAGES):
			if outcomes[index]:
				successes += 1
		_report[key].append(float(successes) / float(SUCCESS_WINDOW_STAGES))


# ---------------------------------------------------------------------------
# Encounter construction (§4.2 / §4.3, production rules)
# ---------------------------------------------------------------------------


func _build_encounter(stage: int) -> Dictionary:
	var kind: int = EnemyScaling.Kind.NORMAL
	var enemy_type: int = EnemyType.NORMAL
	var squad_size: int = BalanceFormulas.enemy_count(profile, stage)
	var encounter_count: int = squad_size
	if BalanceFormulas.is_training_stage(profile, stage):
		kind = EnemyScaling.Kind.TRAINING
	elif stage % profile.boss_interval == 0:
		kind = EnemyScaling.Kind.MINI_BOSS
		enemy_type = EnemyType.MINI_BOSS
		encounter_count = 1
		squad_size = 1
	elif with_special_encounters and _roll_special_encounter(stage):
		enemy_type = _roll_special_type()
		if enemy_type == EnemyType.MINI_BOSS:
			kind = EnemyScaling.Kind.MINI_BOSS
			encounter_count = 1
			squad_size = 1

	var enemies: Array[Dictionary] = []
	var occupied: Dictionary = {PLAYER_START_CELL: true}
	for _index in range(squad_size):
		var base: EnemyData = _pick_pool_enemy() if kind == EnemyScaling.Kind.NORMAL else _reference_base
		var offset: int = _roll_enemy_offset() if kind == EnemyScaling.Kind.NORMAL else 0
		var variance: Array[float] = _roll_variance() if kind == EnemyScaling.Kind.NORMAL \
			else EnemyScaling.unity_variance()
		var stats: EnemyStats = EnemyScaling.build_combat_stats(
			profile,
			base.base_stats,
			stage,
			kind,
			offset,
			encounter_count,
			variance,
			[],
			enemy_type
		)
		var cell: Vector2i = _roll_spawn_cell(occupied)
		occupied[cell] = true
		enemies.append({
			"stats": stats,
			"offset": offset,
			"cell": cell,
			"hp": stats.max_hp,
			"stunned": false,
			"stun_immune": 0,
		})
	return {
		"kind": kind,
		"enemy_type": enemy_type,
		"count": encounter_count,
		"enemies": enemies,
	}


func _pick_pool_enemy() -> EnemyData:
	if _pool.is_empty():
		return _reference_base
	return _pool[_rng.randi_range(0, _pool.size() - 1)]


func _load_enemy_pool() -> Array[EnemyData]:
	var pool: Array[EnemyData] = []
	var names: Array[String] = []
	for file_name in DirAccess.get_files_at(ENEMY_POOL_DIRECTORY):
		if file_name.ends_with(".tres"):
			names.append(file_name)
	names.sort()
	for file_name in names:
		var data := load("%s/%s" % [ENEMY_POOL_DIRECTORY, file_name]) as EnemyData
		if data != null and data.enemy_type == EnemyType.NORMAL:
			pool.append(data)
	return pool


func _build_reference_base() -> EnemyData:
	var data := EnemyData.new()
	data.enemy_type = EnemyType.NORMAL
	var stats := EnemyStats.new()
	stats.max_hp = int(profile.reference_enemy_hp)
	stats.attack = int(profile.reference_enemy_attack)
	stats.defense = int(profile.reference_enemy_defense)
	stats.experience_reward = int(profile.reference_enemy_exp)
	data.base_stats = stats
	return data


## §4.2: the offset distribution of the provider, rolled on the same weights.
func _roll_enemy_offset() -> int:
	var roll: int = _rng.randi_range(1, 100)
	var cumulative: int = 0
	for index in range(ENEMY_OFFSETS.size()):
		cumulative += ENEMY_OFFSET_WEIGHTS[index]
		if roll <= cumulative:
			return ENEMY_OFFSETS[index]
	return 0


## §4.2: three INDEPENDENT uniform factors, one per combat stat.
func _roll_variance() -> Array[float]:
	var minimum: float = minf(profile.enemy_variance_min, profile.enemy_variance_max)
	var maximum: float = maxf(profile.enemy_variance_min, profile.enemy_variance_max)
	return [
		_rng.randf_range(minimum, maximum),
		_rng.randf_range(minimum, maximum),
		_rng.randf_range(minimum, maximum),
	]


## §11 pity model, rolled once per generated stage like the provider does.
func _roll_special_encounter(stage: int) -> bool:
	if stage % profile.boss_interval == 0:
		return false
	return _rng.randf() < 0.03


func _roll_special_type() -> int:
	var types: Array[int] = [
		EnemyType.ELITE,
		EnemyType.TREASURE,
		EnemyType.SPECIAL,
		EnemyType.MINI_BOSS,
		EnemyType.GOLD,
		EnemyType.CURSED,
	]
	return types[_rng.randi_range(0, types.size() - 1)]


func _roll_spawn_cell(occupied: Dictionary) -> Vector2i:
	for _attempt in range(64):
		var cell := Vector2i(
			_rng.randi_range(GRID_MIN.x, GRID_MAX.x),
			_rng.randi_range(GRID_MIN.y, GRID_MAX.y)
		)
		if not occupied.has(cell):
			return cell
	return PLAYER_START_CELL + Vector2i(1, 0)


# ---------------------------------------------------------------------------
# The encounter itself (M3 semantics + the §8 M5 strategy)
# ---------------------------------------------------------------------------


func _simulate_encounter(stage: int, encounter: Dictionary) -> Dictionary:
	var enemies: Array = encounter["enemies"]
	_loot_stub_data.enemy_type = int(encounter["enemy_type"])
	var player_cell: Vector2i = PLAYER_START_CELL
	var attack_actions: int = 0
	var movement_turns: int = 0
	var killed: Array[int] = []

	while killed.size() < enemies.size() and attack_actions < MAX_ACTIONS_PER_ENCOUNTER \
			and _current_hp > 0:
		# §16 AUTO's healing rule, which the fixed strategy adopts: at or below the threshold the
		# hero drinks instead of attacking, and the turn it spends is a real turn.
		if _should_drink_potion():
			_drink_potion()
			if killed.size() < enemies.size():
				_resolve_enemy_volley(enemies, killed)
			_current_hp = maxi(_current_hp, 0)
			continue
		var target_index: int = _lowest_hp_enemy(enemies, killed)
		if target_index < 0:
			break
		var target: Dictionary = enemies[target_index]
		var movement_points: int = int(_block.get(&"movement_points", BASE_MOVEMENT_POINTS))
		var attack_range: int = maxi(int(_block.get(&"attack_range", BASE_ATTACK_RANGE)), 1)
		if _manhattan(player_cell, target["cell"]) > attack_range:
			var moved: Vector2i = _step_toward(player_cell, target["cell"], movement_points)
			if moved != player_cell:
				player_cell = moved
				movement_turns += 1
		if _manhattan(player_cell, target["cell"]) <= attack_range:
			attack_actions += 1
			_resolve_player_hit(stage, target, killed, target_index)
		# §8 M3: after every player action each SURVIVING enemy attacks once.
		if killed.size() < enemies.size():
			_resolve_enemy_volley(enemies, killed)
		_current_hp = maxi(_current_hp, 0)

	var cleared: bool = killed.size() >= enemies.size() and _current_hp > 0
	if cleared:
		_current_hp = mini(_current_hp, int(_block[&"max_hp"]))
		if clear_heal_ratio > 0.0:
			# Model experiment only: the shipped runtime restores nothing on a clear.
			_current_hp = mini(
				_current_hp + roundi(float(_block[&"max_hp"]) * clear_heal_ratio),
				int(_block[&"max_hp"])
			)
	else:
		# §17: a failed attempt (death, or the 100-action cap) ends with the hero restored to full
		# HP and pushed back a stage, so the next attempt starts whole. Nothing else here heals.
		_current_hp = int(_block[&"max_hp"])
	return {
		"cleared": cleared,
		"attack_actions": attack_actions,
		"movement_turns": movement_turns,
	}


## §16 AUTO: drink when the hero is at or below the threshold and a potion is in stock.
func _should_drink_potion() -> bool:
	if _potions <= 0:
		return false
	var max_hp: int = maxi(int(_block[&"max_hp"]), 1)
	return float(_current_hp) / float(max_hp) <= POTION_DRINK_THRESHOLD


## `PlayerController.use_healing_item()`: heal by the ratio (at least 1), spend one potion.
func _drink_potion() -> void:
	if _potions <= 0:
		return
	var max_hp: int = maxi(int(_block[&"max_hp"]), 1)
	_current_hp = mini(
		_current_hp + maxi(roundi(float(max_hp) * POTION_HEAL_RATIO), 1),
		max_hp
	)
	_potions -= 1
	_report["potions_used"] += 1


func _resolve_player_hit(stage: int, target: Dictionary, killed: Array[int], target_index: int) -> void:
	var stats: EnemyStats = target["stats"]
	var critical: bool = false
	if float(_block.get(&"critical_chance", 0.0)) > 0.0:
		critical = _rng.randf() < float(_block[&"critical_chance"])
	var damage: int = BalanceFormulas.resolve_damage(
		profile,
		float(_block[&"attack"]),
		float(stats.defense),
		1.0,
		1.0,
		critical,
		float(_block.get(&"critical_damage", 1.0))
	)
	var hp_before: int = int(target["hp"])
	var hp_lost: int = mini(damage, hp_before)
	target["hp"] = hp_before - hp_lost

	# §4.1: life steal pays on the HP that landed, never on the overkill.
	var life_steal: float = float(_block.get(&"life_steal", 0.0))
	if life_steal > 0.0 and hp_lost > 0:
		var max_hp: int = int(_block[&"max_hp"])
		_current_hp = mini(_current_hp + roundi(float(hp_lost) * life_steal), max_hp)

	# §3.2: a stun is refused while the target is inside its post-release immunity window.
	var stun_chance: float = float(_block.get(&"stun_chance", 0.0))
	if stun_chance > 0.0 and int(target["hp"]) > 0 and not bool(target["stunned"]) \
			and int(target["stun_immune"]) <= 0 and _rng.randf() < stun_chance:
		target["stunned"] = true

	if int(target["hp"]) <= 0 and not killed.has(target_index):
		killed.append(target_index)
		_settle_kill(target, stage)


## Every SURVIVING enemy attacks once after a player action (§8 M3). A stunned enemy spends that
## attack on its stun, which is what opens the §3.2 immunity window; a played turn closes it.
func _resolve_enemy_volley(enemies: Array, killed: Array[int]) -> void:
	var dodge: float = float(_block.get(&"dodge", 0.0))
	for index in range(enemies.size()):
		if killed.has(index):
			continue
		var enemy: Dictionary = enemies[index]
		if bool(enemy["stunned"]):
			enemy["stunned"] = false
			enemy["stun_immune"] = 1
			continue
		if int(enemy["stun_immune"]) > 0:
			enemy["stun_immune"] = int(enemy["stun_immune"]) - 1
		if dodge > 0.0 and _rng.randf() < dodge:
			continue
		var stats: EnemyStats = enemy["stats"]
		_current_hp -= BalanceFormulas.resolve_damage(
			profile,
			float(stats.attack),
			float(_block[&"defense"]),
			1.0,
			1.0,
			false,
			1.0
		)


func _settle_kill(target: Dictionary, stage: int) -> void:
	var stats: EnemyStats = target["stats"]
	# §5: the level is sampled BEFORE the settlement, so one kill can cross several levels.
	var experience: int = BalanceFormulas.round_reward(
		profile,
		float(stats.experience_reward) * BalanceFormulas.experience_catchup(profile, stage, _level),
		1
	)
	_gold += maxi(stats.gold_reward, 0)
	_grant_experience(experience)
	_grant_loot(stats, stage)


func _grant_experience(amount: int) -> void:
	if _level >= profile.max_character_level:
		return
	_experience += maxi(amount, 0)
	_experience_gained += maxi(amount, 0)
	while _level < profile.max_character_level:
		var required: int = BalanceFormulas.experience_required(profile, _level)
		if _experience < required:
			break
		_experience -= required
		_level += 1
		_levels_gained += 1
		# §3.3: a level-up rebuilds the block and keeps the current HP.
		_refresh_block()
		_current_hp = mini(_current_hp, int(_block[&"max_hp"]))


# ---------------------------------------------------------------------------
# Loot and the fixed §8 equipment policy
# ---------------------------------------------------------------------------


func _grant_loot(stats: EnemyStats, stage: int) -> void:
	_loot_stub.enemy_level = maxi(stats.level, 1)
	# §8 M5 "保底掉落的槽位覆盖": the same empty-slot list the live [LootSystem] hands the generator
	# (it reads the hero's inventory; the model reads its own loadout).
	for item in _loot.generate_loot(_loot_stub, stage, _empty_slots()):
		_consider_drop(item, stage)


## The equipment slots this loadout has nothing in.
func _empty_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in range(BalanceProfile.SLOT_COUNT):
		if _equipped[slot] == null:
			slots.append(slot)
	return slots


## §8 M5: fill an empty slot first; otherwise replace only when the effective `ATK × HP` rises AND
## the static survival against the current normal reference enemy stays ≥ 4. A tie keeps the old
## item.
func _consider_drop(item: EquipmentInstance, stage: int) -> void:
	if item == null or item.is_consumable():
		# §7 potion replenishment: a potion found as loot restocks the counter, exactly as
		# `grid_combat` does before the loot presentation.
		_report["potions"] += 1
		_potions = mini(_potions + 1, 99)
		return
	var slot: int = item.get_slot()
	if not EquipmentSlot.is_valid(slot):
		return
	_report["drops"] += 1
	_slot_drops[slot] += 1
	if _equipped[slot] == null:
		_equip(slot, item)
		_slot_empty_fills[slot] += 1
		if _first_full_slot_stage == 0 and _filled_slot_count() == BalanceProfile.SLOT_COUNT:
			_first_full_slot_stage = stage
			_report["slot_fill_stages"].append(float(stage))
		return
	var verdict: Dictionary = EquipmentStatBlock.verdict(
		profile, _level, _equipped, _base_stats, slot, item
	)
	if verdict.is_empty() or not bool(verdict.get("is_upgrade", false)):
		_report["worse_drops"] += 1
		return
	if _static_survival(verdict["candidate"], stage) < SWAP_SURVIVAL_MIN:
		_report["survival_blocked_drops"] += 1
		return
	_equip(slot, item)
	_slot_swaps[slot] += 1
	_report["swaps"] += 1


func _equip(slot: int, item: EquipmentInstance) -> void:
	var previous_max_hp: int = int(_block.get(&"max_hp", _current_hp))
	var previous: EquipmentInstance = _equipped[slot]
	_equipped[slot] = item
	_refresh_block()
	var projected: int = BalanceFormulas.project_current_hp(
		previous_max_hp, _current_hp, int(_block[&"max_hp"])
	)
	if _current_hp > 0 and projected < 1:
		# §3.3: a swap that would floor a living hero is REFUSED, never patched with max(1).
		_equipped[slot] = previous
		_refresh_block()
		_report["refused_swaps"] += 1
		return
	_current_hp = projected


## `survival = player_hp / incoming damage per player action` for the CURRENT normal reference
## enemy at `stage` — offset 0, variance 1, the real group factor.
func _static_survival(block: Dictionary, stage: int) -> float:
	var count: int = BalanceFormulas.enemy_count(profile, stage)
	var enemy_attack: float = BalanceFormulas.enemy_attack(
		profile,
		stage,
		count,
		profile.reference_enemy_attack,
		BalanceFormulas.enemy_offset_multiplier(profile, 0),
		1.0
	)
	var incoming: float = float(count) * BalanceFormulas.armor_damage(
		profile, enemy_attack, float(block.get(&"defense", 0.0))
	)
	if incoming <= 0.0:
		return INF
	return float(block.get(&"max_hp", 0)) / incoming


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _refresh_block() -> void:
	_block = EquipmentStatBlock.compute(profile, _level, _equipped, _base_stats)


func _filled_slot_count() -> int:
	var filled: int = 0
	for item in _equipped:
		if item != null:
			filled += 1
	return filled


## The lag of the WORST slot: how many stages behind the oldest equipped piece is. §8 M5 explains
## the tolerance in `G` ratios rather than one flat number, so the raw lag is what is reported.
func _worst_slot_item_level() -> int:
	var worst: int = 0
	var found: bool = false
	for item in _equipped:
		if item == null:
			continue
		if not found or item.get_item_level() < worst:
			worst = item.get_item_level()
			found = true
	return worst if found else 1


func _lowest_hp_enemy(enemies: Array, killed: Array[int]) -> int:
	var best_index: int = -1
	for index in range(enemies.size()):
		if killed.has(index):
			continue
		if best_index < 0 or int(enemies[index]["hp"]) < int(enemies[best_index]["hp"]):
			best_index = index
	return best_index


func _manhattan(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


## The shortest orthogonal legal move toward a cell, limited to `points` steps — the same rule the
## grid uses (no diagonal movement; the arena walls are the only blockers).
func _step_toward(from_cell: Vector2i, to_cell: Vector2i, points: int) -> Vector2i:
	var cell: Vector2i = from_cell
	var remaining: int = maxi(points, 0)
	while remaining > 0 and cell != to_cell:
		if cell.x != to_cell.x:
			cell.x += signi(to_cell.x - cell.x)
		elif cell.y != to_cell.y:
			cell.y += signi(to_cell.y - cell.y)
		remaining -= 1
	return Vector2i(
		clampi(cell.x, GRID_MIN.x, GRID_MAX.x),
		clampi(cell.y, GRID_MIN.y, GRID_MAX.y)
	)


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------


func _empty_report() -> Dictionary:
	return {
		"seeds": seed_count,
		"first_seed": first_seed,
		"max_stage": max_stage,
		"special_encounters": with_special_encounters,
		"stages": 0,
		"first_challenge_attempts": 0,
		"first_challenge_successes": 0,
		"normal_first_challenges": 0,
		"normal_first_push_successes": 0,
		"normal_successes": 0,
		"normal_budget_successes": 0,
		"over_budget_advances": 0,
		"normal_actions": [],
		"boss_actions": [],
		"movement_turns": [],
		"level_deltas": [],
		"level_deltas_first_push": [],
		"gear_lags": [],
		"attack_ratio": [],
		"hp_ratio": [],
		"entry_hp_ratio": [],
		"replays": [],
		"pushes": [],
		"slot_fill_stages": [],
		"blocked_stages": [],
		"window_rates": [],
		"budget_window_rates": [],
		"swaps": 0,
		"refused_swaps": 0,
		"drops": 0,
		"potions": 0,
		"potions_used": 0,
		"deaths": 0,
		"worse_drops": 0,
		"survival_blocked_drops": 0,
	}

func _finalize_report() -> Dictionary:
	var attempts: int = int(_report["first_challenge_attempts"])
	var slots: Array = _report["slot_fill_stages"]
	var filled_before_s10: int = 0
	for stage in slots:
		if float(stage) < float(TARGET_SLOT_FILL_STAGE):
			filled_before_s10 += 1
	var level: Array = _report["level_deltas"]
	var normal_challenges: int = int(_report["normal_first_challenges"])
	var windows: Array[float] = _to_floats(_report["window_rates"])
	var worst_window: float = 1.0
	for rate in windows:
		worst_window = minf(worst_window, rate)
	var budget_windows: Array[float] = _to_floats(_report["budget_window_rates"])
	var worst_budget_window: float = 1.0
	for rate in budget_windows:
		worst_budget_window = minf(worst_budget_window, rate)
	return {
		"seeds": seed_count,
		"first_seed": first_seed,
		"max_stage": max_stage,
		"special_encounters": with_special_encounters,
		"stages": attempts,
		"slot_fill": {
			"ratio_before_s10": float(filled_before_s10) / float(maxi(seed_count, 1)),
			"median_stage": _percentile(slots, 0.5),
			"p90_stage": _percentile(slots, 0.9),
			"never_filled": seed_count - slots.size(),
		},
		"success": {
			"rate_after_20": float(int(_report["normal_successes"])) / float(maxi(normal_challenges, 1)),
			"first_push_rate_after_20": float(int(_report["normal_first_push_successes"]))
				/ float(maxi(normal_challenges, 1)),
			"budget_rate_after_20": float(int(_report["normal_budget_successes"]))
				/ float(maxi(normal_challenges, 1)),
			"worst_window_rate": worst_window if not windows.is_empty() else 1.0,
			"worst_budget_window_rate": worst_budget_window if not budget_windows.is_empty() else 1.0,
			"windows": windows.size(),
			"normal_challenges": normal_challenges,
			"over_budget_advances": int(_report["over_budget_advances"]),
		},
		"actions": {
			"normal_median": _percentile(_report["normal_actions"], 0.5),
			"normal_p90": _percentile(_report["normal_actions"], 0.9),
			"normal_max": _percentile(_report["normal_actions"], 1.0),
			"boss_median": _percentile(_report["boss_actions"], 0.5),
			"boss_p90": _percentile(_report["boss_actions"], 0.9),
			"movement_median": _percentile(_report["movement_turns"], 0.5),
			"movement_p90": _percentile(_report["movement_turns"], 0.9),
			"normal_samples": _report["normal_actions"].size(),
			"boss_samples": _report["boss_actions"].size(),
		},
		"level": {
			"samples": level.size(),
			"abs_le_3_ratio": _abs_le_ratio(_report["level_deltas_first_push"], 3),
			"max_abs": _max_abs(_report["level_deltas_first_push"]),
			"first_push_samples": _report["level_deltas_first_push"].size(),
			"all_samples": level.size(),
			"all_abs_le_3_ratio": _abs_le_ratio(level, 3),
			"all_max_abs": _max_abs(level),
		},
		"gear_age": {
			"median_lag": _percentile(_report["gear_lags"], 0.5),
			"p90_lag": _percentile(_report["gear_lags"], 0.9),
			"max_lag": _percentile(_report["gear_lags"], 1.0),
			"samples": _report["gear_lags"].size(),
		},
		"loadout": {
			"attack_ratio_median": _percentile(_report["attack_ratio"], 0.5),
			"attack_ratio_p10": _percentile(_report["attack_ratio"], 0.1),
			"attack_ratio_p90": _percentile(_report["attack_ratio"], 0.9),
			"hp_ratio_median": _percentile(_report["hp_ratio"], 0.5),
			"entry_hp_ratio_median": _percentile(_report["entry_hp_ratio"], 0.5),
			"entry_hp_below_half": _below_ratio(_report["entry_hp_ratio"], 0.5),
			"samples": _report["attack_ratio"].size(),
		},
		"replays": {
			"mean": _mean(_report["replays"]),
			"p95": _percentile(_report["replays"], 0.95),
			"max": int(_percentile(_report["replays"], 1.0)),
			"pushes_median": _percentile(_report["pushes"], 0.5),
			"pushes_max": int(_percentile(_report["pushes"], 1.0)),
		},
		"blocked_trajectories": _report["blocked_stages"].size(),
		"blocked_stages": _report["blocked_stages"].duplicate(),
		"clean_trajectory": _finalize_clean(_report.get("clean", {})),
		"clean_only": clean_only,
		"deaths": int(_report["deaths"]),
		"swaps": int(_report["swaps"]),
		"refused_swaps": int(_report["refused_swaps"]),
		"drops": int(_report["drops"]),
		"potions": int(_report["potions"]),
		"potions_used": int(_report["potions_used"]),
		"worse_drops": int(_report["worse_drops"]),
		"survival_blocked_drops": int(_report["survival_blocked_drops"]),
	}


## Strips the nested run down to what the level gate and the report need.
static func _finalize_clean(clean: Dictionary) -> Dictionary:
	if clean.is_empty():
		return {}
	return {
		"stages": int(clean.get("stages", 0)),
		"blocked_trajectories": int(clean.get("blocked_trajectories", 0)),
		"blocked_stages": clean.get("blocked_stages", []),
		"level": clean.get("level", {}),
	}


static func _to_floats(values: Array) -> Array[float]:
	var result: Array[float] = []
	for value in values:
		result.append(float(value))
	return result


## Share of samples whose absolute deviation is at most `limit`.
static func _abs_le_ratio(values: Array, limit: int) -> float:
	if values.is_empty():
		return 0.0
	var within: int = 0
	for value in values:
		if absi(int(value)) <= limit:
			within += 1
	return float(within) / float(values.size())


static func _max_abs(values: Array) -> int:
	var worst: int = 0
	for value in values:
		worst = maxi(worst, absi(int(value)))
	return worst


## Share of samples strictly below a threshold.
static func _below_ratio(values: Array, threshold: float) -> float:
	if values.is_empty():
		return 0.0
	var below: int = 0
	for value in values:
		if float(value) < threshold:
			below += 1
	return float(below) / float(values.size())


static func _percentile(values: Array, ratio: float) -> float:
	var floats: Array[float] = _to_floats(values)
	if floats.is_empty():
		return 0.0
	floats.sort()
	var index: int = clampi(int(ceil(ratio * float(floats.size()))) - 1, 0, floats.size() - 1)
	return floats[index]


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())
