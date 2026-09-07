class_name GridMap2D
extends Node2D

## Reusable 2D orthogonal grid. Actors are represented by StringName IDs only;
## this keeps the grid independent from player and enemy scene scripts.
signal occupancy_changed(cell: Vector2i)

const ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]

@export var grid_size: Vector2i = Vector2i(12, 8)
@export_range(8, 256, 1) var cell_size: int = 64
@export var origin: Vector2 = Vector2.ZERO
@export var blocked_cells: Array[Vector2i] = []
@export var draw_grid: bool = true

var _occupied_cells: Dictionary = {}
var _highlighted_cells: Array[Vector2i] = []
var _selected_cell: Vector2i = Vector2i(-1, -1)
var _marker_cells: Dictionary = {}


func _ready() -> void:
	queue_redraw()


func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func is_walkable(cell: Vector2i) -> bool:
	return is_valid_cell(cell) and not blocked_cells.has(cell)


func is_occupied(cell: Vector2i) -> bool:
	return _occupied_cells.has(cell)


func get_occupant(cell: Vector2i) -> StringName:
	return StringName(_occupied_cells.get(cell, &""))


func set_occupied(cell: Vector2i, actor_id: StringName) -> bool:
	if not is_walkable(cell) or is_occupied(cell):
		return false
	_occupied_cells[cell] = actor_id
	occupancy_changed.emit(cell)
	return true


func clear_occupied(cell: Vector2i, actor_id: StringName = &"") -> bool:
	if not is_occupied(cell):
		return false
	if not actor_id.is_empty() and get_occupant(cell) != actor_id:
		return false
	_occupied_cells.erase(cell)
	occupancy_changed.emit(cell)
	return true


func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for direction in ORTHOGONAL_DIRECTIONS:
		var neighbor: Vector2i = cell + direction
		if is_walkable(neighbor):
			neighbors.append(neighbor)
	return neighbors


func get_reachable_cells(start: Vector2i, max_steps: int, include_start: bool = false) -> Array[Vector2i]:
	var reachable: Array[Vector2i] = []
	if not is_walkable(start) or max_steps < 0:
		return reachable

	var distances: Dictionary = {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var distance: int = distances[current]
		if include_start or current != start:
			reachable.append(current)
		if distance >= max_steps:
			continue

		for neighbor in get_neighbors(current):
			if distances.has(neighbor):
				continue
			if is_occupied(neighbor) and neighbor != start:
				continue
			distances[neighbor] = distance + 1
			frontier.append(neighbor)
	return reachable


func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not is_walkable(start) or not is_walkable(goal):
		return path
	if start == goal:
		path.append(start)
		return path
	if is_occupied(goal):
		return path

	var came_from: Dictionary = {start: start}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			break
		for neighbor in get_neighbors(current):
			if came_from.has(neighbor):
				continue
			if is_occupied(neighbor) and neighbor != goal:
				continue
			came_from[neighbor] = current
			frontier.append(neighbor)

	if not came_from.has(goal):
		return path

	var current_cell: Vector2i = goal
	while current_cell != start:
		path.push_front(current_cell)
		current_cell = came_from[current_cell]
	path.push_front(start)
	return path


func grid_to_world(cell: Vector2i) -> Vector2:
	return origin + Vector2(cell * cell_size) + Vector2.ONE * (cell_size * 0.5)


func world_to_grid(world_position: Vector2) -> Vector2i:
	var local_position: Vector2 = world_position - origin
	return Vector2i(floori(local_position.x / cell_size), floori(local_position.y / cell_size))


func get_cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(cell * cell_size), Vector2.ONE * cell_size)


func set_highlighted_cells(cells: Array[Vector2i]) -> void:
	_highlighted_cells = cells.duplicate()
	queue_redraw()


func set_selected_cell(cell: Vector2i) -> void:
	_selected_cell = cell
	queue_redraw()


## Marks a special arena cell (e.g. the stage exit / entrance) with a colored
## frame so the player can find it. Draws after the normal cell loop.
func set_arena_marker(cell: Vector2i, color: Color) -> void:
	_marker_cells[cell] = color
	queue_redraw()


func clear_arena_markers() -> void:
	if not _marker_cells.is_empty():
		_marker_cells.clear()
		queue_redraw()


func _draw() -> void:
	if not draw_grid:
		return
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			var rect: Rect2 = get_cell_rect(cell)
			var fill_color := Color("171522", 0.68) if (x + y) % 2 == 0 else Color("1c1929", 0.68)
			if not is_walkable(cell):
				fill_color = Color("0b0a10", 0.78)
			if _highlighted_cells.has(cell) and is_walkable(cell):
				fill_color = Color("3a344d")
			draw_rect(rect, fill_color, true)
			if _selected_cell == cell:
				draw_rect(rect.grow(-3.0), Color("c59b52", 0.85), false, 2.0)
			draw_rect(rect, Color("4d465e", 0.8), false, 1.0)
			if not is_walkable(cell):
				draw_rect(rect.grow(-8.0), Color("342b3c"), true)
	for marker_cell in _marker_cells:
		var marker_color: Color = _marker_cells[marker_cell]
		var marker_rect: Rect2 = get_cell_rect(marker_cell).grow(-6.0)
		draw_rect(marker_rect, Color(marker_color, 0.12), true)
		draw_rect(marker_rect, marker_color, false, 2.0)
