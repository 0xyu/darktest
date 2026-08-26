extends SceneTree

const GoldSystemResource = preload("res://scripts/systems/gold_system.gd")

var _failures: Array[String] = []
var _gold_award_count: int = 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var progression := PlayerProgression.new()
	_expect(progression.add_gold(25) == 25, "gold storage accepts a positive reward")
	_expect(progression.gold == 25, "gold is stored on PlayerProgression")
	_expect(progression.add_gold(-10) == 0 and progression.gold == 25, "negative gold rewards are ignored")

	var grid := GridMap2D.new()
	grid.name = "Grid"
	grid.grid_size = Vector2i(6, 3)
	root.add_child(grid)

	var player := PlayerController.new()
	player.grid_path = NodePath("../Grid")
	player.grid_position = Vector2i(1, 1)
	player.player_progression = PlayerProgression.new()
	player.player_stats = PlayerStats.new()
	player.player_stats.attack = 100
	root.add_child(player)

	var enemy_definition := EnemyDefinition.new()
	enemy_definition.display_name = "Phase 13 Wraith"
	enemy_definition.enemy_type = EnemyType.NORMAL
	enemy_definition.base_stats = EnemyStats.new()
	enemy_definition.base_stats.max_hp = 10
	enemy_definition.base_stats.current_hp = 10
	enemy_definition.base_stats.gold_reward = 10

	var enemy := EnemyController.new()
	enemy.grid_path = NodePath("../Grid")
	enemy.grid_position = Vector2i(2, 1)
	enemy.enemy_definition = enemy_definition
	root.add_child(enemy)

	var combat := CombatSystem.new()
	root.add_child(combat)
	var stage_manager := StageManager.new()
	root.add_child(stage_manager)
	var gold_system = GoldSystemResource.new()
	root.add_child(gold_system)
	gold_system.attach_player(player)
	gold_system.attach_combat_system(combat)
	gold_system.attach_stage_manager(stage_manager)
	gold_system.gold_awarded.connect(_on_gold_awarded)
	await process_frame

	_expect(gold_system.calculate_enemy_gold(enemy) == 10, "normal enemy gold uses its scaled reward")
	enemy.enemy_definition.enemy_type = EnemyType.MINI_BOSS
	_expect(gold_system.calculate_enemy_gold(enemy) == 40, "Mini Boss gold uses the boss reward multiplier")
	enemy.enemy_definition.enemy_type = EnemyType.NORMAL
	_expect(gold_system.calculate_stage_gold(1) == 50, "stage one reward uses the configured base Gold")
	_expect(gold_system.calculate_stage_gold(20) == EnemyScaling.scale_value(50, 1.18, 20), "stage rewards follow the 1.18 growth formula")

	combat.resolve_attack(player, enemy)
	_expect(player.player_progression.gold == 10, "defeating an enemy awards Gold through CombatSystem")
	_expect(_gold_award_count == 1, "enemy defeat emits one Gold reward")

	stage_manager.stage_completed.emit(stage_manager.stage_state)
	_expect(player.player_progression.gold == 60, "stage completion awards the stage Gold reward")
	_expect(_gold_award_count == 2, "stage completion emits one additional Gold reward")

	var exit_code: int = 0
	if _failures.is_empty():
		print("Phase 13 smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
		exit_code = 1
	for child in root.get_children():
		child.free()
	await process_frame
	quit(exit_code)


func _on_gold_awarded(_amount: int, _current_gold: int, _source_name: String) -> void:
	_gold_award_count += 1


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
