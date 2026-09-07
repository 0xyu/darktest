extends "res://tools/ui_harness/ui_harness_suite.gd"

## Headless integration suite for the stage-exit gate: the hero must stand on
## the top Next Stage Point (3,0) before advancing, with a free-roam victory,
## an AUTO walk-to-exit, and FARMING position preservation.
##
## Mounts the real game scene (res://scenes/world/Main.tscn) and defeats the
## spawned enemies through EnemyController.handle_defeat (deterministic, no
## turn/attack math), then asserts the progression flow.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")
const TurnStateScript := preload("res://scripts/combat/turn_state.gd")

var _grid_test: Node


func suite_name() -> String:
	return "test_stage_exit_advance"


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_grid_test = instance.find_child("GridTest", true, false)
	# Let stage generation, turn start, and HUD refresh settle.
	await flush_frames(6)


func _player() -> Node:
	return _grid_test.find_child("Player", true, false)


func _stage() -> Node:
	return _grid_test.find_child("StageManager")


func _turn() -> Node:
	return _grid_test.find_child("TurnManager")


func _auto() -> Node:
	return _grid_test.find_child("AutoCombatController")


func _hud() -> Node:
	return _grid_test.find_child("MobileCombatHUD", true, false)


func _combat_actions() -> Node:
	return _hud().get("_combat_actions")


func _find_living_enemy() -> Node:
	var stage := _stage()
	for enemy in stage.call("get_spawned_enemies"):
		if enemy != null and is_instance_valid(enemy) and not bool(enemy.call("is_defeated")):
			return enemy
	return null


func _defeat_all_enemies() -> void:
	var guard := 0
	while guard < 80:
		var enemy := _find_living_enemy()
		if enemy == null:
			break
		enemy.call("handle_defeat")
		guard += 1
		await flush_frames(1)


func _place_player(cell: Vector2i) -> void:
	_player().call("place_at", cell)
	await flush_frames(1)


func _stage_number() -> int:
	var stage := _stage()
	var state: Resource = stage.call("get", "stage_state") as Resource
	return state.get("stage_number") as int if state != null else -1


func _phase() -> int:
	return int(_turn().call("get_phase"))


# --- Tests ---------------------------------------------------------------

func test_boot_places_player_at_start() -> void:
	await _mount_game()
	expect(_grid_test != null, "GridTest scene mounted")
	if _grid_test == null:
		return
	var stage := _stage()
	expect_eq(stage.call("get_stage_start_cell"), Vector2i(3, 10), "start cell is bottom x=3")
	expect_eq(stage.call("get_stage_exit_cell"), Vector2i(3, 0), "exit cell is top x=3")
	expect_eq(_player().call("get_grid_position"), Vector2i(3, 10), "hero spawns at stage start")
	expect_eq(_phase(), TurnStateScript.PLAYER_TURN, "stage 1 begins on the player turn")
	expect(not bool(_player().call("is_free_moving")), "free roam off during combat")


func test_manual_clear_gates_advance_on_exit() -> void:
	await _mount_game()
	await _defeat_all_enemies()
	expect_eq(_phase(), TurnStateScript.VICTORY, "clear reaches VICTORY")
	expect(bool(_player().call("is_free_moving")), "victory enables free roam")
	var actions := _combat_actions()
	var button: Button = actions.get_node("%NextStageButton") as Button
	expect(button != null, "NextStageButton exists")
	if button == null:
		return
	expect(bool(button.visible), "next-stage button revealed on victory")
	expect(bool(button.disabled), "next-stage disabled off the exit")

	# Walk onto the exit (3,0) and confirm the button enables.
	await _place_player(Vector2i(3, 1))
	_player().call("try_move", Vector2i.UP)
	await flush_frames(2)
	expect_eq(_player().call("get_grid_position"), Vector2i(3, 0), "hero stepped onto the exit")
	expect(not bool(button.disabled), "next-stage enabled while standing on the exit")

	# Press NEXT STAGE -> stage 2 starts, hero teleported back to the start.
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_stage_number(), 2, "advanced to stage 2")
	expect_eq(_player().call("get_grid_position"), Vector2i(3, 10), "stage 2 hero teleported to the start")
	expect_eq(_phase(), TurnStateScript.PLAYER_TURN, "stage 2 begins on the player turn")


func test_auto_walks_to_exit_when_enabled() -> void:
	await _mount_game()
	await _defeat_all_enemies()
	expect_eq(_phase(), TurnStateScript.VICTORY, "clear reaches VICTORY")
	# Place the hero one cell below the exit so the walk is short and certain.
	await _place_player(Vector2i(3, 1))
	_auto().call("set_game_speed", 2)  # FASTEST
	_auto().call("set_auto_enabled", true)
	# FASTEST action delay = 0.05s; headless frame delta ~1/60 => allow many frames.
	await flush_frames(120)
	# With AUTO on and farming off the ONLY path to stage 2 is the controller
	# walking the hero onto the exit cell first.
	expect_eq(_stage_number(), 2, "AUTO advanced to stage 2 after reaching the exit")
	expect(not bool(_player().call("is_free_moving")), "free roam reset once stage 2 combat begins")


func test_farming_respawn_keeps_position() -> void:
	await _mount_game()
	_auto().call("set_farming_enabled", true)
	await _place_player(Vector2i(5, 5))
	expect_eq(_player().call("get_grid_position"), Vector2i(5, 5), "hero positioned before the clear")
	await _defeat_all_enemies()
	await flush_frames(8)
	expect_eq(_stage_number(), 1, "farming stays on the same stage")
	expect_eq(_player().call("get_grid_position"), Vector2i(5, 5), "farming re-spawn keeps hero position")
	expect(not bool(_player().call("is_free_moving")), "farming does not enable free-roam victory")
