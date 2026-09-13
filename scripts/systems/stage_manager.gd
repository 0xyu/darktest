class_name StageManager
extends Node

const EnemyScalingSystem = preload("res://scripts/systems/enemy_scaling.gd")
const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")

## Consumes final StageDefinitions and owns only battle-stage spawning/state.
signal stage_started(stage_state: StageState, enemies: Array[Node])
signal enemy_spawned(enemy: Node)
signal stage_completed(stage_state: StageState)
signal stage_generation_failed(stage_number: int, reason: String)

## Which arena gate the hero walks in through when a stage is generated.
##
## FROM_START_POINT is the forward direction: the battle arrives from behind, so
## the hero is placed one cell right of the Stage Starting Point. It covers map
## entry, the first boot, farming re-spawn and every "next stage" advance.
## FROM_NEXT_STAGE_POINT is the walk backwards: the hero arrives through the Next
## Stage Point and is placed one cell left of it.
enum Arrival {
	FROM_START_POINT,
	FROM_NEXT_STAGE_POINT,
}

@export var grid_path: NodePath
@export var spawn_parent_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../Player")
@export var level_manager_path: NodePath = NodePath("../LevelManager")
@export var enemy_scene: PackedScene
@export_range(1, 999999, 1) var starting_stage: int = 1
## 0-based y row of the arena gate lane: the Stage Starting Point sits on the
## left edge of this row and the Next Stage Point / exit on the right edge.
## It is also the ONLY row where the grid's two outer columns are usable, so it
## is pushed into GridMap2D.gate_row (see _resolve_references).
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


func initialize_stage(new_stage_number: int = -1, requested_special_encounter_type: int = SpecialEncounterTypeResource.NONE, arrival: int = Arrival.FROM_START_POINT) -> bool:
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
	# the first boot) re-enters the arena through the gate the battle arrived at,
	# one cell inward from it (`arrival`). Farming re-spawns the SAME number, so
	# the hero stays where it is and `arrival` is not consulted.
	var teleport_to_start: bool = _active_stage_number != target_stage
	_clear_spawned_enemies()
	current_definition = _level_manager.request_level(target_stage, requested_special_encounter_type)
	if current_definition == null:
		return false
	if teleport_to_start:
		_place_player_at_arrival(arrival)
	stage_state.reset_for_stage(target_stage, current_definition.is_mini_boss_stage)
	stage_state.is_special_encounter = current_definition.is_special_encounter
	stage_state.special_encounter_type = current_definition.special_encounter_type
	stage_state.special_mini_boss_level = current_definition.special_mini_boss_level
	if current_definition.boss != null:
		stage_state.encounter_id = current_definition.boss.id
	elif current_definition.special_enemy_definition != null:
		stage_state.encounter_id = current_definition.special_enemy_definition.id
	_defeated_enemy_ids.clear()

	# §4.2: the encounter size c is FROZEN here, when the stage is built, from the number of
	# enemies the stage actually opens with — killing one never re-scales the survivors — and
	# the rule set (normal / training / Mini Boss) is decided once, at the same moment.
	var encounter_count: int = 0
	for entry in current_definition.enemy_entries:
		if entry != null and entry.enemy_definition != null:
			encounter_count += maxi(entry.count, 0)
	var encounter_kind: int = EnemyScalingSystem.Kind.NORMAL
	if current_definition.boss != null:
		encounter_kind = EnemyScalingSystem.Kind.MINI_BOSS
	elif current_definition.is_special_encounter:
		encounter_count = 1
	elif BalanceFormulas.is_training_stage(get_balance_profile(), target_stage):
		encounter_kind = EnemyScalingSystem.Kind.TRAINING
	encounter_count = maxi(encounter_count, 1)

	var available_cells := _get_available_spawn_cells()
	var spawned_nodes: Array[Node] = []
	if current_definition.boss != null:
		var boss_cells := _take_spawn_cells(available_cells, 1, StageEnemyEntry.SpawnRule.RANDOM)
		if boss_cells.size() != 1:
			return _fail_spawn(target_stage, "Not enough walkable cells to spawn the stage boss.")
		var boss_level: int = target_stage if not current_definition.is_special_encounter else current_definition.special_mini_boss_level
		var boss := _spawn_enemy(current_definition.boss, target_stage, boss_cells[0], StringName("stage_%d_boss" % target_stage), boss_level, null, encounter_kind, encounter_count)
		if boss == null:
			return false
		spawned_nodes.append(boss)
	elif current_definition.is_special_encounter:
		var special_definition: EnemyData = current_definition.special_enemy_definition
		var special_level: int = current_definition.special_mini_boss_level if current_definition.special_encounter_type == SpecialEncounterTypeResource.RANDOM_MINI_BOSS else target_stage
		var special_cells := _take_spawn_cells(available_cells, 1, StageEnemyEntry.SpawnRule.RANDOM)
		if special_cells.size() != 1:
			return _fail_spawn(target_stage, "Not enough walkable cells to spawn the special enemy.")
		var special_enemy := _spawn_enemy(special_definition, target_stage, special_cells[0], StringName("stage_%d_special" % target_stage), special_level, null, encounter_kind, encounter_count)
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
				var enemy := _spawn_enemy(entry.enemy_definition, target_stage, cell, StringName("stage_%d_enemy_%d" % [target_stage, enemy_index]), entry.get_level(target_stage), entry, encounter_kind, encounter_count)
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


