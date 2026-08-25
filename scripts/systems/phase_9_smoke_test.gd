extends SceneTree

const EnemyScalingSystem = preload("res://scripts/systems/enemy_scaling.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var grid := GridMap2D.new()
	grid.name = "Grid"
	grid.grid_size = Vector2i(12, 8)
	root.add_child(grid)

	var player := PlayerController.new()
	player.grid_path = NodePath("../Grid")
	player.grid_position = Vector2i(1, 1)
	root.add_child(player)

	var manager := StageManager.new()
	manager.grid_path = NodePath("../Grid")
	manager.spawn_parent_path = NodePath("..")
	manager.enemy_scene = preload("res://scenes/enemies/Enemy.tscn")
	manager.random_seed = 97531
	root.add_child(manager)
	await process_frame

	_expect(manager.initialize_stage(1), "stage one initializes")
	var stage_one_enemy: EnemyController = manager.get_spawned_enemies()[0]
	var stage_one_stats: EnemyStats = stage_one_enemy.enemy_stats
	_expect(stage_one_stats.max_hp == 60, "stage one HP matches the base value")
	_expect(stage_one_stats.attack == 8, "stage one attack matches the base value")
	_expect(stage_one_stats.defense == 2, "stage one defense matches the base value")
	_expect(stage_one_stats.gold_reward == 10, "stage one gold matches the base value")

	_expect(manager.initialize_stage(20), "stage twenty initializes")
	var stage_twenty_enemy: EnemyController = manager.get_spawned_enemies()[0]
	var stage_twenty_stats: EnemyStats = stage_twenty_enemy.enemy_stats
	var stage_twenty_base_stats: EnemyStats = manager.current_definition.mini_boss_definition.base_stats
	var expected_hp: int = EnemyScalingSystem.scale_value(stage_twenty_base_stats.max_hp, 1.20, 20)
	var expected_attack: int = EnemyScalingSystem.scale_value(stage_twenty_base_stats.attack, 1.16, 20)
	var expected_defense: int = EnemyScalingSystem.scale_value(stage_twenty_base_stats.defense, 1.15, 20)
	var expected_gold: int = EnemyScalingSystem.scale_value(stage_twenty_base_stats.gold_reward, 1.18, 20)
	_expect(stage_twenty_stats.max_hp == expected_hp, "stage twenty HP follows exponential scaling")
	_expect(stage_twenty_stats.attack == expected_attack, "stage twenty attack follows exponential scaling")
	_expect(stage_twenty_stats.defense == expected_defense, "stage twenty defense follows exponential scaling")
	_expect(stage_twenty_stats.gold_reward == expected_gold, "stage twenty gold follows exponential scaling")
	_expect(stage_twenty_stats.max_hp > stage_one_stats.max_hp, "stage twenty is harder than stage one")
	_expect(stage_twenty_stats.attack > stage_one_stats.attack, "stage twenty attack is higher than stage one")
	_expect(stage_twenty_stats.defense > stage_one_stats.defense, "stage twenty defense is higher than stage one")
	_expect(stage_twenty_stats.gold_reward > stage_one_stats.gold_reward, "stage twenty gold reward is higher than stage one")

	manager.hp_growth_rate = 1.0
	manager.attack_growth_rate = 1.0
	manager.defense_growth_rate = 1.0
	manager.gold_growth_rate = 1.0
	_expect(manager.initialize_stage(2), "stage two initializes with custom growth rates")
	var custom_stats: EnemyStats = manager.get_spawned_enemies()[0].enemy_stats
	_expect(custom_stats.max_hp == 60, "HP growth rate is tunable")
	_expect(custom_stats.attack == 8, "attack growth rate is tunable")
	_expect(custom_stats.defense == 2, "defense growth rate is tunable")
	_expect(custom_stats.gold_reward == 10, "gold growth rate is tunable")

	if _failures.is_empty():
		print("Phase 9 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
