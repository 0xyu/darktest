extends SceneTree

var _attack_count: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var grid := GridMap2D.new()
	grid.name = "Grid"
	grid.grid_size = Vector2i(8, 4)
	root.add_child(grid)

	var player := PlayerController.new()
	player.grid_path = NodePath("../Grid")
	player.grid_position = Vector2i(1, 1)
	root.add_child(player)

	var enemy := EnemyController.new()
	enemy.grid_path = NodePath("../Grid")
	enemy.grid_position = Vector2i(5, 1)
	enemy.enemy_definition = EnemyDefinition.new()
	enemy.enemy_definition.base_stats = EnemyStats.new()
	enemy.enemy_definition.base_stats.movement_points = 3
	enemy.enemy_definition.base_stats.attack_range = 1
	enemy.attack_requested.connect(_on_enemy_attack_requested)
	root.add_child(enemy)

	var manager := TurnManager.new()
	root.add_child(manager)
	var actors: Array[Node] = [enemy]
	manager.start_combat(player, actors)
	await process_frame

	_expect(manager.is_player_turn(), "combat starts on the player turn")
	_expect(grid.is_occupied(enemy.grid_position), "enemy occupies its spawn cell")
	var start_distance: int = absi(enemy.grid_position.x - player.grid_position.x) + absi(enemy.grid_position.y - player.grid_position.y)

	manager.complete_player_turn()
	_expect(manager.is_player_turn(), "enemy completion returns to the player turn")
	var end_distance: int = absi(enemy.grid_position.x - player.grid_position.x) + absi(enemy.grid_position.y - player.grid_position.y)
	_expect(end_distance < start_distance, "enemy moves toward the player")
	_expect(_attack_count == 1, "enemy requests an attack when in range")
	_expect(enemy.enemy_stats.current_hp == enemy.enemy_stats.max_hp, "Phase 6 attack request does not resolve damage")

	if _failures.is_empty():
		print("Phase 6 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _on_enemy_attack_requested(_enemy: EnemyController, _target: Node) -> void:
	_attack_count += 1


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
