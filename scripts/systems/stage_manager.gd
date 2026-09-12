class_name StageManager
extends Node

const EnemyScalingSystem = preload("res://scripts/systems/enemy_scaling.gd")
const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")

## Consumes final StageDefinitions and owns only battle-stage spawning/state.
signal stage_started(stage_state: StageState, enemies: Array[Node])
signal enemy_spawned(enemy: Node)
signal stage_completed(stage_state: StageState)
signal stage_generation_failed(stage_number: int, reason: String)

@export var grid_path: NodePath
@export var spawn_parent_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../Player")
@export var level_manager_path: NodePath = NodePath("../LevelManager")
@export var enemy_scene: PackedScene
@export_range(1, 999999, 1) var starting_stage: int = 1
## Random per-spawn stat variance around the scaled base values.
## 0.15 means stats may vary by up to +/-15 percent.
@export_range(0.0, 1.0, 0.01) var enemy_stat_variance: float = 0.15
## 0-based y row of the arena gate lane: the Stage Starting Point sits on the
## left edge of this row and the Next Stage Point / exit on the right edge.
@export_range(0, 63, 1) var stage_gate_row: int = 3

var stage_state: StageState = StageState.new()
var current_definition: StageDefinition

var _grid: GridMap2D
var _spawn_parent: Node
var _player: Node
var _level_manager: LevelManager
var _spawned_enemies: Array[EnemyController] = []
var _defeated_enemy_ids: Dictionary = {}
var _random_number_generator := RandomNumberGenerator.new()
## The stage number that is currently generated. -1 means no stage has been
## generated yet (boot), so the first initialize_stage must place the hero at
## the Stage Starting Point. Farming re-spawn of the same number keeps position.
var _active_stage_number: int = -1

## Kept as a read-only compatibility property for GoldSystem.
var gold_growth_rate: float:
	get:
		return _level_manager.get_gold_growth_rate() if _level_manager != null else 1.18


func _ready() -> void:
	_grid = get_node_or_null(grid_path) as GridMap2D
	_spawn_parent = get_node_or_null(spawn_parent_path)
	_player = get_node_or_null(player_path)
	_level_manager = get_node_or_null(level_manager_path) as LevelManager
	_random_number_generator.randomize()


func initialize_stage(new_stage_number: int = -1, requested_special_encounter_type: int = SpecialEncounterTypeResource.NONE) -> bool:
	_resolve_references()
	var target_stage: int = starting_stage if new_stage_number < 0 else maxi(new_stage_number, 1)
	if _grid == null or _spawn_parent == null or _level_manager == null:
		var missing_reference_reason := "StageManager requires a grid, spawn parent, and LevelManager."
		stage_generation_failed.emit(target_stage, missing_reference_reason)
		push_error(missing_reference_reason)
		return false
	if enemy_scene == null:
		var missing_scene_reason := "StageManager requires an enemy scene."
		stage_generation_failed.emit(target_stage, missing_scene_reason)
		push_error(missing_scene_reason)
		return false

	# A new stage (different number from the one currently generated, including
	# the first boot) re-enters the arena through the Stage Starting Point.
	# Farming re-spawns the SAME number, so the hero stays where it is.
	var teleport_to_start: bool = _active_stage_number != target_stage
	_clear_spawned_enemies()
	current_definition = _level_manager.request_level(target_stage, requested_special_encounter_type)
	if current_definition == null:
		return false
	if teleport_to_start:
		_place_player_at_start()
	stage_state.reset_for_stage(target_stage, current_definition.is_mini_boss_stage)
	stage_state.is_special_encounter = current_definition.is_special_encounter
	stage_state.special_encounter_type = current_definition.special_encounter_type
	stage_state.special_mini_boss_level = current_definition.special_mini_boss_level
	if current_definition.boss != null:
		stage_state.encounter_id = current_definition.boss.id
	elif current_definition.special_enemy_definition != null:
		stage_state.encounter_id = current_definition.special_enemy_definition.id
	_defeated_enemy_ids.clear()

	var available_cells := _get_available_spawn_cells()
	var spawned_nodes: Array[Node] = []
	if current_definition.boss != null:
		var boss_cells := _take_spawn_cells(available_cells, 1, StageEnemyEntry.SpawnRule.RANDOM)
		if boss_cells.size() != 1:
			return _fail_spawn(target_stage, "Not enough walkable cells to spawn the stage boss.")
		var boss_level: int = target_stage if not current_definition.is_special_encounter else current_definition.special_mini_boss_level
		var boss := _spawn_enemy(current_definition.boss, target_stage, boss_cells[0], StringName("stage_%d_boss" % target_stage), boss_level)
		if boss == null:
			return false
		spawned_nodes.append(boss)
	elif current_definition.is_special_encounter:
		var special_definition: EnemyData = current_definition.special_enemy_definition
		var special_level: int = current_definition.special_mini_boss_level if current_definition.special_encounter_type == SpecialEncounterTypeResource.RANDOM_MINI_BOSS else target_stage
		var special_cells := _take_spawn_cells(available_cells, 1, StageEnemyEntry.SpawnRule.RANDOM)
		if special_cells.size() != 1:
			return _fail_spawn(target_stage, "Not enough walkable cells to spawn the special enemy.")
		var special_enemy := _spawn_enemy(special_definition, target_stage, special_cells[0], StringName("stage_%d_special" % target_stage), special_level)
		if special_enemy == null:
			return false
		spawned_nodes.append(special_enemy)
	else:
		for entry in current_definition.enemy_entries:
			if entry == null or entry.enemy_definition == null:
				continue
			var entry_cells := _take_spawn_cells(available_cells, maxi(entry.count, 0), entry.spawn_rule)
			if entry_cells.size() != maxi(entry.count, 0):
				return _fail_spawn(target_stage, "Not enough walkable cells to spawn the stage enemies.")
			for cell in entry_cells:
				var enemy_index: int = stage_state.spawned_enemy_count + 1
				var enemy := _spawn_enemy(entry.enemy_definition, target_stage, cell, StringName("stage_%d_enemy_%d" % [target_stage, enemy_index]), entry.get_level(target_stage), entry)
				if enemy == null:
					return false
				spawned_nodes.append(enemy)

	if spawned_nodes.is_empty():
		return _fail_spawn(target_stage, "StageDefinition contains no spawnable enemies.")
	_active_stage_number = target_stage
	stage_started.emit(stage_state, spawned_nodes)
	return true


