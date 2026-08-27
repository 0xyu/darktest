extends SceneTree

var _failures: Array[String] = []
var _area_attack_count: int = 0
var _summon_count: int = 0
var _enrage_count: int = 0
var _normal_attack_count: int = 0


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

	var stage_manager := StageManager.new()
	stage_manager.grid_path = NodePath("../Grid")
	stage_manager.spawn_parent_path = NodePath("..")
	stage_manager.enemy_scene = preload("res://scenes/enemies/Enemy.tscn")
	stage_manager.random_seed = 86420
	root.add_child(stage_manager)
	await process_frame

	stage_manager.mini_boss_definitions.append(preload("res://resources/enemies/AshenOracle.tres") as MiniBossDefinition)
	_expect(stage_manager.initialize_stage(10), "stage ten initializes")
	_expect(stage_manager.is_mini_boss_stage(10), "every tenth stage is a Mini Boss stage")
	_expect(stage_manager.stage_state.is_mini_boss_stage, "stage state identifies the Mini Boss encounter")
	_expect(stage_manager.stage_state.spawned_enemy_count == 1, "Mini Boss stage starts with one boss")

	var boss: EnemyController = stage_manager.get_spawned_enemies()[0]
	_expect(boss.is_mini_boss, "stage ten enemy is marked as a Mini Boss")
	_expect(boss.boss_identifier == &"ashen_oracle", "Mini Boss has a stable identifier")
	_expect(boss.get_display_name() == "Ashen Oracle", "Mini Boss has a display name")
	_expect(boss.enemy_stats.max_hp > 60, "Mini Boss uses stronger base stats")

	_area_attack_count = 0
	boss.area_attack_requested.connect(_on_area_attack_requested)
	_set_boss_adjacent_to_player(grid, boss)
	var turn_manager := TurnManager.new()
	root.add_child(turn_manager)
	turn_manager.start_combat(player, [boss])
	turn_manager.complete_player_turn()
	_expect(_area_attack_count == 1, "AOE boss uses its area attack when in range")
	_expect(turn_manager.is_player_turn(), "AOE boss completes its enemy turn")

	stage_manager.mini_boss_definitions.clear()
	stage_manager.mini_boss_definitions.append(preload("res://resources/enemies/Gravecaller.tres") as MiniBossDefinition)
	_expect(stage_manager.initialize_stage(10), "summoner Mini Boss stage initializes")
	var summoner: EnemyController = stage_manager.get_spawned_enemies()[0]
	_summon_count = 0
	stage_manager.enemy_spawned.connect(_on_enemy_spawned)
	_set_boss_adjacent_to_player(grid, summoner)
	turn_manager.start_combat(player, [summoner])
	turn_manager.complete_player_turn()
	_expect(_summon_count == 1, "summoner boss creates a minion")
	_expect(stage_manager.stage_state.spawned_enemy_count == 2, "summoned minion is tracked by the stage")

	stage_manager.mini_boss_definitions.clear()
	stage_manager.mini_boss_definitions.append(preload("res://resources/enemies/BloodboundWarlord.tres") as MiniBossDefinition)
	_expect(stage_manager.initialize_stage(10), "enrager Mini Boss stage initializes")
	var enrager: EnemyController = stage_manager.get_spawned_enemies()[0]
	_enrage_count = 0
	_normal_attack_count = 0
	enrager.enraged.connect(_on_enraged)
	enrager.attack_requested.connect(_on_normal_attack_requested)
	enrager.enemy_stats.current_hp = floori(float(enrager.enemy_stats.max_hp) * 0.5)
	var attack_before_enrage: int = enrager.enemy_stats.attack
	_set_boss_adjacent_to_player(grid, enrager)
	turn_manager.start_combat(player, [enrager])
	turn_manager.complete_player_turn()
	_expect(_enrage_count == 1, "enrager signals its enrage")
	_expect(enrager.enemy_stats.attack > attack_before_enrage, "enrager increases attack below its threshold")
	_expect(_normal_attack_count == 1, "enrager still takes its normal attack action")

	if _failures.is_empty():
		print("Phase 10 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _set_boss_adjacent_to_player(grid: GridMap2D, boss: EnemyController) -> void:
	grid.clear_occupied(boss.grid_position, boss.enemy_id)
	boss.grid_position = Vector2i(2, 1)
	grid.set_occupied(boss.grid_position, boss.enemy_id)
	boss.global_position = grid.grid_to_world(boss.grid_position)


func _on_area_attack_requested(_boss: EnemyController, _target: Node, _attack_range: int, _damage_multiplier: float) -> void:
	_area_attack_count += 1


func _on_enemy_spawned(_enemy: Node) -> void:
	_summon_count += 1


func _on_enraged(_boss: EnemyController) -> void:
	_enrage_count += 1


func _on_normal_attack_requested(_boss: EnemyController, _target: Node) -> void:
	_normal_attack_count += 1


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
