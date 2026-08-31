extends SceneTree

const ServiceScript = preload("res://scripts/sub_hero/sub_hero_summon_service.gd")
const TableScript = preload("res://scripts/sub_hero/sub_hero_summon_table.gd")
const PlayerScript = preload("res://scripts/player/player_controller.gd")
const ProgressionScript = preload("res://scripts/player/player_progression.gd")
const QualityScript = preload("res://scripts/sub_hero/sub_hero_quality.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var player: PlayerController = PlayerScript.new()
	var player_progression: PlayerProgression = ProgressionScript.new()
	player_progression.gold = 2000
	player.player_progression = player_progression
	var service: SubHeroSummonService = ServiceScript.new()
	var table: SubHeroSummonTable = TableScript.new()
	table.common_weight = 0.0
	table.rare_weight = 100.0
	table.legendary_weight = 0.0
	service.summon_table = table
	service.summon_cost = 250
	service.set_random_seed(7)

	var first_result := service.summon(player)
	_expect(bool(first_result.get("success")), "summon should succeed when the player can afford it")
	_expect(int(first_result.get("data").quality) == QualityScript.RARE, "summon should use the configured rare-only weight")
	_expect(bool(first_result.get("is_new")), "first summon should create a new Sub Hero")
	_expect(player_progression.gold == 1750, "summon should spend exactly the configured cost")

	var duplicate_result: Dictionary = {}
	for _summon_index in 3:
		var owned_count_before: int = player.get_sub_hero_progression().get_owned_count()
		var next_result := service.summon(player)
		_expect(bool(next_result.get("success")), "summon should succeed while the player can afford it")
		if not bool(next_result.get("is_new", true)) and duplicate_result.is_empty():
			duplicate_result = next_result
			_expect(player.get_sub_hero_progression().get_owned_count() == owned_count_before, "duplicate should not add a second owned entry")
	_expect(not duplicate_result.is_empty(), "a repeated result should be produced after four summons from three rare heroes")
	_expect(not bool(duplicate_result.get("is_new")), "repeated hero should be reported as a duplicate")
	_expect(int(duplicate_result.get("duplicate_count")) >= 1, "duplicate should convert into progression count")
	_expect(player.get_sub_hero_progression().get_owned_count() <= 3, "rare summon pool should contain at most three owned heroes")
	_expect(player_progression.gold == 1000, "all four summons should spend the configured cost")

	player_progression.gold = 0
	var failed_result := service.summon(player)
	_expect(not bool(failed_result.get("success")), "summon should fail when gold is insufficient")
	_expect(str(failed_result.get("reason")) == "INSUFFICIENT_GOLD", "insufficient gold should return a stable failure reason")

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