## Starts the stage after the one currently generated.
##
## "May the player leave this stage at all" is deliberately NOT decided here: the
## stage-flow gate owns that rule (grid_combat._can_advance_to_next_stage, backed
## by StageFlow) and is the only caller. The gate needs to allow more than a full
## clear — a stage the player walked back into may be left through the exit while
## enemies are still standing when the next stage is already cleared — so this
## method only performs the move instead of re-checking the clear itself.
func start_next_stage() -> bool:
	return initialize_stage(stage_state.stage_number + 1)


func start_previous_stage() -> bool:
	return initialize_stage(maxi(stage_state.stage_number - 1, 1))


func get_spawned_enemies() -> Array[EnemyController]:
	return _spawned_enemies.duplicate()


## The left arrival cell of the arena (Stage Starting Point). The hero is
## teleported here when a new stage is generated.
func get_stage_start_cell() -> Vector2i:
	if _grid == null:
		return Vector2i.ZERO
	return Vector2i(0, clampi(stage_gate_row, 0, _grid.grid_size.y - 1))


## The right exit cell of the arena (Next Stage Point). The player must stand
## here before the next stage can start.
func get_stage_exit_cell() -> Vector2i:
	if _grid == null:
		return Vector2i.ZERO
	return Vector2i(_grid.grid_size.x - 1, clampi(stage_gate_row, 0, _grid.grid_size.y - 1))


func is_player_on_stage_exit() -> bool:
	return (
		_player != null
		and _player.has_method("get_grid_position")
		and _player.get_grid_position() == get_stage_exit_cell()
	)


## Completes the current stage when every spawned enemy has been defeated.
## This is idempotent so independent combat layers can confirm a clear
## without producing duplicate rewards or stage transitions.
func complete_stage_if_cleared() -> bool:
	if stage_state == null or stage_state.is_complete:
		return stage_state != null and stage_state.is_complete
	if _spawned_enemies.is_empty():
		return false
	for enemy in _spawned_enemies:
		if enemy != null and is_instance_valid(enemy) and not enemy.is_defeated():
			return false
	stage_state.defeated_enemy_count = stage_state.spawned_enemy_count
	stage_state.is_complete = true
	stage_completed.emit(stage_state)
	return true


func _resolve_references() -> void:
	if _grid == null:
		_grid = get_node_or_null(grid_path) as GridMap2D
	if _spawn_parent == null:
		_spawn_parent = get_node_or_null(spawn_parent_path)
	if _player == null:
		_player = get_node_or_null(player_path)
	if _level_manager == null:
		_level_manager = get_node_or_null(level_manager_path) as LevelManager


## Best-effort teleport of the hero onto the Stage Starting Point so enemies
## spawn away from the arena entrance. Runs before enemies spawn, therefore the
## start cell is occupied and excluded from spawn candidates.
func _place_player_at_start() -> void:
	if _player != null and _player.has_method("place_at"):
		_player.place_at(get_stage_start_cell())


func _get_available_spawn_cells() -> Array[Vector2i]:
	var available_cells: Array[Vector2i] = []
	for y in range(_grid.grid_size.y):
		for x in range(_grid.grid_size.x):
			var cell := Vector2i(x, y)
			if _grid.is_walkable(cell) and not _grid.is_occupied(cell):
				available_cells.append(cell)
	return available_cells


