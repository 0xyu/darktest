extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var main_scene := load("res://scenes/world/Main.tscn") as PackedScene
	_expect(main_scene != null, "main scene can be loaded")
	if main_scene == null:
		_quit_with_result()
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var game := main.get_node("grid_combat") as grid_combat
	_expect(game.stage_manager.initialize_stage(3), "stage three initializes before defeat")
	await process_frame
	await process_frame

	var enemy: EnemyController = game.stage_manager.get_spawned_enemies()[0]
	var old_enemy_cell: Vector2i = enemy.grid_position
	var attack_cell: Vector2i = game.player.grid_position + Vector2i.RIGHT
	game.grid.clear_occupied(old_enemy_cell, enemy.enemy_id)
	game.grid.set_occupied(attack_cell, enemy.enemy_id)
	enemy.grid_position = attack_cell
	game.player.player_stats.current_hp = 1
	enemy.enemy_stats.attack = 1000
	game.combat_system.resolve_attack(enemy, game.player)
	await process_frame
	await process_frame

	_expect(game.stage_manager.stage_state.stage_number == 2, "defeat returns to the previous stage")
	_expect(not game.player.is_defeated(), "player is revived after defeat")
	_expect(game.player.player_stats.current_hp == game.player.player_stats.max_hp, "player HP is restored after defeat")
	_expect(game.turn_manager.is_player_turn(), "retry starts on the player turn")

	main.free()
	await process_frame
	if _failures.is_empty():
		print("Defeat retry smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	_quit_with_result()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)


func _quit_with_result() -> void:
	quit(0 if _failures.is_empty() else 1)
