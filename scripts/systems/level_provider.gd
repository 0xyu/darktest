class_name LevelProvider
extends Node

const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")
const DEFAULT_ENEMY_DATA_PATH: String = "res://resources/enemies/TrainingEnemy.tres"
const DEFAULT_MINI_BOSS_PATHS: Array[String] = [
	"res://resources/enemies/AshenOracle.tres",
	"res://resources/enemies/Gravecaller.tres",
	"res://resources/enemies/BloodboundWarlord.tres",
]
const DEFAULT_FIXED_LEVEL_PATHS: Array[String] = [
	"res://resources/levels/level_001.tres",
	"res://resources/levels/level_002.tres",
	"res://resources/levels/level_010.tres",
	"res://resources/levels/level_100.tres",
]

## Fixed resources can be assigned in a scene; the default paths cover the
## small set of authored levels shipped with the prototype.
@export var fixed_level_paths: Array[String] = DEFAULT_FIXED_LEVEL_PATHS.duplicate()
@export var fixed_level_configs: Array[LevelConfig] = []
@export var templates: Array[LevelTemplate] = []
@export var enemy_pool: Array[EnemyData] = []
@export var mini_boss_definitions: Array[MiniBossDefinition] = []
@export_range(1, 999, 1) var base_enemy_count: int = 1
@export_range(1, 999, 1) var enemy_count_growth_interval: int = 3
@export_range(1, 999, 1) var max_enemy_count: int = 4
@export_range(0.1, 10.0, 0.01) var hp_growth_rate: float = 1.20
@export_range(0.1, 10.0, 0.01) var attack_growth_rate: float = 1.16
@export_range(0.1, 10.0, 0.01) var defense_growth_rate: float = 1.15
@export_range(0.1, 10.0, 0.01) var gold_growth_rate: float = 1.18
@export_range(0.0, 1.0, 0.01) var base_special_encounter_chance: float = 0.03
@export_range(0.0, 1.0, 0.01) var special_chance_increment: float = 0.01
@export_range(0.0, 1.0, 0.01) var max_special_encounter_chance: float = 0.15
@export var random_seed: int = 0

var special_encounter_chance: float = 0.03
var _fixed_levels: Dictionary = {}
var _random_number_generator := RandomNumberGenerator.new()


func _ready() -> void:
	if random_seed != 0:
		_random_number_generator.seed = random_seed
	else:
		_random_number_generator.randomize()
	special_encounter_chance = clampf(base_special_encounter_chance, 0.0, max_special_encounter_chance)
	_load_fixed_levels()


func get_stage_definition(level_id: int, requested_special_encounter_type: int = SpecialEncounterTypeResource.NONE) -> StageDefinition:
	var safe_level_id: int = maxi(level_id, 1)
	var fixed_config := _get_fixed_level_config(safe_level_id)
	if fixed_config != null:
		return fixed_config.to_stage_definition()
	return _generate_stage_definition(safe_level_id, requested_special_encounter_type)


func has_fixed_level(level_id: int) -> bool:
	return _get_fixed_level_config(maxi(level_id, 1)) != null


func get_enemy_for_summon(_level_id: int, _summon_index: int = 0) -> EnemyData:
	var pool: Array[EnemyData] = _get_enemy_pool()
	if pool.is_empty():
		return null
	return pool[_random_number_generator.randi_range(0, pool.size() - 1)]


func get_gold_growth_rate() -> float:
	return gold_growth_rate


func get_hp_growth_rate() -> float:
	return hp_growth_rate


func get_attack_growth_rate() -> float:
	return attack_growth_rate


func get_defense_growth_rate() -> float:
	return defense_growth_rate


func get_special_encounter_chance() -> float:
	return special_encounter_chance


func _load_fixed_levels() -> void:
	_fixed_levels.clear()
	for config in fixed_level_configs:
		if config != null:
			_fixed_levels[config.level_id] = config
	for path in fixed_level_paths:
		var config := load(path) as LevelConfig
		if config != null:
			_fixed_levels[config.level_id] = config


