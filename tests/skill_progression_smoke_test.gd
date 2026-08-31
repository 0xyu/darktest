extends SceneTree

class MockActor:
	extends Node2D

	var player_stats: PlayerStats
	var player_progression: PlayerProgression
	var enemy_runtime: EnemyRuntime
	var enemy_stats: EnemyStats
	var player_id: StringName = &""
	var enemy_id: StringName = &""
	var grid_position: Vector2i

	func get_grid_position() -> Vector2i:
		return grid_position

	func clamp_current_hp() -> void:
		if enemy_stats != null:
			enemy_stats.clamp_current_hp()

	func handle_defeat() -> void:
		pass


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression := PlayerProgression.new()
	_expect(progression.get_skill_points() == 0, "new player starts with zero skill points")
	_expect(progression.add_experience(100) == 1, "one level-up is awarded")
	_expect(progression.level == 2 and progression.get_skill_points() == 1, "level-up grants one skill point")
	_expect(progression.upgrade_skill(SkillCatalog.WHIRLWIND), "one point learns whirlwind")
	_expect(progression.get_skill_level(SkillCatalog.WHIRLWIND) == 1 and progression.get_skill_points() == 0, "learning costs one point")
	_expect(not progression.upgrade_skill(SkillCatalog.WHIRLWIND), "upgrade requires another point")

	progression.skill_points = 4
	for _level in 4:
		_expect(progression.upgrade_skill(SkillCatalog.WHIRLWIND), "whirlwind can upgrade before level five")
	_expect(progression.get_skill_level(SkillCatalog.WHIRLWIND) == SkillDefinition.MAX_LEVEL, "skill reaches level five")
	_expect(not progression.upgrade_skill(SkillCatalog.WHIRLWIND), "skill cannot exceed level five")

	var player := MockActor.new()
	player.player_id = &"player"
	player.grid_position = Vector2i(3, 3)
	player.player_stats = PlayerStats.new()
	player.player_stats.attack = 100
	player.player_progression = progression
	var enemy := _make_enemy(&"adjacent", Vector2i(4, 3))
	root.add_child(player)
	root.add_child(enemy)
	var combat := CombatSystem.new()
	root.add_child(combat)
	combat.set_combat_targets([enemy])
	_expect(combat.can_use_skill(player, SkillCatalog.WHIRLWIND), "learned skill is available in combat")
	_expect(combat.resolve_skill(player, SkillCatalog.WHIRLWIND), "learned skill resolves in combat")
	_expect(enemy.enemy_stats.current_hp == 0, "level five whirlwind applies upgraded damage")

	var panel_scene := load("res://scenes/ui/SkillPanel.tscn") as PackedScene
	var skill_panel := panel_scene.instantiate() as SkillPanel
	root.add_child(skill_panel)
	var ui_player := PlayerController.new()
	ui_player.player_progression = progression
	skill_panel.set_player(ui_player)
	skill_panel.show_panel()
	await process_frame
	_expect(skill_panel.visible, "skill panel opens")
	_expect(skill_panel.get_node("Panel/Margin/Content/SkillList").get_child_count() == 3, "skill panel lists all three skills")
	skill_panel.free()
	ui_player.free()
	combat.free()
	player.free()
	enemy.free()

	if _failures.is_empty():
		print("Skill progression smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _make_enemy(enemy_id: StringName, cell: Vector2i) -> MockActor:
	var enemy := MockActor.new()
	enemy.enemy_id = enemy_id
	enemy.grid_position = cell
	enemy.enemy_stats = EnemyStats.new()
	enemy.enemy_stats.max_hp = 100
	enemy.enemy_stats.current_hp = 100
	enemy.enemy_stats.defense = 10
	return enemy


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
