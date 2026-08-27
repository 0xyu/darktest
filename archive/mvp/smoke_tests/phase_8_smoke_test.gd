extends SceneTree

var _failures: Array[String] = []
var _stage_completed_count: int = 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var grid := GridMap2D.new()
	grid.name = "Grid"
	grid.grid_size = Vector2i(8, 5)
	grid.blocked_cells = [Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)]
	root.add_child(grid)

	var player := PlayerController.new()
	player.grid_path = NodePath("../Grid")
	player.grid_position = Vector2i(1, 2)
	root.add_child(player)

	var manager := StageManager.new()
	manager.grid_path = NodePath("../Grid")
	manager.spawn_parent_path = NodePath("..")
	manager.enemy_scene = preload("res://scenes/enemies/Enemy.tscn")
	manager.random_seed = 2468
	manager.base_enemy_count = 1
	manager.enemy_count_growth_interval = 1
	manager.max_enemy_count = 3
	manager.stage_completed.connect(_on_stage_completed)
	root.add_child(manager)
	await process_frame

	_expect(manager.initialize_stage(1), "stage one initializes")
	_expect(manager.stage_state.stage_number == 1, "stage number is initialized")
	_expect(manager.stage_state.spawned_enemy_count == 1, "stage one spawns the configured enemy count")
	var stage_one_enemy: EnemyController = manager.get_spawned_enemies()[0]
	_expect(grid.is_valid_cell(stage_one_enemy.grid_position), "enemy spawns inside the grid")
	_expect(grid.is_walkable(stage_one_enemy.grid_position), "enemy spawns on a walkable cell")
	_expect(stage_one_enemy.grid_position != player.grid_position, "enemy does not spawn on the player")
	_expect(grid.is_occupied(stage_one_enemy.grid_position), "spawned enemy occupies its cell")

	for _index in range(100):
		var level: int = manager.roll_enemy_level(10)
		_expect(level >= 7 and level <= 13, "enemy level variance stays within three levels")

	stage_one_enemy.handle_defeat()
	_expect(manager.stage_state.is_complete, "stage completes after all enemies are defeated")
	_expect(_stage_completed_count == 1, "stage completion emits once")
	_expect(manager.start_next_stage(), "next stage starts after completion")
	_expect(manager.stage_state.stage_number == 2, "next stage increments sequentially")
	_expect(manager.stage_state.spawned_enemy_count == 2, "next stage uses its generated enemy count")

	if _failures.is_empty():
		print("Phase 8 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _on_stage_completed(_stage_state: StageState) -> void:
	_stage_completed_count += 1


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
