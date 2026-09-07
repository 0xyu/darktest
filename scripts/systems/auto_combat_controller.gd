class_name AutoCombatController
extends Node

## Drives the existing turn, grid, combat, and stage systems for AUTO mode.
## Decisions are deferred so signals from one action can finish before the
## next automatic decision is made.
signal auto_mode_changed(enabled: bool)
signal auto_action_taken(description: String)
signal farming_changed(enabled: bool)
signal game_speed_changed(speed: int)

enum GameSpeed {
	X1,
	X2,
	FASTEST,
}

@export var player_path: NodePath = NodePath("../Player")
@export var turn_manager_path: NodePath = NodePath("../TurnManager")
@export var combat_system_path: NodePath = NodePath("../CombatSystem")
@export var stage_manager_path: NodePath = NodePath("../StageManager")
@export var grid_path: NodePath = NodePath("../Grid")
@export var use_healing_items: bool = true
@export_range(0.05, 0.95, 0.05) var healing_item_threshold: float = 0.35
## Kept as the fastest mode so the existing rapid test/debug loop is preserved.
@export_range(0.01, 2.0, 0.01) var action_delay_seconds: float = 0.05
@export_range(0.10, 2.0, 0.01) var x1_action_delay_seconds: float = 0.40
@export_range(0.05, 2.0, 0.01) var x2_action_delay_seconds: float = 0.20

## FARMING keeps the fight on the current stage: once every enemy is defeated
## the stage re-spawns them so it can be repeated (AUTO keeps attacking, manual
## play resumes on the same stage). When false a cleared stage advances to the
## next one: AUTO moves on automatically and manual mode waits for the NEXT
## STAGE button.
var farming_enabled: bool = false
var _game_speed: int = GameSpeed.X1

var _player: PlayerController
var _turn_manager: TurnManager
var _combat_system: CombatSystem
var _stage_manager: StageManager
var _grid: GridMap2D
var _auto_enabled: bool = false
var _decision_scheduled: bool = false
var _decision_remaining_seconds: float = 0.0
var _decision_wait_duration: float = 0.0
var _stage_advance_scheduled: bool = false
var _run_token: int = 0
var _exit_roam_active: bool = false
var _exit_roam_remaining_seconds: float = 0.0


func _ready() -> void:
	_resolve_dependencies()
	_connect_signals()


func _process(delta: float) -> void:
	if _exit_roam_active:
		_process_exit_roam(delta)
		return
	if not _decision_scheduled:
		return
	if not _auto_enabled or _turn_manager == null or _turn_manager.get_phase() != TurnState.PLAYER_TURN:
		_decision_scheduled = false
		return
	_decision_remaining_seconds -= delta
	if _decision_remaining_seconds > 0.0:
		return
	_decision_scheduled = false
	_run_auto_turn(_run_token)


func attach_systems(
	player: PlayerController,
	turn_manager: TurnManager,
	combat_system: CombatSystem,
	stage_manager: StageManager,
	grid: GridMap2D
) -> void:
	_player = player
	_turn_manager = turn_manager
	_combat_system = combat_system
	_stage_manager = stage_manager
	_grid = grid
	_connect_signals()


func set_auto_enabled(enabled: bool) -> void:
	if enabled and _turn_manager != null and _turn_manager.get_phase() == TurnState.DEFEAT:
		return
	if _auto_enabled == enabled:
		if enabled:
			_schedule_for_current_state()
		return
	_auto_enabled = enabled
	_run_token += 1
	_decision_scheduled = false
	_stage_advance_scheduled = false
	_exit_roam_active = false
	auto_mode_changed.emit(_auto_enabled)
	if _auto_enabled:
		_schedule_for_current_state()


func toggle_auto() -> void:
	set_auto_enabled(not _auto_enabled)


func is_auto_enabled() -> bool:
	return _auto_enabled


func stop_auto() -> void:
	set_auto_enabled(false)


func set_farming_enabled(enabled: bool) -> void:
	if farming_enabled == enabled:
		return
	farming_enabled = enabled
	if farming_enabled:
		# Farming takes priority over an in-progress walk to the exit.
		if _exit_roam_active:
			_cancel_exit_roam()
		if _is_cleared_victory():
			_schedule_post_clear_transition()
	else:
		# Turning farming off mid-victory restores the auto walk-to-exit.
		if _auto_enabled and _is_cleared_victory():
			_stage_advance_scheduled = false
			_begin_exit_roam()
	farming_changed.emit(farming_enabled)


func is_farming_enabled() -> bool:
	return farming_enabled


