class_name PlayerController
extends Node2D

signal moved(from_cell: Vector2i, to_cell: Vector2i, movement_points_remaining: int)
signal selection_changed(is_selected: bool)
signal action_completed
signal attack_requested(attacker: Node, target: Node)
signal defeated
signal experience_gained(amount: int, current_experience: int, required_experience: int)
signal level_up(new_level: int)

@export var grid_path: NodePath
@export var player_id: StringName = &"player"
@export var grid_position: Vector2i = Vector2i(1, 1)
@export var player_stats: PlayerStats = PlayerStats.new()
@export var player_progression: PlayerProgression = PlayerProgression.new()
@export var is_selected: bool = true
@export var target_path: NodePath

var movement_points_remaining: int = 0
var _grid: GridMap2D
var _input_enabled: bool = true
var _turn_manager: Node
var _is_defeated: bool = false
var _target: Node


func _ready() -> void:
	_grid = get_node_or_null(grid_path) as GridMap2D
	if _grid == null:
		push_error("PlayerController requires a GridMap2D assigned through grid_path.")
		return
	if not _grid.is_walkable(grid_position):
		grid_position = Vector2i.ZERO
	if not _grid.is_occupied(grid_position):
		_grid.set_occupied(grid_position, player_id)
	global_position = _grid.grid_to_world(grid_position)
	reset_movement_points()
	_input_enabled = true
	_refresh_grid_feedback()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _grid == null:
		return
	if event.is_action_pressed("move_up"):
		try_move(Vector2i.UP)
	elif event.is_action_pressed("move_right"):
		try_move(Vector2i.RIGHT)
	elif event.is_action_pressed("move_down"):
		try_move(Vector2i.DOWN)
	elif event.is_action_pressed("move_left"):
		try_move(Vector2i.LEFT)
	elif event.is_action_pressed("primary_action"):
		if _turn_manager != null:
			action_completed.emit()
		else:
			reset_movement_points()
	elif event.is_action_pressed("attack"):
		if _input_enabled and is_selected:
			attack_requested.emit(self, _get_attack_target())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked_cell: Vector2i = _grid.world_to_grid(get_global_mouse_position())
		if clicked_cell == grid_position:
			set_selected(not is_selected)


func try_move(direction: Vector2i) -> bool:
	if not _input_enabled or not is_selected or movement_points_remaining <= 0 or _grid == null:
		return false
	var target_cell: Vector2i = grid_position + direction
	if not _grid.is_walkable(target_cell) or _grid.is_occupied(target_cell):
		return false

	var previous_cell: Vector2i = grid_position
	_grid.clear_occupied(previous_cell, player_id)
	_grid.set_occupied(target_cell, player_id)
	grid_position = target_cell
	movement_points_remaining -= 1
	global_position = _grid.grid_to_world(grid_position)
	_refresh_grid_feedback()
	queue_redraw()
	moved.emit(previous_cell, grid_position, movement_points_remaining)
	return true


func reset_movement_points() -> void:
	if player_stats == null:
		return
	movement_points_remaining = maxi(player_stats.movement_points, 0)
	_refresh_grid_feedback()
	queue_redraw()


func begin_player_turn(movement_points: int = -1) -> void:
	_input_enabled = true
	if movement_points >= 0:
		movement_points_remaining = movement_points
		_refresh_grid_feedback()
		queue_redraw()
	else:
		reset_movement_points()


func end_player_turn() -> void:
	_input_enabled = false
	_refresh_grid_feedback()
	queue_redraw()


func attach_turn_manager(turn_manager: Node) -> void:
	_turn_manager = turn_manager


func set_target(target: Node) -> void:
	_target = target


func get_target() -> Node:
	return _get_attack_target()


func is_input_enabled() -> bool:
	return _input_enabled


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	_refresh_grid_feedback()
	queue_redraw()
	selection_changed.emit(is_selected)


func get_grid_position() -> Vector2i:
	return grid_position


func handle_defeat() -> void:
	if _is_defeated:
		return
	_is_defeated = true
	player_stats.current_hp = 0
	_input_enabled = false
	if _grid != null:
		_grid.clear_occupied(grid_position, player_id)
	queue_redraw()
	defeated.emit()


func is_defeated() -> bool:
	return _is_defeated


func get_level() -> int:
	if player_progression == null:
		return 1
	return maxi(player_progression.level, 1)


func get_experience() -> int:
	if player_progression == null:
		return 0
	return maxi(player_progression.experience, 0)


func get_experience_to_next_level() -> int:
	if player_progression == null:
		return 1
	return player_progression.experience_to_next_level()


func notify_experience_gained(amount: int, current_experience: int, required_experience: int) -> void:
	experience_gained.emit(amount, current_experience, required_experience)


func notify_level_up(new_level: int) -> void:
	level_up.emit(new_level)


func _get_attack_target() -> Node:
	if _target != null and is_instance_valid(_target):
		return _target
	return get_node_or_null(target_path)


func _refresh_grid_feedback() -> void:
	if _grid == null:
		return
	_grid.set_selected_cell(grid_position)
	if is_selected:
		_grid.set_highlighted_cells(_grid.get_reachable_cells(grid_position, movement_points_remaining))
	else:
		_grid.set_highlighted_cells([])


func _draw() -> void:
	var body_color := Color("5c5366") if _is_defeated else (Color("b7a2d1") if is_selected else Color("736a82"))
	draw_circle(Vector2.ZERO, 22.0, Color("08070c", 0.85))
	draw_circle(Vector2.ZERO, 18.0, body_color)
	draw_circle(Vector2(0, -5), 7.0, Color("e3c889"))
	draw_line(Vector2(-9, 7), Vector2(9, 7), Color("4b294e"), 4.0)
	if is_selected:
		draw_arc(Vector2.ZERO, 29.0, 0.0, TAU, 32, Color("d8af5c"), 2.0)
