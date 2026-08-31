class_name SubHeroSummonService
extends Resource

const SubHeroCatalogResource = preload("res://scripts/sub_hero/sub_hero_catalog.gd")
const SubHeroInstanceResource = preload("res://scripts/sub_hero/sub_hero_instance.gd")
const SubHeroSummonTableResource = preload("res://scripts/sub_hero/sub_hero_summon_table.gd")

## The Shop-facing service owns summon rules. It does not own UI state or
## persistent collection state; the player's progression service does that.
@export_range(0, 999999999, 1) var summon_cost: int = 250
@export var summon_table: SubHeroSummonTable

var _random_number_generator := RandomNumberGenerator.new()


func _init() -> void:
	_random_number_generator.randomize()
	if summon_table == null:
		summon_table = SubHeroSummonTableResource.new()


## Summons one Sub Hero and routes ownership/duplicate conversion through the
## player's existing progression service.
##
## Result keys are intentionally UI-friendly but contain no Control objects:
## {success, reason, data, is_new, level, duplicate_count, cost}.
func summon(player: Node) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return _failure("PLAYER_UNAVAILABLE")
	var progression: PlayerProgression = player.get("player_progression") as PlayerProgression
	if progression == null:
		return _failure("PROGRESSION_UNAVAILABLE")
	var cost: int = maxi(summon_cost, 0)
	if progression.gold < cost:
		return _failure("INSUFFICIENT_GOLD", cost)
	if summon_table == null or not summon_table.is_valid():
		return _failure("INVALID_SUMMON_TABLE", cost)

	var quality: int = summon_table.roll_quality(_random_number_generator)
	var candidates: Array[SubHeroData] = []
	for data in SubHeroCatalogResource.get_all_data():
		if data != null and data.quality == quality and data.is_valid():
			candidates.append(data)
	if candidates.is_empty():
		return _failure("NO_HEROES_FOR_QUALITY", cost)

	if not progression.spend_gold(cost):
		return _failure("INSUFFICIENT_GOLD", cost)
	var selected: SubHeroData = candidates[_random_number_generator.randi_range(0, candidates.size() - 1)]
	var instance := SubHeroInstanceResource.new(selected.id, 1)
	var collection_result: Dictionary = player.add_sub_hero(instance) if player.has_method("add_sub_hero") else {}
	if collection_result.is_empty() or not collection_result.has("hero_id"):
		progression.add_gold(cost)
		return _failure("COLLECTION_UNAVAILABLE", cost)

	var owned_instance: SubHeroInstance = player.get_sub_hero_progression().get_owned_instance(selected.id)
	return {
		"success": true,
		"reason": "",
		"data": selected,
		"instance": owned_instance,
		"is_new": bool(collection_result.get("is_new", false)),
		"level": int(collection_result.get("level", 1)),
		"duplicate_count": int(collection_result.get("duplicate_count", 0)),
		"cost": cost,
	}


## Exposed for deterministic tests and balancing tools; normal gameplay uses a
## randomized generator.
func set_random_seed(seed: int) -> void:
	_random_number_generator.seed = seed


func _failure(reason: String, cost: int = -1) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
		"data": null,
		"instance": null,
		"is_new": false,
		"level": 0,
		"duplicate_count": 0,
		"cost": maxi(cost, 0),
	}
