class_name EnemyController
extends Node2D

signal moved(from_cell: Vector2i, to_cell: Vector2i)
signal target_selected(target: Node)
signal attack_requested(enemy: EnemyController, target: Node)

@export var grid_path: NodePath
@export var enemy_id: StringName = &"enemy"
@export var grid_position: Vector2i = Vector2i(1, 1)
@export_range(1, 999999, 1) var enemy_level: int = 1
@export var enemy_definition: EnemyDefinition

var enemy_stats: EnemyStats = EnemyStats.new()
var _grid: GridMap2D
var _target: Node


func _ready() -> void:
	_grid = get_node_or_null(grid_path) as GridMap2D
	if _grid == null:
		push_error("EnemyController requires a GridMap2D assigned through grid_path.")
		return
	if enemy_definition != null and enemy_definition.base_stats != null:
		enemy_stats = enemy_definition.base_stats.duplicate(true) as EnemyStats
	enemy_stats.level = maxi(enemy_level, 1)
	enemy_stats.current_hp = enemy_stats.max_hp
	if not _grid.is_walkable(grid_position):
		grid_position = Vector2i.ZERO
	if not _grid.is_occupied(grid_position):
		_grid.set_occupied(grid_position, enemy_id)
	global_position = _grid.grid_to_world(grid_position)
	queue_redraw()


func take_turn(player: Node, turn_manager: TurnManager) -> void:
	if _grid == null or player == null:
		turn_manager.complete_enemy_turn(self)
		return

	_target = player
	target_selected.emit(_target)
	var target_cell: Vector2i = _get_target_cell(player)
	if _grid_distance(grid_position, target_cell) > enemy_stats.attack_range:
		_move_toward_target(target_cell)
	if _grid_distance(grid_position, target_cell) <= enemy_stats.attack_range:
		attack_requested.emit(self, _target)
	turn_manager.complete_enemy_turn(self)


func get_grid_position() -> Vector2i:
	return grid_position


func _move_toward_target(target_cell: Vector2i) -> void:
	var reachable_cells: Array[Vector2i] = _grid.get_reachable_cells(grid_position, enemy_stats.movement_points)
	var best_cell: Vector2i = grid_position
	var best_distance: int = _grid_distance(grid_position, target_cell)
	for candidate in reachable_cells:
		if _grid.is_occupied(candidate):
			continue
		var candidate_distance: int = _grid_distance(candidate, target_cell)
		if candidate_distance < best_distance:
			best_cell = candidate
			best_distance = candidate_distance
	if best_cell == grid_position:
		return

	var path: Array[Vector2i] = _grid.find_path(grid_position, best_cell)
	if path.is_empty():
		return
	var previous_cell: Vector2i = grid_position
	_grid.clear_occupied(previous_cell, enemy_id)
	if not _grid.set_occupied(best_cell, enemy_id):
		_grid.set_occupied(previous_cell, enemy_id)
		return
	grid_position = best_cell
	global_position = _grid.grid_to_world(grid_position)
	queue_redraw()
	moved.emit(previous_cell, grid_position)


func _get_target_cell(target: Node) -> Vector2i:
	if target.has_method("get_grid_position"):
		return target.get_grid_position()
	var target_position: Variant = target.get("grid_position")
	if target_position is Vector2i:
		return target_position
	return grid_position


func _grid_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color("09070d", 0.9))
	draw_circle(Vector2.ZERO, 18.0, Color("9d5267"))
	draw_circle(Vector2(0, -5), 7.0, Color("e4c5a1"))
	draw_line(Vector2(-9, 7), Vector2(9, 7), Color("4a1d2e"), 4.0)
	var health_ratio: float = clampf(float(enemy_stats.current_hp) / maxi(enemy_stats.max_hp, 1), 0.0, 1.0)
	draw_rect(Rect2(-24, -38, 48, 5), Color("26151f"), true)
	draw_rect(Rect2(-24, -38, 48 * health_ratio, 5), Color("b94d63"), true)