## Moves the battle one stage back: the player stepped onto the Stage Starting
## Point, or was pushed back by a defeat. The hero arrives through the Next Stage
## Point, one cell left of it.
func start_previous_stage() -> bool:
	return initialize_stage(
		maxi(stage_state.stage_number - 1, 1),
		SpecialEncounterTypeResource.NONE,
		Arrival.FROM_NEXT_STAGE_POINT
	)


func get_spawned_enemies() -> Array[EnemyController]:
	return _spawned_enemies.duplicate()


## The left arrival cell of the arena (Stage Starting Point). The hero walks back
## out through it into the previous stage.
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


## Where the hero stands right after a stage is generated: one cell inward from
## the gate the battle arrived through, so both gate cells stay free for walking
## back out. Forward stages start one cell right of the Stage Starting Point;
## walking backwards starts one cell left of the Next Stage Point.
func get_stage_arrival_cell(arrival: int = Arrival.FROM_START_POINT) -> Vector2i:
	if arrival == Arrival.FROM_NEXT_STAGE_POINT:
		return get_stage_exit_cell() + Vector2i.LEFT
	return get_stage_start_cell() + Vector2i.RIGHT


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
	_sync_grid_gate_row()


## The gate lane row is the one row whose two outer columns are usable, so the
## grid needs it to know which cells are positions and which are unusable. This
## manager owns the row; the grid is told, never asked.
func _sync_grid_gate_row() -> void:
	if _grid != null:
		_grid.gate_row = stage_gate_row


## Best-effort teleport of the hero onto the arrival cell of the gate the stage
## was entered through, so enemies spawn away from the arena gate. Runs before
## enemies spawn, therefore the arrival cell is occupied and excluded from spawn
## candidates. If the arrival cell is unusable or taken, the gate cell itself is
## used instead, so the hero is never left standing in another stage's arena.
func _place_player_at_arrival(arrival: int) -> void:
	if _player == null or not _player.has_method("place_at"):
		return
	if _player.place_at(get_stage_arrival_cell(arrival)):
		return
	var gate_cell: Vector2i = (
		get_stage_exit_cell() if arrival == Arrival.FROM_NEXT_STAGE_POINT else get_stage_start_cell()
	)
	_player.place_at(gate_cell)


## Walkable cells an enemy may spawn on: the whole arena except the two gate
## cells, which belong to the stage entrance and exit and must stay free for the
## walk into the next stage / back into the previous one.
func _get_available_spawn_cells() -> Array[Vector2i]:
	var reserved_gate_cells: Array[Vector2i] = [get_stage_start_cell(), get_stage_exit_cell()]
	var available_cells: Array[Vector2i] = []
	for y in range(_grid.grid_size.y):
		for x in range(_grid.grid_size.x):
			var cell := Vector2i(x, y)
			if reserved_gate_cells.has(cell):
				continue
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


