extends SceneTree

const ServiceScript = preload("res://scripts/sub_hero/sub_hero_summon_service.gd")
const TableScript = preload("res://scripts/sub_hero/sub_hero_summon_table.gd")
const PlayerScript = preload("res://scripts/player/player_controller.gd")
const ProgressionScript = preload("res://scripts/player/player_progression.gd")
const QualityScript = preload("res://scripts/sub_hero/sub_hero_quality.gd")
const PROFILE_PATH: String = BalanceProfile.DEFAULT_PROFILE_PATH

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := load(PROFILE_PATH) as BalanceProfile
	var player: PlayerController = PlayerScript.new()
	var player_progression: PlayerProgression = ProgressionScript.new()
	player_progression.balance_profile = profile
	player_progression.gold = 200000
	player.player_progression = player_progression
	var service: SubHeroSummonService = ServiceScript.new()
	service.balance_profile = profile
	var table: SubHeroSummonTable = TableScript.new()
	table.common_weight = 0.0
	table.rare_weight = 100.0
	table.legendary_weight = 0.0
	service.summon_table = table
	service.set_random_seed(7)

	# §6.2: an empty collection sits on the price FLOOR, which is the shop's existing entry gate.
	var first_expected_cost: int = BalanceFormulas.sub_hero_summon_cost(profile, 0)
	_expect(first_expected_cost == profile.summon_gold_floor, "an empty collection costs the floor price, got %d" % first_expected_cost)
	_expect(service.calculate_summon_cost(player) == first_expected_cost, "the service quotes the same price as the formula")
	var gold_before_first: int = player_progression.gold
	var first_result := service.summon(player)
	_expect(bool(first_result.get("success")), "summon should succeed when the player can afford it")
	_expect(int(first_result.get("cost")) == first_expected_cost, "the result reports the quoted cost")
	_expect(int(first_result.get("data").quality) == QualityScript.RARE, "summon should use the configured rare-only weight")
	_expect(bool(first_result.get("is_new")), "first summon should create a new Sub Hero")
	_expect(player_progression.gold == gold_before_first - first_expected_cost, "summon spends exactly the quoted cost")

	# §6.2: the price now depends on the WHOLE collection, so each further summon is priced from
	# the draws already owned — and a failed summon costs nothing.
	var duplicate_result: Dictionary = {}
	for _summon_index in 3:
		var expected_cost: int = service.calculate_summon_cost(player)
		_expect(
			expected_cost == BalanceFormulas.sub_hero_summon_cost(profile, service.get_owned_draws(player)),
			"every summon is priced from the collection it will extend"
		)
		var gold_before: int = player_progression.gold
		var owned_count_before: int = player.get_sub_hero_progression().get_owned_count()
		var next_result := service.summon(player)
		_expect(bool(next_result.get("success")), "summon should succeed while the player can afford it")
		_expect(int(next_result.get("cost")) == expected_cost, "the charged cost is the quoted one")
		_expect(player_progression.gold == gold_before - expected_cost, "the purse moves by exactly the quoted cost")
		if not bool(next_result.get("is_new", true)) and duplicate_result.is_empty():
			duplicate_result = next_result
			_expect(player.get_sub_hero_progression().get_owned_count() == owned_count_before, "duplicate should not add a second owned entry")
	_expect(not duplicate_result.is_empty(), "a repeated result should be produced after four summons from three rare heroes")
	_expect(not bool(duplicate_result.get("is_new")), "repeated hero should be reported as a duplicate")
	_expect(int(duplicate_result.get("duplicate_count")) >= 1, "duplicate should convert into progression count")
	_expect(player.get_sub_hero_progression().get_owned_count() <= 3, "rare summon pool should contain at most three owned heroes")

	# §6.2: the price rises with the investment the collection already represents.
	var invested_cost: int = service.calculate_summon_cost(player)
	_expect(invested_cost >= first_expected_cost, "the price never falls as the collection grows (%d >= %d)" % [invested_cost, first_expected_cost])
	_expect(service.get_owned_draws(player) > 0, "the collection reports its draws")

	# §6.2: a FAILED summon costs nothing, and the failure reports the price it refused.
	player_progression.gold = 0
	var failed_result := service.summon(player)
	_expect(not bool(failed_result.get("success")), "summon should fail when gold is insufficient")
	_expect(str(failed_result.get("reason")) == "INSUFFICIENT_GOLD", "insufficient gold should return a stable failure reason")
	_expect(player_progression.gold == 0, "a failed summon does not touch the purse")
	_expect(int(failed_result.get("cost")) == invested_cost, "a failed summon still reports the price")

	# §6.2: the price does not depend on the current stage, so returning to a low stage is not a
	# discount and there is no reset that could make the collection cheaper.
	player.current_stage_number = 1
	var low_stage_cost: int = service.calculate_summon_cost(player)
	player.current_stage_number = 900
	_expect(service.calculate_summon_cost(player) == low_stage_cost, "the summon price is independent of the current stage")

	# §6.2: the price is capped by the coordinate, so an oversized legacy collection still prices.
	var huge_levels: Array[int] = [100000]
	var huge_duplicates: Array[int] = [100000]
	var huge_draws: int = BalanceFormulas.sub_hero_owned_draws(huge_levels, huge_duplicates, 3)
	_expect(
		BalanceFormulas.sub_hero_summon_cost(profile, huge_draws) > 0,
		"an oversized collection still produces a finite price"
	)

	if _failures.is_empty():
		print("Sub Hero summon smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	player.free()
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
