class_name StageManager
extends Node

const EnemyScalingSystem = preload("res://scripts/systems/enemy_scaling.gd")
const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")

## Creates and advances the procedural stages used by the combat scene.
signal stage_started(stage_state: StageState, enemies: Array[Node])
signal enemy_spawned(enemy: Node)
signal stage_completed(stage_state: StageState)
signal stage_generation_failed(stage_number: int, reason: String)

const DEFAULT_MINI_BOSS_PATHS: Array[String] = [
	"res://resources/enemies/AshenOracle.tres",
	"res://resources/enemies/Gravecaller.tres",
	"res://resources/enemies/BloodboundWarlord.tres",
]
const DEFAULT_ENEMY_DEFINITION_PATH: String = "res://resources/enemies/TrainingEnemy.tres"

@export var grid_path: NodePath
@export var spawn_parent_path: NodePath = NodePath("..")
@export var enemy_scene: PackedScene
@export var enemy_definitions: Array[EnemyDefinition] = []
@export var mini_boss_definitions: Array[MiniBossDefinition] = []
@export_range(1, 999999, 1) var starting_stage: int = 1
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

var stage_state: StageState = StageState.new()
var current_definition: StageDefinition

var _grid: GridMap2D
var _spawn_parent: Node
var _spawned_enemies: Array[EnemyController] = []
var _defeated_enemy_ids: Dictionary = {}
var _random_number_generator := RandomNumberGenerator.new()
var special_encounter_chance: float = 0.03


func _ready() -> void:
	_grid = get_node_or_null(grid_path) as GridMap2D
	_spawn_parent = get_node_or_null(spawn_parent_path)
	if random_seed != 0:
		_random_number_generator.seed = random_seed
	else:
		_random_number_generator.randomize()
	special_encounter_chance = clampf(base_special_encounter_chance, 0.0, max_special_encounter_chance)


func initialize_stage(new_stage_number: int = -1, requested_special_encounter_type: int = SpecialEncounterTypeResource.NONE) -> bool:
	if _grid == null:
		_grid = get_node_or_null(grid_path) as GridMap2D
	if _spawn_parent == null:
		_spawn_parent = get_node_or_null(spawn_parent_path)
	if _grid == null or _spawn_parent == null:
		var missing_reference_reason := "StageManager requires a grid and spawn parent."
		stage_generation_failed.emit(maxi(new_stage_number, 1), missing_reference_reason)
		push_error(missing_reference_reason)
		return false
	if enemy_scene == null:
		var missing_scene_reason := "StageManager requires an enemy scene."
		stage_generation_failed.emit(maxi(new_stage_number, 1), missing_scene_reason)
		push_error(missing_scene_reason)
		return false

	var target_stage: int = starting_stage if new_stage_number < 0 else new_stage_number
	target_stage = maxi(target_stage, 1)
	_clear_spawned_enemies()
	current_definition = build_stage_definition(target_stage, requested_special_encounter_type)
	stage_state.reset_for_stage(target_stage, false)
	stage_state.is_mini_boss_stage = current_definition.is_mini_boss_stage
	stage_state.is_special_encounter = current_definition.is_special_encounter
	stage_state.special_encounter_type = current_definition.special_encounter_type
	stage_state.special_mini_boss_level = current_definition.special_mini_boss_level
	if current_definition.mini_boss_definition != null:
		stage_state.encounter_id = current_definition.mini_boss_definition.definition_id
	elif current_definition.special_enemy_definition != null:
		stage_state.encounter_id = current_definition.special_enemy_definition.definition_id
	_defeated_enemy_ids.clear()

	var spawn_cells: Array[Vector2i] = _get_random_spawn_cells(current_definition.enemy_count)
	if spawn_cells.size() != current_definition.enemy_count:
		var spawn_reason := "Not enough walkable cells to spawn the stage enemies."
		stage_generation_failed.emit(target_stage, spawn_reason)
		push_error(spawn_reason)
		return false

	var spawned_nodes: Array[Node] = []
	if current_definition.is_mini_boss_stage:
		if current_definition.mini_boss_definition == null:
			var missing_boss_reason := "No Mini Boss definition is available."
			stage_generation_failed.emit(target_stage, missing_boss_reason)
			push_error(missing_boss_reason)
			return false
		var boss := _spawn_enemy(
			current_definition.mini_boss_definition,
			target_stage,
			spawn_cells[0],
			StringName("stage_%d_boss" % target_stage),
			target_stage
		)
		if boss == null:
			return false
		spawned_nodes.append(boss)
	elif current_definition.is_special_encounter:
		var special_definition: EnemyDefinition = current_definition.special_enemy_definition
		var special_level: int = current_definition.special_mini_boss_level if current_definition.special_encounter_type == SpecialEncounterTypeResource.RANDOM_MINI_BOSS else roll_enemy_level(target_stage)
		var special_id: StringName = StringName("stage_%d_special" % target_stage)
		var special_enemy := _spawn_enemy(
			special_definition if special_definition != null else current_definition.mini_boss_definition,
			target_stage,
			spawn_cells[0],
			special_id,
			special_level
		)
		if special_enemy == null:
			return false
		spawned_nodes.append(special_enemy)
	else:
		for enemy_index in range(current_definition.enemy_count):
			var normal_definition: EnemyDefinition = _pick_enemy_definition()
			var enemy := _spawn_enemy(
				normal_definition,
				target_stage,
				spawn_cells[enemy_index],
				StringName("stage_%d_enemy_%d" % [target_stage, enemy_index + 1]),
				roll_enemy_level(target_stage)
			)
			if enemy == null:
				return false
			spawned_nodes.append(enemy)

	stage_started.emit(stage_state, spawned_nodes)
	return true


