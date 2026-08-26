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

	var game := main.get_node("GridTest") as GridTest
	var auto_combat := game.get_node("AutoCombatController") as AutoCombatController
	_expect(auto_combat != null, "combat scene contains an auto controller")
	if auto_combat == null:
		_quit_with_result()
		return

	game.player.player_stats.current_hp = 30
	var starting_potions: int = game.player.get_healing_item_count()
	var starting_stage: int = game.stage_manager.stage_state.stage_number
	auto_combat.set_auto_enabled(true)

	for _frame in range(180):
		await process_frame
		if game.stage_manager.stage_state.stage_number > starting_stage:
			break

	_expect(auto_combat.is_auto_enabled(), "auto mode remains enabled after a successful stage")
	_expect(game.stage_manager.stage_state.stage_number > starting_stage, "auto mode continues to the next stage")
	_expect(game.player.get_healing_item_count() < starting_potions, "auto mode uses a healing item when health is low")
	_expect(game.turn_manager.get_phase() == TurnState.PLAYER_TURN, "auto mode does not leave the new stage stalled")

	auto_combat.stop_auto()
	_expect(not auto_combat.is_auto_enabled(), "auto mode can be disabled")

	game.player.healing_item_count = 1
	game.player.player_stats.current_hp = 10
	var healed: bool = game.player.use_healing_item()
	_expect(healed and game.player.player_stats.current_hp > 10, "healing item restores player HP")
	_expect(game.player.get_healing_item_count() == 0, "healing item is consumed")

	if _failures.is_empty():
		print("Phase 20 smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)

	main.free()
	await process_frame
	_quit_with_result()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)


func _quit_with_result() -> void:
	quit(0 if _failures.is_empty() else 1)