func _get_fixed_level_config(level_id: int) -> LevelConfig:
	if _fixed_levels.is_empty():
		_load_fixed_levels()
	return _fixed_levels.get(level_id) as LevelConfig


func _generate_stage_definition(level_id: int, requested_special_encounter_type: int) -> StageDefinition:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for_level(level_id)
	var template := _get_template(&"default")
	var definition := StageDefinition.new()
	definition.stage_number = level_id
	definition.level_id = level_id
	definition.template_id = template.template_id
	definition.display_name = "Stage %d" % level_id
	definition.difficulty_multiplier = maxf(template.difficulty_multiplier, 0.1)
	definition.spawn_rules = template.spawn_rules.duplicate()
	definition.special_rules = template.special_rules.duplicate(true)

	var encounter_type: int = requested_special_encounter_type
	if encounter_type == SpecialEncounterTypeResource.NONE:
		encounter_type = _roll_special_encounter(level_id, rng)
	if level_id % 10 == 0:
		definition.is_mini_boss_stage = true
		definition.boss = _pick_mini_boss_definition(rng)
		return definition
	if encounter_type != SpecialEncounterTypeResource.NONE:
		definition.is_special_encounter = true
		definition.special_encounter_type = encounter_type
		if encounter_type == SpecialEncounterTypeResource.RANDOM_MINI_BOSS:
			definition.boss = _pick_mini_boss_definition(rng)
			definition.special_mini_boss_level = _roll_random_mini_boss_level(level_id, rng)
		else:
			definition.special_enemy_definition = _build_special_enemy_definition(level_id, encounter_type, rng)
		return definition

	var configured_entries := _build_template_entries(template, level_id, rng)
	definition.enemy_entries = configured_entries
	return definition


func _get_template(template_id: StringName) -> LevelTemplate:
	for template in templates:
		if template != null and template.template_id == template_id:
			return template
	var default_template := LevelTemplate.new()
	default_template.template_id = template_id
	for enemy_definition in _get_enemy_pool():
		default_template.enemy_pool.append(enemy_definition)
	default_template.base_enemy_count = base_enemy_count
	default_template.enemy_count_growth_interval = enemy_count_growth_interval
	default_template.max_enemy_count = max_enemy_count
	default_template.difficulty_multiplier = 1.0
	return default_template


func _build_template_entries(template: LevelTemplate, level_id: int, rng: RandomNumberGenerator) -> Array[StageEnemyEntry]:
	var result: Array[StageEnemyEntry] = []
	if not template.enemy_entries.is_empty():
		for source_entry in template.enemy_entries:
			if source_entry != null and source_entry.enemy_definition != null:
				result.append(source_entry.copy_entry())
		return result
	var safe_interval: int = maxi(template.enemy_count_growth_interval, 1)
	var growth_steps: int = floori(float(maxi(level_id - 1, 0)) / float(safe_interval))
	var enemy_count: int = clampi(template.base_enemy_count + growth_steps, 1, maxi(template.max_enemy_count, 1))
	var pool: Array[EnemyData] = template.enemy_pool
	if pool.is_empty():
		pool = _get_enemy_pool()
	for _index in range(enemy_count):
		var entry := StageEnemyEntry.new()
		entry.enemy_definition = pool[rng.randi_range(0, pool.size() - 1)]
		entry.level_offset = _roll_enemy_offset(rng)
		result.append(entry)
	return result


func _get_enemy_pool() -> Array[EnemyData]:
	if not enemy_pool.is_empty():
		return enemy_pool
	var fallback := load(DEFAULT_ENEMY_DATA_PATH) as EnemyData
	var fallback_pool: Array[EnemyData] = []
	if fallback != null:
		fallback_pool.append(fallback)
	return fallback_pool


func _pick_mini_boss_definition(rng: RandomNumberGenerator) -> MiniBossDefinition:
	var available_definitions: Array[MiniBossDefinition] = mini_boss_definitions
	if available_definitions.is_empty():
		for path in DEFAULT_MINI_BOSS_PATHS:
			var definition := load(path) as MiniBossDefinition
			if definition != null:
				available_definitions.append(definition)
		mini_boss_definitions = available_definitions
	if available_definitions.is_empty():
		return null
	return available_definitions[rng.randi_range(0, available_definitions.size() - 1)]