func _take_spawn_cells(available_cells: Array[Vector2i], required_count: int, spawn_rule: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var count: int = mini(maxi(required_count, 0), available_cells.size())
	var anchor := _get_player_cell()
	for _index in range(count):
		var selected_index: int = _random_number_generator.randi_range(0, available_cells.size() - 1)
		if spawn_rule != StageEnemyEntry.SpawnRule.RANDOM and _player != null:
			var best_distance: int = -1 if spawn_rule == StageEnemyEntry.SpawnRule.FAR_FROM_PLAYER else 999999999
			for cell_index in range(available_cells.size()):
				var distance: int = _grid_distance(available_cells[cell_index], anchor)
				var is_better: bool = distance > best_distance if spawn_rule == StageEnemyEntry.SpawnRule.FAR_FROM_PLAYER else distance < best_distance
				if is_better:
					best_distance = distance
					selected_index = cell_index
		result.append(available_cells[selected_index])
		available_cells.remove_at(selected_index)
	return result


func _get_player_cell() -> Vector2i:
	if _player != null and _player.has_method("get_grid_position"):
		return _player.get_grid_position()
	return Vector2i.ZERO


func _grid_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


func _fail_spawn(stage_number: int, reason: String) -> bool:
	stage_generation_failed.emit(stage_number, reason)
	push_error(reason)
	_clear_spawned_enemies()
	return false


func _get_enemy_grid_path() -> NodePath:
	var parent_grid_path: String = str(_spawn_parent.get_path_to(_grid))
	if parent_grid_path == ".":
		return NodePath("..")
	return NodePath("../" + parent_grid_path)


func _scale_enemy_runtime(enemy: EnemyController, stage_number: int, entry: StageEnemyEntry = null) -> void:
	if enemy.enemy_data == null or enemy.enemy_data.base_stats == null:
		return
	var scaled_stats: EnemyStats = EnemyScalingSystem.scale_stats(
		enemy.enemy_data.base_stats,
		stage_number,
		_level_manager.get_hp_growth_rate(),
		_level_manager.get_attack_growth_rate(),
		_level_manager.get_defense_growth_rate(),
		_level_manager.get_gold_growth_rate(),
		_level_manager.get_exp_growth_rate()
	)
	var difficulty_multiplier: float = maxf(current_definition.difficulty_multiplier, 0.1)
	var hp_multiplier: float = entry.hp_multiplier if entry != null else 1.0
	var attack_multiplier: float = entry.attack_multiplier if entry != null else 1.0
	var defense_multiplier: float = entry.defense_multiplier if entry != null else 1.0
	scaled_stats.max_hp = _multiply_stat(scaled_stats.max_hp, difficulty_multiplier * hp_multiplier)
	scaled_stats.attack = _multiply_stat(scaled_stats.attack, difficulty_multiplier * attack_multiplier)
	scaled_stats.defense = _multiply_stat(scaled_stats.defense, difficulty_multiplier * defense_multiplier)
	_apply_stat_variance(scaled_stats)
	scaled_stats.current_hp = scaled_stats.max_hp
	enemy.initialize_runtime_from_stats(scaled_stats)


func _apply_stat_variance(stats: EnemyStats) -> void:
	if enemy_stat_variance <= 0.0:
		return
	stats.max_hp = _apply_variance_to_value(stats.max_hp)
	stats.attack = _apply_variance_to_value(stats.attack)
	stats.defense = _apply_variance_to_value(stats.defense)


func _apply_variance_to_value(value: int) -> int:
	if value <= 0:
		return value
	var variance: float = clampf(enemy_stat_variance, 0.0, 1.0)
	var multiplier: float = 1.0 + _random_number_generator.randf_range(-variance, variance)
	return maxi(roundi(float(value) * multiplier), 1)


func _multiply_stat(value: int, multiplier: float) -> int:
	return maxi(roundi(float(value) * maxf(multiplier, 0.1)), 1)


func _spawn_enemy(enemy_data: EnemyData, stage_number: int, spawn_cell: Vector2i, generated_id: StringName, level: int, entry: StageEnemyEntry = null) -> EnemyController:
	if enemy_data == null:
		return null
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
	enemy.enemy_data = enemy_data
	_spawn_parent.add_child(enemy)
	_scale_enemy_runtime(enemy, stage_number, entry)
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
	var spawn_cells := _take_spawn_cells(_get_available_spawn_cells(), maxi(summon_count, 0), StageEnemyEntry.SpawnRule.RANDOM)
	for spawn_cell in spawn_cells:
		var summon_index: int = stage_state.spawned_enemy_count + 1
		var summon := _spawn_enemy(
			_level_manager.get_enemy_for_summon(stage_state.stage_number, summon_index),
			stage_state.stage_number,
			spawn_cell,
			StringName("stage_%d_summon_%d" % [stage_state.stage_number, summon_index]),
			stage_state.stage_number
		)
		if summon != null:
			enemy_spawned.emit(summon)


func _on_enemy_defeated(enemy: EnemyController) -> void:
	if not _spawned_enemies.has(enemy) or _defeated_enemy_ids.has(enemy.enemy_id):
		return
	_defeated_enemy_ids[enemy.enemy_id] = true
	stage_state.defeated_enemy_count += 1
	complete_stage_if_cleared()


func _clear_spawned_enemies() -> void:
	for enemy in _spawned_enemies:
		if is_instance_valid(enemy):
			if _grid != null and not enemy.is_defeated():
				_grid.clear_occupied(enemy.grid_position, enemy.enemy_id)
			enemy.queue_free()
	_spawned_enemies.clear()
	_defeated_enemy_ids.clear()