func toggle_farming() -> void:
	set_farming_enabled(not farming_enabled)


func set_game_speed(speed: int) -> void:
	var clamped_speed: int = clampi(speed, GameSpeed.X1, GameSpeed.FASTEST)
	if _game_speed == clamped_speed:
		return
	var previous_wait_duration: float = _decision_wait_duration
	var decision_progress: float = 0.0
	if _decision_scheduled and previous_wait_duration > 0.0:
		decision_progress = clampf(
			1.0 - (_decision_remaining_seconds / previous_wait_duration),
			0.0,
			1.0
		)
	_game_speed = clamped_speed
	if _decision_scheduled:
		_decision_wait_duration = _get_action_delay_seconds()
		_decision_remaining_seconds = _decision_wait_duration * (1.0 - decision_progress)
	game_speed_changed.emit(_game_speed)


func get_game_speed() -> int:
	return _game_speed


func get_game_speed_label() -> String:
	match _game_speed:
		GameSpeed.X1:
			return "x1"
		GameSpeed.X2:
			return "x2"
		_:
			return "FASTEST"


func _resolve_dependencies() -> void:
	if _player == null:
		_player = get_node_or_null(player_path) as PlayerController
	if _turn_manager == null:
		_turn_manager = get_node_or_null(turn_manager_path) as TurnManager
	if _combat_system == null:
		_combat_system = get_node_or_null(combat_system_path) as CombatSystem
	if _stage_manager == null:
		_stage_manager = get_node_or_null(stage_manager_path) as StageManager
	if _grid == null:
		_grid = get_node_or_null(grid_path) as GridMap2D


func _connect_signals() -> void:
	if _turn_manager != null:
		if not _turn_manager.player_turn_started.is_connected(_on_player_turn_started):
			_turn_manager.player_turn_started.connect(_on_player_turn_started)
		if not _turn_manager.combat_victory.is_connected(_on_combat_victory):
			_turn_manager.combat_victory.connect(_on_combat_victory)
		if not _turn_manager.combat_defeat.is_connected(_on_combat_defeat):
			_turn_manager.combat_defeat.connect(_on_combat_defeat)
	if _stage_manager != null and not _stage_manager.stage_completed.is_connected(_on_stage_completed):
		_stage_manager.stage_completed.connect(_on_stage_completed)
	if _player != null and _player.has_signal("defeated"):
		var defeated_signal: Signal = _player.defeated
		if not defeated_signal.is_connected(_on_player_defeated):
			defeated_signal.connect(_on_player_defeated)


func _on_player_turn_started() -> void:
	_schedule_decision()


func _schedule_for_current_state() -> void:
	if _turn_manager == null:
		return
	if _turn_manager.get_phase() == TurnState.VICTORY:
		_schedule_post_clear_transition()
	elif _turn_manager.get_phase() == TurnState.PLAYER_TURN:
		_schedule_decision()


func _on_combat_victory() -> void:
	_schedule_post_clear_transition()


func _on_stage_completed(_stage_state: StageState) -> void:
	# StageManager is the source of truth for "all enemies defeated". This
	# also covers clears caused by skills and Sub Heroes, before any turn-state
	# transition is required.
	_schedule_post_clear_transition()


## After a clear, FARMING re-spawns the current stage (regardless of AUTO);
## with FARMING off, AUTO walks the hero to the exit cell and only then starts
## the next stage. Manual play without FARMING waits on the NEXT STAGE button
## and schedules nothing here.
func _schedule_post_clear_transition() -> void:
	if _stage_manager == null or _stage_advance_scheduled:
		return
	if not _auto_enabled and not farming_enabled:
		return
	if _auto_enabled and not farming_enabled:
		# AUTO & non-farming: no immediate advance. The deferred pass starts the
		# walk-to-exit once the victory phase has been set.
		_stage_advance_scheduled = true
		var token: int = _run_token
		call_deferred("_begin_exit_roam", token)
		return
	_stage_advance_scheduled = true
	var farming_token: int = _run_token
	call_deferred("_advance_after_victory", farming_token)


func _advance_after_victory(token: int) -> void:
	_stage_advance_scheduled = false
	if token != _run_token:
		return
	if _stage_manager == null or not farming_enabled:
		return
	if _turn_manager == null or _turn_manager.get_phase() != TurnState.VICTORY:
		if _stage_manager.stage_state == null or not _stage_manager.stage_state.is_complete:
			return
	var stage_started: bool = _stage_manager.initialize_stage(_stage_manager.stage_state.stage_number)
	if not stage_started:
		if _auto_enabled:
			stop_auto()
		auto_action_taken.emit("Cleared stage could not be restarted")