func start_next_stage() -> bool:
	if not stage_state.is_complete:
		return false
	var next_stage: int = stage_state.stage_number + 1
	var special_encounter_type: int = roll_special_encounter(next_stage)
	return initialize_stage(next_stage, special_encounter_type)


func start_previous_stage() -> bool:
	var previous_stage: int = maxi(stage_state.stage_number - 1, 1)
	return initialize_stage(previous_stage)


func build_stage_definition(for_stage: int, requested_special_encounter_type: int = SpecialEncounterTypeResource.NONE) -> StageDefinition:
	var definition := StageDefinition.new()
	definition.stage_number = maxi(for_stage, 1)
	definition.display_name = "Stage %d" % definition.stage_number
	definition.is_mini_boss_stage = is_mini_boss_stage(definition.stage_number)
	if definition.is_mini_boss_stage:
		definition.enemy_count = 1
		definition.mini_boss_definition = _pick_mini_boss_definition()
	elif requested_special_encounter_type != SpecialEncounterTypeResource.NONE:
		definition.enemy_count = 1
		definition.is_special_encounter = true
		definition.special_encounter_type = requested_special_encounter_type
		if requested_special_encounter_type == SpecialEncounterTypeResource.RANDOM_MINI_BOSS:
			definition.mini_boss_definition = _pick_mini_boss_definition()
			definition.special_mini_boss_level = roll_random_mini_boss_level(definition.stage_number)
		else:
			definition.special_enemy_definition = _build_special_enemy_definition(definition.stage_number, requested_special_encounter_type)
	else:
		definition.enemy_count = get_enemy_count(definition.stage_number)
		definition.enemy_definitions = enemy_definitions
	return definition


func is_mini_boss_stage(for_stage: int) -> bool:
	return maxi(for_stage, 1) % 10 == 0


func roll_special_encounter(for_stage: int) -> int:
	if is_mini_boss_stage(for_stage):
		return SpecialEncounterTypeResource.NONE
	var current_chance: float = clampf(special_encounter_chance, 0.0, max_special_encounter_chance)
	if _random_number_generator.randf() < current_chance:
		record_special_encounter_result(true)
		return _pick_special_encounter_type()
	record_special_encounter_result(false)
	return SpecialEncounterTypeResource.NONE


func get_special_encounter_chance() -> float:
	return special_encounter_chance


