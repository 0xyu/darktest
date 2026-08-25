extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var grid := GridMap2D.new()
	grid.name = "Grid"
	grid.grid_size = Vector2i(6, 3)
	root.add_child(grid)

	var player := PlayerController.new()
	player.grid_path = NodePath("../Grid")
	player.grid_position = Vector2i(1, 1)
	player.player_stats = PlayerStats.new()
	player.player_stats.attack = 20
	player.player_stats.critical_chance = 1.0
	player.player_stats.critical_damage = 1.5
	root.add_child(player)

	var enemy := EnemyController.new()
	enemy.grid_path = NodePath("../Grid")
	enemy.grid_position = Vector2i(2, 1)
	enemy.enemy_definition = EnemyDefinition.new()
	enemy.enemy_definition.base_stats = EnemyStats.new()
	enemy.enemy_definition.base_stats.max_hp = 100
	enemy.enemy_definition.base_stats.current_hp = 100
	enemy.enemy_definition.base_stats.defense = 5
	enemy.enemy_definition.base_stats.attack_range = 1
	root.add_child(enemy)

	var combat := CombatSystem.new()
	root.add_child(combat)
	await process_frame

	var result := combat.resolve_attack(player, enemy)
	_expect(not result.is_miss, "adjacent target is in attack range")
	_expect(result.is_critical, "critical chance produces a critical hit")
	_expect(result.raw_damage == 15, "damage uses attack minus defense")
	_expect(result.final_damage == 23, "critical damage uses the 150 percent multiplier")
	_expect(enemy.enemy_stats.current_hp == 77, "damage reduces enemy HP")

	combat.connect_actor(enemy)
	enemy.attack_requested.emit(enemy, player)
	_expect(player.player_stats.current_hp == 97, "enemy attack resolves without player-only critical stats")

	var far_enemy := EnemyController.new()
	far_enemy.grid_path = NodePath("../Grid")
	far_enemy.grid_position = Vector2i(5, 1)
	far_enemy.enemy_definition = EnemyDefinition.new()
	far_enemy.enemy_definition.base_stats = EnemyStats.new()
	root.add_child(far_enemy)
	await process_frame
	var out_of_range := combat.resolve_attack(player, far_enemy)
	_expect(out_of_range.is_miss, "target outside attack range is rejected")
	_expect(far_enemy.enemy_stats.current_hp == far_enemy.enemy_stats.max_hp, "missed attack does not reduce HP")

	player.player_stats.attack = 200
	var defeat_result := combat.resolve_attack(player, enemy)
	_expect(defeat_result.target_defeated, "lethal damage marks the target defeated")
	_expect(enemy.is_defeated(), "enemy enters defeated state")
	_expect(not grid.is_occupied(enemy.grid_position), "defeated enemy releases its grid cell")

	if _failures.is_empty():
		print("Phase 7 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
