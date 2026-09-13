class_name SubHeroSummonService
extends Resource

const SubHeroCatalogResource = preload("res://scripts/sub_hero/sub_hero_catalog.gd")
const SubHeroInstanceResource = preload("res://scripts/sub_hero/sub_hero_instance.gd")
const SubHeroSummonTableResource = preload("res://scripts/sub_hero/sub_hero_summon_table.gd")

## The Shop-facing service owns summon rules. It does not own UI state or
## persistent collection state; the player's progression service does that.
##
## §6.2: the price is DERIVED from the whole existing collection
## (`max(250, ceil(10 * G(1 + owned_draws / 24)))`), not a fixed constant — a fixed 250 would let
## the late game buy unbounded exponential power for pocket change. It is computed BEFORE the draw
## and before any gold moves, so a failed draw costs nothing and no reset can make the collection
## cheaper.
##
## `summon_table` still owns the quality roll, and `duplicates_per_level` still owns the existing
## "3 duplicates = +1 level" rule; only the price and the damage coordinate changed with R2.
@export var summon_table: SubHeroSummonTable
## §7: the profile the price curve reads, handed in by whoever owns the provider.
@export var balance_profile: BalanceProfile

var _random_number_generator := RandomNumberGenerator.new()


func get_balance_profile() -> BalanceProfile:
	return balance_profile if balance_profile != null else BalanceProfile.get_default()


## §6.2: what one summon costs the player RIGHT NOW, from the whole owned collection. Independent
## of the current stage: a hero summoned from a high stage and the same hero summoned from stage 1
## cost the same.
func calculate_summon_cost(player: Node) -> int:
	var profile: BalanceProfile = get_balance_profile()
	return BalanceFormulas.sub_hero_summon_cost(profile, get_owned_draws(player))


## §6.2 `owned_draws = sum_owned(1 + 3 * (hero_level - 1) + duplicate_count)`: the summons the
## collection represents. Every field is validated as a non-negative int before it is summed, so a
## damaged save cannot produce a negative or wrapped price input.
func get_owned_draws(player: Node) -> int:
	var progression: SubHeroProgressionService = _get_collection(player)
	if progression == null:
		return 0
	var levels: Array[int] = []
	var duplicates: Array[int] = []
	for instance in progression.owned_sub_heroes:
		if instance == null:
			continue
		levels.append(maxi(instance.level, 1))
		duplicates.append(maxi(instance.duplicate_count, 0))
	return BalanceFormulas.sub_hero_owned_draws(levels, duplicates, maxi(progression.duplicates_per_level, 1))


func _get_collection(player: Node) -> SubHeroProgressionService:
	if player == null or not is_instance_valid(player):
		return null
	if not player.has_method("get_sub_hero_progression"):
		return null
	return player.get_sub_hero_progression() as SubHeroProgressionService


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
	# §6.2: priced before the draw and before any gold moves.
	var cost: int = maxi(calculate_summon_cost(player), 0)
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