func record_special_encounter_result(encounter_occurred: bool) -> void:
	if encounter_occurred:
		special_encounter_chance = clampf(base_special_encounter_chance, 0.0, max_special_encounter_chance)
		return
	special_encounter_chance = minf(
		clampf(special_encounter_chance, 0.0, max_special_encounter_chance) + maxf(special_chance_increment, 0.0),
		max_special_encounter_chance
	)


func reset_special_encounter_chance() -> void:
	special_encounter_chance = clampf(base_special_encounter_chance, 0.0, max_special_encounter_chance)


func roll_random_mini_boss_level(for_stage: int) -> int:
	var current_stage: int = maxi(for_stage, 1)
	var recent_minimum: int = maxi(current_stage - 20, 1)
	if recent_minimum <= 1 or _random_number_generator.randf() < 0.8:
		return _random_number_generator.randi_range(recent_minimum, current_stage)
	return _random_number_generator.randi_range(1, recent_minimum - 1)


func get_enemy_count(for_stage: int) -> int:
	var safe_interval: int = maxi(enemy_count_growth_interval, 1)
	var growth_steps: int = floori(float(maxi(for_stage - 1, 0)) / float(safe_interval))
	return clampi(base_enemy_count + growth_steps, 1, maxi(max_enemy_count, 1))


func roll_enemy_level(stage_level: int) -> int:
	var offsets: Array[int] = [0, -1, 1, -2, 2, -3, 3]
	var weights: Array[int] = [40, 15, 15, 10, 10, 5, 5]
	var roll: int = _random_number_generator.randi_range(1, 100)
	var cumulative_weight: int = 0
	var selected_offset: int = 0
	for index in range(offsets.size()):
		cumulative_weight += weights[index]
		if roll <= cumulative_weight:
			selected_offset = offsets[index]
			break
	return maxi(stage_level + selected_offset, 1)


func get_spawned_enemies() -> Array[EnemyController]:
	return _spawned_enemies.duplicate()


func _pick_enemy_definition() -> EnemyDefinition:
	if enemy_definitions.is_empty():
		return null
	return enemy_definitions[_random_number_generator.randi_range(0, enemy_definitions.size() - 1)]


func _pick_special_encounter_type() -> int:
	var encounter_types: Array[int] = [
		SpecialEncounterTypeResource.ELITE,
		SpecialEncounterTypeResource.TREASURE_MONSTER,
		SpecialEncounterTypeResource.SPECIAL_MONSTER,
		SpecialEncounterTypeResource.RANDOM_MINI_BOSS,
		SpecialEncounterTypeResource.GOLD_MONSTER,
		SpecialEncounterTypeResource.CURSED_MONSTER,
	]
	return encounter_types[_random_number_generator.randi_range(0, encounter_types.size() - 1)]


func _build_special_enemy_definition(for_stage: int, encounter_type: int) -> EnemyDefinition:
	var source_definition: EnemyDefinition = _pick_enemy_definition()
	if source_definition == null:
		source_definition = load(DEFAULT_ENEMY_DEFINITION_PATH) as EnemyDefinition
	if source_definition == null:
		return null
	var special_definition := source_definition.duplicate(true) as EnemyDefinition
	var encounter_name: String = SpecialEncounterTypeResource.get_display_name(encounter_type)
	special_definition.definition_id = StringName("%s_stage_%d" % [encounter_name.to_lower().replace(" ", "_"), for_stage])
	special_definition.display_name = "%s %s" % [encounter_name, source_definition.display_name]
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


func _pick_mini_boss_definition() -> MiniBossDefinition:
	var available_definitions: Array[MiniBossDefinition] = mini_boss_definitions
	if available_definitions.is_empty():
		for definition_path in DEFAULT_MINI_BOSS_PATHS:
			var loaded_definition := load(definition_path) as MiniBossDefinition
			if loaded_definition != null:
				available_definitions.append(loaded_definition)
		mini_boss_definitions = available_definitions
	if available_definitions.is_empty():
		return null
	return available_definitions[_random_number_generator.randi_range(0, available_definitions.size() - 1)]


