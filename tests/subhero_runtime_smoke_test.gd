extends SceneTree

const GameScene = preload("res://scenes/world/grid_combat.tscn")
const InstanceScript = preload("res://scripts/sub_hero/sub_hero_instance.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame

	var player: PlayerController = game.get_node("Player")
	var manager: SubHeroCombatManager = game.get_node("SubHeroCombatManager")
	player.add_sub_hero(InstanceScript.new(&"skeleton_archer", 1))
	_expect(player.assign_sub_hero_slot(0, &"skeleton_archer"), "Sub Hero should assign to the active combat slot")
	await process_frame

	var stage_manager: StageManager = game.get_node("StageManager")
	var enemies: Array[EnemyController] = stage_manager.get_spawned_enemies()
	_expect(manager.is_combat_running(), "Sub Hero combat should be running after stage start")
	_expect(not enemies.is_empty(), "stage should have a live enemy")
	if not enemies.is_empty():
		var enemy := enemies[0]
		var hp_before: int = enemy.get_current_hp()
		await create_timer(1.95).timeout
		_expect(enemy.get_current_hp() < hp_before, "Sub Hero should damage an enemy without player input")
		if manager.is_combat_running():
			enemy.set_current_hp(1)
			manager._process(1.8)
			_expect(not manager.is_combat_running(), "Sub Hero combat should stop when the final enemy dies")
			_expect(game.get_node("TurnManager").get_phase() == TurnState.VICTORY, "final Sub Hero kill should settle the stage immediately")

	game.queue_free()
	if _failures.is_empty():
		print("Sub Hero runtime smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
