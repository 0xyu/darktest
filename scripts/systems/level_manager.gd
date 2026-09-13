class_name LevelManager
extends Node

const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")

signal level_loaded(level_id: int, definition: StageDefinition)
signal level_load_failed(level_id: int, reason: String)

@export var provider_path: NodePath = NodePath("LevelProvider")

var _provider: LevelProvider


func _ready() -> void:
	_provider = get_node_or_null(provider_path) as LevelProvider


func request_level(level_id: int, requested_special_encounter_type: int = SpecialEncounterTypeResource.NONE) -> StageDefinition:
	if _provider == null:
		_provider = get_node_or_null(provider_path) as LevelProvider
	if _provider == null:
		var reason := "LevelManager requires a LevelProvider."
		level_load_failed.emit(maxi(level_id, 1), reason)
		push_error(reason)
		return null
	var definition := _provider.get_stage_definition(level_id, requested_special_encounter_type)
	if definition == null:
		level_load_failed.emit(maxi(level_id, 1), "LevelProvider returned no StageDefinition.")
		return null
	level_loaded.emit(definition.level_id, definition)
	return definition


func has_fixed_level(level_id: int) -> bool:
	return _provider != null and _provider.has_fixed_level(level_id)


func get_enemy_for_summon(level_id: int, summon_index: int = 0) -> EnemyData:
	return _provider.get_enemy_for_summon(level_id, summon_index) if _provider != null else null


func get_gold_growth_rate() -> float:
	return _provider.get_gold_growth_rate() if _provider != null else 1.18


func get_exp_growth_rate() -> float:
	return _provider.get_exp_growth_rate() if _provider != null else 1.15


## §7: the provider owns the balance profile, and the systems this manager already configures
## (the stage manager above all) read it through here instead of loading a second copy.
func get_balance_profile() -> BalanceProfile:
	return _provider.get_balance_profile() if _provider != null else BalanceProfile.get_default()