func _is_cleared_victory() -> bool:
	return (
		_turn_manager != null
		and _turn_manager.get_phase() == TurnState.VICTORY
		and _stage_manager != null
		and _stage_manager.stage_state != null
		and _stage_manager.stage_state.is_complete
	)


func _begin_exit_roam(token: int = -1) -> void:
	_stage_advance_scheduled = false
	if token != -1 and token != _run_token:
		return
	if _exit_roam_active:
		return
	if not _auto_enabled or farming_enabled:
		return
	if not _is_cleared_victory():
		return
	if _stage_manager == null or not _stage_manager.has_method("get_stage_exit_cell"):
		return
	if _player == null or _player.is_defeated():
		return
	_decision_scheduled = false
	_exit_roam_active = true
	_exit_roam_remaining_seconds = _get_action_delay_seconds()


func _cancel_exit_roam() -> void:
	if _exit_roam_active:
		_exit_roam_active = false
		_run_token += 1


func _process_exit_roam(delta: float) -> void:
	if _turn_manager == null or not _auto_enabled or farming_enabled:
		_cancel_exit_roam()
		if farming_enabled and _is_cleared_victory():
			_schedule_post_clear_transition()
		return
	if _turn_manager.get_phase() != TurnState.VICTORY or _player == null or _player.is_defeated():
		_cancel_exit_roam()
		return
	_exit_roam_remaining_seconds -= delta
	if _exit_roam_remaining_seconds > 0.0:
		return
	_step_exit_roam()


func _step_exit_roam() -> void:
	if _stage_manager == null:
		_cancel_exit_roam()
		return
	var exit_cell: Vector2i = _stage_manager.get_stage_exit_cell()
	if _player.grid_position == exit_cell:
		_exit_roam_active = false
		_start_next_stage_from_exit()
		return
	if _grid == null:
		_cancel_exit_roam()
		return
	var path: Array[Vector2i] = _grid.find_path(_player.grid_position, exit_cell)
	if path.size() < 2:
		_cancel_exit_roam()
		return
	var direction: Vector2i = path[1] - _player.grid_position
	if _player.try_move(direction):
		_exit_roam_remaining_seconds = _get_action_delay_seconds()
		auto_action_taken.emit("AUTO: heading to the exit")
	else:
		_cancel_exit_roam()


func _start_next_stage_from_exit() -> void:
	if not _auto_enabled or farming_enabled:
		return
	if _turn_manager == null or _turn_manager.get_phase() != TurnState.VICTORY:
		return
	var stage_started: bool = _stage_manager.start_next_stage()
	if not stage_started:
		if _auto_enabled:
			stop_auto()
		auto_action_taken.emit("Could not start the next stage")


func _on_combat_defeat() -> void:
	# AUTO stays enabled through the defeat retreat so the idle loop resumes
	# automatically on the previous stage.
	pass


func _on_player_defeated() -> void:
	# Fires before combat_defeat from handle_defeat(); AUTO stays enabled.
	pass


func _schedule_decision() -> void:
	if not _auto_enabled or _decision_scheduled or _turn_manager == null:
		return
	if _turn_manager.get_phase() != TurnState.PLAYER_TURN:
		return
	_decision_scheduled = true
	_decision_wait_duration = _get_action_delay_seconds()
	_decision_remaining_seconds = _decision_wait_duration


func _run_auto_turn(token: int) -> void:
	_decision_scheduled = false
	if token != _run_token or not _auto_enabled:
		return
	if _turn_manager == null or _turn_manager.get_phase() != TurnState.PLAYER_TURN:
		return
	if _player == null or _player.is_defeated():
		stop_auto()
		return
	if _player.movement_points_remaining <= 0:
		_end_player_turn("AUTO: movement exhausted")
		return

	var target: EnemyController = _select_target()
	if target == null:
		if _has_living_enemies():
			stop_auto()
			auto_action_taken.emit("AUTO stopped: no reachable target")
		else:
			_end_player_turn("AUTO: no living target")
		return
	_player.set_target(target)

	if _should_use_healing_item() and _player.use_healing_item():
		auto_action_taken.emit("AUTO: used healing item")
		_end_player_turn("")
		return

	var attack_range: int = _get_player_attack_range()
	if _grid_distance(_player.grid_position, target.grid_position) <= attack_range:
		_perform_attack(target)
		return

	var moved_cells: int = _move_toward_target(target, attack_range)
	if _grid_distance(_player.grid_position, target.grid_position) <= attack_range:
		_perform_attack(target)
		return
	if moved_cells > 0:
		auto_action_taken.emit("AUTO: moved toward %s" % target.get_display_name())
	_end_player_turn("AUTO: target out of range")


