extends SceneTree

const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")

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
	manager.random_seed = 112233
	root.add_child(manager)
	await process_frame

	_expect(is_equal_approx(manager.get_special_encounter_chance(), 0.03), "special encounter chance starts at three percent")
	_expect(is_equal_approx(manager.special_chance_increment, 0.01), "special encounter pity increment is one percent")
	_expect(is_equal_approx(manager.max_special_encounter_chance, 0.15), "special encounter chance caps at fifteen percent")

	manager.special_encounter_chance = 0.0
	for _index in range(30):
		manager.record_special_encounter_result(false)
	_expect(is_equal_approx(manager.get_special_encounter_chance(), 0.15), "failed rolls stop at the pity cap")

	manager.record_special_encounter_result(true)
	_expect(is_equal_approx(manager.get_special_encounter_chance(), 0.03), "successful encounter result resets the chance")
	manager.max_special_encounter_chance = 1.0
	manager.special_encounter_chance = 1.0
	var successful_type: int = manager.roll_special_encounter(3)
	_expect(successful_type != SpecialEncounterTypeResource.NONE, "a successful roll creates a special encounter")
	_expect(is_equal_approx(manager.get_special_encounter_chance(), manager.base_special_encounter_chance), "successful roll resets the chance")
	_expect(successful_type >= SpecialEncounterTypeResource.ELITE and successful_type <= SpecialEncounterTypeResource.CURSED_MONSTER, "successful roll uses a supported encounter type")

	manager.special_encounter_chance = 0.11
	_expect(manager.roll_special_encounter(10) == SpecialEncounterTypeResource.NONE, "guaranteed Mini Boss stages skip random special encounters")
	_expect(is_equal_approx(manager.get_special_encounter_chance(), 0.11), "guaranteed Mini Boss stages do not consume pity")

	for _index in range(100):
		var random_boss_level: int = manager.roll_random_mini_boss_level(100)
		_expect(random_boss_level >= 1 and random_boss_level <= 100, "random Mini Boss level stays within the unlocked range")

	_expect(manager.initialize_stage(3, SpecialEncounterTypeResource.ELITE), "elite special encounter initializes")
	_expect(manager.stage_state.is_special_encounter, "stage state marks an elite encounter")
	_expect(manager.stage_state.special_encounter_type == SpecialEncounterTypeResource.ELITE, "stage state records the encounter type")
	var elite: EnemyController = manager.get_spawned_enemies()[0]
	_expect(elite.enemy_definition.enemy_type == EnemyType.ELITE, "elite encounter changes the enemy type")
	_expect(elite.get_display_name().begins_with("Elite "), "elite encounter gets a readable name")

	_expect(manager.initialize_stage(3, SpecialEncounterTypeResource.RANDOM_MINI_BOSS), "random Mini Boss encounter initializes")
	_expect(manager.stage_state.is_special_encounter, "random Mini Boss is a special encounter")
	_expect(manager.stage_state.special_encounter_type == SpecialEncounterTypeResource.RANDOM_MINI_BOSS, "random Mini Boss type is recorded")
	var random_boss: EnemyController = manager.get_spawned_enemies()[0]
	_expect(random_boss.is_mini_boss, "random Mini Boss uses a Mini Boss definition")
	_expect(manager.stage_state.special_mini_boss_level >= 1 and manager.stage_state.special_mini_boss_level <= 3, "random Mini Boss level is valid for the current stage")
	_expect(random_boss.enemy_level == manager.stage_state.special_mini_boss_level, "random Mini Boss receives its rolled level")

	if _failures.is_empty():
		print("Phase 11 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
