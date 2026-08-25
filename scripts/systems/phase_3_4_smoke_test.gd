extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var grid := GridMap2D.new()
	grid.name = "Grid"
	grid.grid_size = Vector2i(5, 5)
	grid.blocked_cells = [Vector2i(2, 1)]
	root.add_child(grid)

	var player := PlayerController.new()
	player.grid_path = NodePath("../Grid")
	player.grid_position = Vector2i(1, 1)
	root.add_child(player)
	await process_frame

	_expect(grid.is_valid_cell(Vector2i(4, 4)), "valid cell is accepted")
	_expect(not grid.is_valid_cell(Vector2i(5, 4)), "out-of-bounds cell is rejected")
	_expect(not grid.is_walkable(Vector2i(2, 1)), "blocked cell is not walkable")
	_expect(grid.is_occupied(Vector2i(1, 1)), "player cell is occupied")
	_expect(not player.try_move(Vector2i.RIGHT), "player cannot enter a blocked cell")
	_expect(player.try_move(Vector2i.DOWN), "player can move to a walkable cell")
	_expect(player.movement_points_remaining == 2, "movement points decrease after moving")
	_expect(grid.get_occupant(Vector2i(1, 2)) == &"player", "occupancy follows the player")

	var reachable := grid.get_reachable_cells(Vector2i(1, 2), 2)
	_expect(not reachable.has(Vector2i(2, 1)), "reachable cells exclude blocked cells")
	_expect(not reachable.has(Vector2i(1, 2)), "reachable cells exclude the starting cell by default")

	var path := grid.find_path(Vector2i(1, 1), Vector2i(3, 1))
	_expect(not path.is_empty(), "pathfinding finds a route around an obstacle")
	_expect(not path.has(Vector2i(2, 1)), "pathfinding avoids blocked cells")

	_expect(player.try_move(Vector2i.DOWN), "second walkable move succeeds")
	_expect(player.try_move(Vector2i.RIGHT), "third walkable move succeeds")
	_expect(not player.try_move(Vector2i.RIGHT), "movement stops when movement points are spent")
	player.reset_movement_points()
	_expect(player.movement_points_remaining == player.player_stats.movement_points, "movement points reset to player stat")

	if _failures.is_empty():
		print("Phase 3/4 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