func _select_target() -> EnemyController:
	if _stage_manager == null:
		return null
	var best_target: EnemyController
	var best_distance: int = 2147483647
	var best_hp: int = 2147483647
	for enemy in _stage_manager.get_spawned_enemies():
		if enemy == null or not is_instance_valid(enemy) or enemy.is_defeated():
			continue
		if enemy.enemy_runtime == null or enemy.enemy_runtime.current_hp <= 0:
			continue
		var distance: int = _grid_distance(_player.grid_position, enemy.grid_position)
		if distance > _get_player_attack_range() and (_grid == null or _get_best_destination(enemy.grid_position, _player.movement_points_remaining, _get_player_attack_range()) == _player.grid_position):
			continue
		var current_hp: int = enemy.enemy_runtime.current_hp
		if distance < best_distance or (distance == best_distance and current_hp < best_hp):
			best_target = enemy
			best_distance = distance
			best_hp = current_hp
	return best_target


func _has_living_enemies() -> bool:
	if _stage_manager == null:
		return false
	for enemy in _stage_manager.get_spawned_enemies():
		if enemy != null and is_instance_valid(enemy) and not enemy.is_defeated() and enemy.enemy_runtime != null and enemy.enemy_runtime.current_hp > 0:
			return true
	return false


func _move_toward_target(target: EnemyController, attack_range: int) -> int:
	if _grid == null or _player == null or target == null:
		return 0
	var movement_points: int = maxi(_player.movement_points_remaining, 0)
	if movement_points <= 0:
		return 0
	var destination: Vector2i = _get_best_destination(target.grid_position, movement_points, attack_range)
	if destination == _player.grid_position:
		return 0
	var path: Array[Vector2i] = _grid.find_path(_player.grid_position, destination)
	if path.size() < 2:
		return 0
	var moved_cells: int = 0
	for path_index in range(1, path.size()):
		var direction: Vector2i = path[path_index] - _player.grid_position
		if not _player.try_move(direction):
			break
		moved_cells += 1
	return moved_cells


func _get_best_destination(target_cell: Vector2i, movement_points: int, attack_range: int) -> Vector2i:
	var start_cell: Vector2i = _player.grid_position
	var best_cell: Vector2i = start_cell
	var best_distance: int = _grid_distance(start_cell, target_cell)
	var best_in_range: bool = best_distance <= attack_range
	for candidate in _grid.get_reachable_cells(start_cell, movement_points):
		if _grid.is_occupied(candidate):
			continue
		var candidate_distance: int = _grid_distance(candidate, target_cell)
		var candidate_in_range: bool = candidate_distance <= attack_range
		if candidate_in_range and not best_in_range:
			best_cell = candidate
			best_distance = candidate_distance
			best_in_range = true
		elif candidate_in_range == best_in_range and candidate_distance < best_distance:
			best_cell = candidate
			best_distance = candidate_distance
	return best_cell


func _perform_attack(target: EnemyController) -> void:
	if _combat_system == null:
		_player.attack_requested.emit(_player, target)
	else:
		_combat_system.resolve_attack(_player, target)
	if _turn_manager != null and _turn_manager.is_player_turn():
		_turn_manager.complete_player_turn()
	auto_action_taken.emit("AUTO: attacked %s" % target.get_display_name())


func _end_player_turn(description: String) -> void:
	if not description.is_empty():
		auto_action_taken.emit(description)
	if _turn_manager != null and _turn_manager.is_player_turn():
		_turn_manager.complete_player_turn()


func _should_use_healing_item() -> bool:
	if not use_healing_items or _player == null or _player.player_stats == null:
		return false
	if _player.get_healing_item_count() <= 0 or _player.player_stats.max_hp <= 0:
		return false
	var health_ratio: float = float(_player.player_stats.current_hp) / float(_player.player_stats.max_hp)
	return health_ratio <= healing_item_threshold


func _get_player_attack_range() -> int:
	if _player == null or _player.player_stats == null:
		return 1
	return maxi(_player.player_stats.attack_range, 0)


func _get_action_delay_seconds() -> float:
	match _game_speed:
		GameSpeed.X1:
			return maxf(x1_action_delay_seconds, 0.0)
		GameSpeed.X2:
			return maxf(x2_action_delay_seconds, 0.0)
		_:
			return maxf(action_delay_seconds, 0.0)


func _grid_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
