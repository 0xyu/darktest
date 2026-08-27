extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var grid := GridMap2D.new()
	grid.name = "Grid"
	grid.grid_size = Vector2i(6, 2)
	root.add_child(grid)

	var data := EnemyData.new()
	data.id = &"shared_wraith"
	data.name = "Shared Wraith"
	data.base_stats = EnemyStats.new()
	data.base_stats.max_hp = 100
	data.base_stats.current_hp = 100

	var enemies: Array[EnemyController] = []
	for index in range(3):
		var enemy := EnemyController.new()
		enemy.enemy_id = StringName("enemy_%d" % (index + 1))
		enemy.enemy_data = data
		enemy.grid_path = NodePath("../Grid")
		enemy.grid_position = Vector2i(index + 1, 0)
		root.add_child(enemy)
		enemies.append(enemy)

	await process_frame
	_expect(enemies[0].enemy_data == data, "Enemy A references the shared EnemyData")
	_expect(enemies[1].enemy_data == data, "Enemy B references the shared EnemyData")
	_expect(enemies[2].enemy_data == data, "Enemy C references the shared EnemyData")
	_expect(enemies[0].enemy_runtime != enemies[1].enemy_runtime, "Enemy A and B have separate runtime state")
	_expect(enemies[1].enemy_runtime != enemies[2].enemy_runtime, "Enemy B and C have separate runtime state")
	_expect(enemies[0].enemy_runtime.current_stats != data.base_stats, "runtime stats do not alias EnemyData.base_stats")

	enemies[0].set_current_hp(25)
	_expect(enemies[0].get_current_hp() == 25, "Enemy A HP changes")
	_expect(enemies[1].get_current_hp() == 100, "Enemy B HP remains independent")
	_expect(enemies[2].get_current_hp() == 100, "Enemy C HP remains independent")
	_expect(data.base_stats.current_hp == 100, "shared EnemyData base stats remain unchanged")

	for enemy in enemies:
		enemy.free()
	grid.free()
	await process_frame
	if _failures.is_empty():
		print("Phase 1 EnemyData/EnemyRuntime smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
