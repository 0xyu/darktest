class_name StageManager
extends Node

const EnemyScalingSystem = preload("res://scripts/systems/enemy_scaling.gd")

## Creates and advances the procedural stages used by the combat scene.
signal stage_started(stage_state: StageState, enemies: Array[Node])
signal stage_completed(stage_state: StageState)
signal stage_generation_failed(stage_number: int, reason: String)

@export var grid_path: NodePath
@export var spawn_parent_path: NodePath = NodePath("..")
@export var enemy_scene: PackedScene
@export var enemy_definitions: Array[EnemyDefinition] = []
@export_range(1, 999999, 1) var starting_stage: int = 1
@export_range(1, 999, 1) var base_enemy_count: int = 1
@export_range(1, 999, 1) var enemy_count_growth_interval: int = 3
@export_range(1, 999, 1) var max_enemy_count: int = 4
@export_range(0.1, 10.0, 0.01) var hp_growth_rate: float = 1.20
@export_range(0.1, 10.0, 0.01) var attack_growth_rate: float = 1.16
@export_range(0.1, 10.0, 0.01) var defense_growth_rate: float = 1.15
@export_range(0.1, 10.0, 0.01) var gold_growth_rate: float = 1.18
@export var random_seed: int = 0

var stage_state: StageState = StageState.new()
var current_definition: StageDefinition

var _grid: GridMap2D
var _spawn_parent: Node
var _spawned_enemies: Array[EnemyController] = []
var _defeated_enemy_ids: Dictionary = {}
var _random_number_generator := RandomNumberGenerator.new()


func _ready() -> void:
	_grid = get_node_or_null(grid_path) as GridMap2D
	_spawn_parent = get_node_or_null(spawn_parent_path)
	if random_seed != 0:
		_random_number_generator.seed = random_seed
	else:
		_random_number_generator.randomize()


func initialize_stage(new_stage_number: int = -1) -> bool:
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
	current_definition = build_stage_definition(target_stage)
	stage_state.reset_for_stage(target_stage, false)
	_defeated_enemy_ids.clear()

	var spawn_cells: Array[Vector2i] = _get_random_spawn_cells(current_definition.enemy_count)
	if spawn_cells.size() != current_definition.enemy_count:
		var spawn_reason := "Not enough walkable cells to spawn the stage enemies."
		stage_generation_failed.emit(target_stage, spawn_reason)
		push_error(spawn_reason)
		return false

	var spawned_nodes: Array[Node] = []
	for enemy_index in range(current_definition.enemy_count):
		var enemy := enemy_scene.instantiate() as EnemyController
		if enemy == null:
			var invalid_scene_reason := "Enemy scene must contain an EnemyController root node."
			stage_generation_failed.emit(target_stage, invalid_scene_reason)
			push_error(invalid_scene_reason)
			_clear_spawned_enemies()
			return false

		enemy.name = "StageEnemy_%d_%d" % [target_stage, enemy_index + 1]
		enemy.enemy_id = StringName("stage_%d_enemy_%d" % [target_stage, enemy_index + 1])
		enemy.enemy_level = roll_enemy_level(target_stage)
		enemy.grid_position = spawn_cells[enemy_index]
		enemy.grid_path = _get_enemy_grid_path()
		if not enemy_definitions.is_empty():
			enemy.enemy_definition = enemy_definitions[_random_number_generator.randi_range(0, enemy_definitions.size() - 1)]
		_scale_enemy_definition(enemy, target_stage)
		_spawn_parent.add_child(enemy)
		_spawned_enemies.append(enemy)
		stage_state.spawned_enemy_count += 1
		if enemy.has_signal("defeated"):
			enemy.defeated.connect(_on_enemy_defeated.bind(enemy))
		spawned_nodes.append(enemy)

	stage_started.emit(stage_state, spawned_nodes)
	return true


func start_next_stage() -> bool:
	if not stage_state.is_complete:
		return false
	return initialize_stage(stage_state.stage_number + 1)


func build_stage_definition(for_stage: int) -> StageDefinition:
	var definition := StageDefinition.new()
	definition.stage_number = maxi(for_stage, 1)
	definition.display_name = "Stage %d" % definition.stage_number
	definition.enemy_count = get_enemy_count(definition.stage_number)
	definition.enemy_definitions = enemy_definitions
	return definition


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