func _get_random_spawn_cells(required_count: int) -> Array[Vector2i]:
	var available_cells: Array[Vector2i] = []
	for y in range(_grid.grid_size.y):
		for x in range(_grid.grid_size.x):
			var cell := Vector2i(x, y)
			if _grid.is_walkable(cell) and not _grid.is_occupied(cell):
				available_cells.append(cell)

	var result: Array[Vector2i] = []
	var count: int = mini(required_count, available_cells.size())
	for _index in range(count):
		var random_index: int = _random_number_generator.randi_range(0, available_cells.size() - 1)
		result.append(available_cells[random_index])
		available_cells.remove_at(random_index)
	return result


func _get_enemy_grid_path() -> NodePath:
	var parent_grid_path: String = str(_spawn_parent.get_path_to(_grid))
	if parent_grid_path == ".":
		return NodePath("..")
	return NodePath("../" + parent_grid_path)


func _scale_enemy_definition(enemy: EnemyController, stage_number: int) -> void:
	if enemy.enemy_definition == null or enemy.enemy_definition.base_stats == null:
		return
	var scaled_definition := enemy.enemy_definition.duplicate(true) as EnemyDefinition
	scaled_definition.base_stats = EnemyScalingSystem.scale_stats(
		enemy.enemy_definition.base_stats,
		stage_number,
		hp_growth_rate,
		attack_growth_rate,
		defense_growth_rate,
		gold_growth_rate
	)
	enemy.enemy_definition = scaled_definition


func _spawn_enemy(
	enemy_definition: EnemyDefinition,
	stage_number: int,
	spawn_cell: Vector2i,
	generated_id: StringName,
	level: int
) -> EnemyController:
	var enemy := enemy_scene.instantiate() as EnemyController
	if enemy == null:
		var invalid_scene_reason := "Enemy scene must contain an EnemyController root node."
		stage_generation_failed.emit(stage_number, invalid_scene_reason)
		push_error(invalid_scene_reason)
		_clear_spawned_enemies()
		return null

	enemy.name = generated_id
	enemy.enemy_id = generated_id
	enemy.enemy_level = maxi(level, 1)
	enemy.grid_position = spawn_cell
	enemy.grid_path = _get_enemy_grid_path()
	if enemy_definition != null:
		enemy.enemy_definition = enemy_definition
	_scale_enemy_definition(enemy, stage_number)
	_spawn_parent.add_child(enemy)
	_spawned_enemies.append(enemy)
	stage_state.spawned_enemy_count += 1
	if enemy.has_signal("defeated"):
		enemy.defeated.connect(_on_enemy_defeated.bind(enemy))
	if enemy.has_signal("summon_requested"):
		enemy.summon_requested.connect(_on_summon_requested)
	return enemy


func _on_summon_requested(boss: EnemyController, summon_count: int) -> void:
	if not _spawned_enemies.has(boss) or boss.is_defeated():
		return
	var spawn_cells: Array[Vector2i] = _get_random_spawn_cells(maxi(summon_count, 0))
	for spawn_cell in spawn_cells:
		var summon_index: int = stage_state.spawned_enemy_count + 1
		var summon := _spawn_enemy(
			_pick_enemy_definition(),
			stage_state.stage_number,
			spawn_cell,
			StringName("stage_%d_summon_%d" % [stage_state.stage_number, summon_index]),
			roll_enemy_level(stage_state.stage_number)
		)
		if summon != null:
			enemy_spawned.emit(summon)


func _on_enemy_defeated(enemy: EnemyController) -> void:
	if not _spawned_enemies.has(enemy) or _defeated_enemy_ids.has(enemy.enemy_id):
		return
	_defeated_enemy_ids[enemy.enemy_id] = true
	stage_state.defeated_enemy_count += 1
	if stage_state.defeated_enemy_count >= stage_state.spawned_enemy_count and stage_state.spawned_enemy_count > 0:
		stage_state.is_complete = true
		stage_completed.emit(stage_state)


func _clear_spawned_enemies() -> void:
	for enemy in _spawned_enemies:
		if is_instance_valid(enemy):
			if _grid != null and not enemy.is_defeated():
				_grid.clear_occupied(enemy.grid_position, enemy.enemy_id)
			enemy.queue_free()
	_spawned_enemies.clear()
	_defeated_enemy_ids.clear()