## §4.2/§4.3/§5/§6.1: the stats AND the rewards one spawn fights and pays with. The stage manager
## supplies only the stage-level inputs — the frozen encounter size, the real level offset and the
## per-stat variance — and [EnemyScaling] owns the formulas, so difficulty(S) is applied exactly
## once (it travels on the StageDefinition), a per-entry correction is applied once, on the stat it
## names, and the reward curve is written with the same offset multiplier the stats used.
##
## R2 removed the legacy `rate^(stage-1)` reward scaling from this path: EXP and Gold now come from
## `G(S)`, and both [ExperienceSystem] and [GoldSystem] read the runtime value instead of scaling
## it a second time.
func _scale_enemy_runtime(
	enemy: EnemyController,
	stage_number: int,
	entry: StageEnemyEntry = null,
	encounter_kind: int = EnemyScalingSystem.Kind.NORMAL,
	encounter_count: int = 1
) -> void:
	if enemy.enemy_data == null or enemy.enemy_data.base_stats == null:
		return
	var profile: BalanceProfile = get_balance_profile()
	var base_stats: EnemyStats = enemy.enemy_data.base_stats
	# §4.2: `o = enemy_level - S` uses the CLAMPED real offset, so the display level and the
	# risk multiplier can never disagree. Training stages and Mini Bosses are offset 0.
	var enemy_offset: int = maxi(enemy.enemy_level, 1) - maxi(stage_number, 1)
	if encounter_kind != EnemyScalingSystem.Kind.NORMAL:
		enemy_offset = 0
	var scaled_stats: EnemyStats = EnemyScalingSystem.build_combat_stats(
		profile,
		base_stats,
		stage_number,
		encounter_kind,
		enemy_offset,
		encounter_count,
		_roll_variance(encounter_kind),
		_entry_multipliers(entry),
		enemy.enemy_data.enemy_type
	)
	if scaled_stats == null:
		return
	enemy.initialize_runtime_from_stats(scaled_stats)


## §4.2: each stat gets its OWN uniform factor from the profile's band. Training stages and Mini
## Bosses are exact — an authored fight stays the same fight for every player.
func _roll_variance(encounter_kind: int) -> Array[float]:
	if encounter_kind != EnemyScalingSystem.Kind.NORMAL:
		return EnemyScalingSystem.unity_variance()
	var profile: BalanceProfile = get_balance_profile()
	var minimum: float = minf(profile.enemy_variance_min, profile.enemy_variance_max)
	var maximum: float = maxf(profile.enemy_variance_min, profile.enemy_variance_max)
	return [
		_random_number_generator.randf_range(minimum, maximum),
		_random_number_generator.randf_range(minimum, maximum),
		_random_number_generator.randf_range(minimum, maximum),
	]


## The per-entry corrections of §4.2, in HP / ATK / DEF order, or an empty array for "none".
func _entry_multipliers(entry: StageEnemyEntry) -> Array[float]:
	if entry == null:
		return []
	return [entry.hp_multiplier, entry.attack_multiplier, entry.defense_multiplier]


## §7: the profile the provider owns. A stage manager configured without a level manager (a
## headless fixture) still gets the shipped default instead of restating a balance number, and
## the world hands the SAME instance to the hero and to the damage entry.
func get_balance_profile() -> BalanceProfile:
	if _level_manager != null:
		return _level_manager.get_balance_profile()
	return BalanceProfile.get_default()


func _spawn_enemy(enemy_data: EnemyData, stage_number: int, spawn_cell: Vector2i, generated_id: StringName, level: int, entry: StageEnemyEntry = null, encounter_kind: int = EnemyScalingSystem.Kind.NORMAL, encounter_count: int = 1) -> EnemyController:
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
	_scale_enemy_runtime(enemy, stage_number, entry, encounter_kind, encounter_count)
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
			stage_state.stage_number,
			null,
			EnemyScalingSystem.Kind.NORMAL,
			# §4.2: the encounter size a summon fights under is the group the stage opened
			# with — a summon joins that encounter, it does not re-freeze it.
			maxi(stage_state.spawned_enemy_count, 1)
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
