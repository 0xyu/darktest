extends SceneTree

var _failures: Array[String] = []
var _experience_award_count: int = 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var progression := PlayerProgression.new()
	_expect(progression.experience_to_next_level() == 100, "level one requires one hundred EXP")
	progression.add_experience(99)
	_expect(progression.level == 1 and progression.experience == 99, "EXP remains in the current level before the threshold")
	progression.add_experience(1)
	_expect(progression.level == 2 and progression.experience == 0, "reaching the threshold levels the player and carries no overflow")
	_expect(progression.experience_to_next_level() == 115, "level two EXP requirement follows the 1.15 growth formula")

	var grid := GridMap2D.new()
	grid.name = "Grid"
	grid.grid_size = Vector2i(6, 3)
	root.add_child(grid)

	var player := PlayerController.new()
	player.grid_path = NodePath("../Grid")
	player.grid_position = Vector2i(1, 1)
	player.player_progression = PlayerProgression.new()
	player.player_stats = PlayerStats.new()
	player.player_stats.max_hp = 100
	player.player_stats.current_hp = 80
	player.player_stats.attack = 100
	player.player_stats.defense = 5
	root.add_child(player)

	var enemy_definition := EnemyDefinition.new()
	enemy_definition.display_name = "Phase 12 Wraith"
	enemy_definition.enemy_type = EnemyType.NORMAL
	enemy_definition.base_stats = EnemyStats.new()
	enemy_definition.base_stats.max_hp = 10
	enemy_definition.base_stats.current_hp = 10
	enemy_definition.base_stats.experience_reward = 100
	enemy_definition.base_stats.level = 1

	var enemy := EnemyController.new()
	enemy.grid_path = NodePath("../Grid")
	enemy.grid_position = Vector2i(2, 1)
	enemy.enemy_level = 1
	enemy.enemy_definition = enemy_definition
	root.add_child(enemy)

	var combat := CombatSystem.new()
	root.add_child(combat)
	var experience_system := ExperienceSystem.new()
	root.add_child(experience_system)
	experience_system.attach_player(player)
	experience_system.attach_combat_system(combat)
	experience_system.experience_awarded.connect(_on_experience_awarded)
	await process_frame

	_expect(experience_system.calculate_enemy_experience(enemy) == 100, "normal enemy EXP uses base reward at level one")
	var elite_definition := enemy_definition.duplicate(true) as EnemyDefinition
	elite_definition.enemy_type = EnemyType.ELITE
	enemy.enemy_definition = elite_definition
	_expect(experience_system.calculate_enemy_experience(enemy) == 200, "elite enemies grant their configured EXP multiplier")
	enemy.enemy_definition = enemy_definition

	combat.resolve_attack(player, enemy)
	_expect(_experience_award_count == 1, "enemy defeat awards EXP through CombatSystem")
	_expect(player.player_progression.level == 2, "awarded EXP levels the player")
	_expect(player.player_progression.experience == 0, "level-up EXP overflow is retained correctly")
	_expect(player.player_stats.max_hp == 120, "level-up increases max HP")
	_expect(player.player_stats.current_hp == 80, "level-up preserves current HP while increasing max HP")
	_expect(player.player_stats.attack == 102, "level-up increases attack")
	_expect(player.player_stats.defense == 6, "level-up increases defense")

	var multi_level_player := PlayerController.new()
	multi_level_player.player_progression = PlayerProgression.new()
	multi_level_player.player_stats = PlayerStats.new()
	experience_system.attach_player(multi_level_player)
	var levels_gained: int = experience_system.grant_experience(215)
	_expect(levels_gained == 2, "large EXP awards can grant multiple levels")
	_expect(multi_level_player.player_progression.level == 3, "multiple level-ups advance the player repeatedly")
	_expect(multi_level_player.player_progression.experience == 0, "multiple level-ups consume each level requirement")
	_expect(multi_level_player.player_stats.max_hp == 140, "multiple level-ups apply stat growth for every level")
	multi_level_player.free()

	var exit_code: int = 0
	if _failures.is_empty():
		print("Phase 12 smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
		exit_code = 1
	for child in root.get_children():
		child.free()
	await process_frame
	quit(exit_code)


func _on_experience_awarded(_amount: int, _current_experience: int, _required_experience: int, _source_name: String) -> void:
	_experience_award_count += 1


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