func _build_special_enemy_definition(for_level: int, encounter_type: int, rng: RandomNumberGenerator) -> EnemyData:
	var pool: Array[EnemyData] = _get_enemy_pool()
	if pool.is_empty():
		return null
	var source_definition: EnemyData = pool[rng.randi_range(0, pool.size() - 1)]
	var special_definition := EnemyData.new()
	special_definition.base_stats = source_definition.base_stats
	special_definition.portrait = source_definition.portrait
	special_definition.battle_sprite = source_definition.battle_sprite
	special_definition.skills = source_definition.skills
	special_definition.loot_table = source_definition.loot_table
	special_definition.description = source_definition.description
	var encounter_name: String = SpecialEncounterTypeResource.get_display_name(encounter_type)
	special_definition.id = StringName("%s_stage_%d" % [encounter_name.to_lower().replace(" ", "_"), for_level])
	special_definition.name = "%s %s" % [encounter_name, source_definition.name]
	special_definition.enemy_type = _get_enemy_type_for_encounter(encounter_type)
	return special_definition


func _get_enemy_type_for_encounter(encounter_type: int) -> int:
	match encounter_type:
		SpecialEncounterTypeResource.ELITE:
			return EnemyType.ELITE
		SpecialEncounterTypeResource.TREASURE_MONSTER:
			return EnemyType.TREASURE
		SpecialEncounterTypeResource.SPECIAL_MONSTER:
			return EnemyType.SPECIAL
		SpecialEncounterTypeResource.GOLD_MONSTER:
			return EnemyType.GOLD
		SpecialEncounterTypeResource.CURSED_MONSTER:
			return EnemyType.CURSED
		_:
			return EnemyType.SPECIAL


func _roll_special_encounter(for_level: int, rng: RandomNumberGenerator) -> int:
	if for_level % 10 == 0:
		return SpecialEncounterTypeResource.NONE
	if rng.randf() >= clampf(special_encounter_chance, 0.0, max_special_encounter_chance):
		record_special_encounter_result(false)
		return SpecialEncounterTypeResource.NONE
	record_special_encounter_result(true)
	var types: Array[int] = [
		SpecialEncounterTypeResource.ELITE,
		SpecialEncounterTypeResource.TREASURE_MONSTER,
		SpecialEncounterTypeResource.SPECIAL_MONSTER,
		SpecialEncounterTypeResource.RANDOM_MINI_BOSS,
		SpecialEncounterTypeResource.GOLD_MONSTER,
		SpecialEncounterTypeResource.CURSED_MONSTER,
	]
	return types[rng.randi_range(0, types.size() - 1)]


func record_special_encounter_result(encounter_occurred: bool) -> void:
	if encounter_occurred:
		special_encounter_chance = clampf(base_special_encounter_chance, 0.0, max_special_encounter_chance)
	else:
		special_encounter_chance = minf(
			clampf(special_encounter_chance, 0.0, max_special_encounter_chance) + maxf(special_chance_increment, 0.0),
			max_special_encounter_chance
		)


func _roll_random_mini_boss_level(for_level: int, rng: RandomNumberGenerator) -> int:
	var recent_minimum: int = maxi(for_level - 20, 1)
	if recent_minimum <= 1 or rng.randf() < 0.8:
		return rng.randi_range(recent_minimum, for_level)
	return rng.randi_range(1, recent_minimum - 1)


func _roll_enemy_offset(rng: RandomNumberGenerator) -> int:
	var offsets: Array[int] = [0, -1, 1, -2, 2, -3, 3]
	var weights: Array[int] = [40, 15, 15, 10, 10, 5, 5]
	var roll: int = rng.randi_range(1, 100)
	var cumulative_weight: int = 0
	for index in range(offsets.size()):
		cumulative_weight += weights[index]
		if roll <= cumulative_weight:
			return offsets[index]
	return 0


func _seed_for_level(level_id: int) -> int:
	var base_seed: int = random_seed if random_seed != 0 else 7919
	return int(hash([base_seed, level_id]))
