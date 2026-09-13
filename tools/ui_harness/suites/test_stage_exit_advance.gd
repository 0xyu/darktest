extends "res://tools/ui_harness/ui_harness_suite.gd"

## Headless integration suite for the stage-exit gate: the hero must stand on
## the right Next Stage Point (12,3) before advancing, with a free-roam victory,
## an AUTO walk-to-exit, and FARMING position preservation.
##
## It also covers the arena gate lane (the Starting Cell (0,3) and the Next Stage
## Point (12,3) are the only usable cells of the two outer columns, and a new
## stage starts one cell inward from the gate it was entered through), the walk
## BACK into the previous stage through the Starting Cell, and the replay rule: a
## stage the player walked back into may be left through the same exit cell WHILE
## ITS ENEMIES ARE STILL STANDING, because the stage after it has already been
## cleared (the fight is simply abandoned, and the skipped stage is recorded as
## cleared by a real clear only).
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
	_grid_test = instance.find_child("grid_combat", true, false)
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


func _combat() -> Node:
	return _grid_test.find_child("CombatSystem", true, false)


func _presentation() -> Node:
	return _grid_test.find_child("CombatPresentation", true, false)


func _living_enemies() -> Array:
	var living: Array = []
	for enemy in _stage().call("get_spawned_enemies"):
		if enemy != null and is_instance_valid(enemy) and not bool(enemy.call("is_defeated")):
			living.append(enemy)
	return living


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


## Puts the hero on the exit cell WHILE the fight is still running, and reports
## whether that worked.
##
## An enemy may legitimately occupy the exit cell (spawn cells are random), so a
## blocker is defeated first — one cell can hold at most one enemy, and a stage
## with two spawned enemies can therefore never lose its whole fight to this.
func _stand_on_exit_while_fighting() -> bool:
	var exit_cell: Vector2i = _stage().call("get_stage_exit_cell")
	if bool(_player().call("place_at", exit_cell)):
		await flush_frames(1)
		return true
	for enemy in _stage().call("get_spawned_enemies"):
		if enemy == null or not is_instance_valid(enemy) or bool(enemy.call("is_defeated")):
			continue
		if enemy.get("grid_position") == exit_cell:
			enemy.call("handle_defeat")
			await flush_frames(2)
	var placed: bool = bool(_player().call("place_at", exit_cell))
	await flush_frames(1)
	return placed


## Opens an authored stage directly (the DEV / harness entry, which intentionally
## bypasses the map's lock gate).
func _enter_typed_stage(stage_number: int) -> void:
	_grid_test.call("enter_area_stage", stage_number)
	await flush_frames(3)


## Marks stages as already played. Recording a completion directly on
## PlayerProgress is the sanctioned shortcut for "the player has been here
## before" — no turn/attack math is involved, and it is what makes the replay
## case deterministically reachable.
func _mark_cleared(stage_numbers: Array) -> void:
	var progress: Resource = _progress()
	for number in stage_numbers:
		progress.call("complete_stage", number)


func _progress() -> Resource:
	return _grid_test.call("get_stage_progress") as Resource


func _stage_is_complete() -> bool:
	var state: Resource = _stage().call("get", "stage_state") as Resource
	return state != null and bool(state.get("is_complete"))


func _next_stage_button() -> Button:
	return _combat_actions().get_node("%NextStageButton") as Button


func _status_text() -> String:
	return str(_grid_test.get("_last_move_text"))


func _stage_number() -> int:
	var stage := _stage()
	var state: Resource = stage.call("get", "stage_state") as Resource
	return state.get("stage_number") as int if state != null else -1


func _phase() -> int:
	return int(_turn().call("get_phase"))


# --- Tests ---------------------------------------------------------------

func test_boot_places_player_at_start() -> void:
	await _mount_game()
	expect(_grid_test != null, "grid_combat scene mounted")
	if _grid_test == null:
		return
	var stage := _stage()
	expect_eq(stage.call("get_stage_start_cell"), Vector2i(0, 3), "Starting Cell is the extra left cell of row 4")
	expect_eq(stage.call("get_stage_exit_cell"), Vector2i(12, 3), "Next Stage Cell is the extra right cell of row 4")
	expect_eq(_player().call("get_grid_position"), Vector2i(1, 3), "hero spawns one cell right of the Starting Cell")
	expect_eq(_phase(), TurnStateScript.PLAYER_TURN, "stage 1 begins on the player turn")
	expect(not bool(_player().call("is_free_moving")), "free roam off during combat")


## Rule: only row 4 carries the two extra cells. The outer columns are usable
## there and unusable on every other row, so the gate cells exist without
## widening rows 1-3 / 5-7.
func test_the_gate_lane_is_the_only_row_using_the_outer_columns() -> void:
	await _mount_game()
	var grid: Node = _grid_test.find_child("Grid", true, false)
	expect(grid != null, "the arena grid exists")
	if grid == null:
		return
	expect(bool(grid.call("is_walkable", Vector2i(0, 3))), "the Starting Cell is walkable")
	expect(bool(grid.call("is_walkable", Vector2i(12, 3))), "the Next Stage Cell is walkable")
	for row in [0, 1, 2, 4, 5, 6]:
		expect(
			not bool(grid.call("is_walkable", Vector2i(0, row))),
			"the left gate column is unusable on row %d" % (row + 1)
		)
		expect(
			not bool(grid.call("is_walkable", Vector2i(12, row))),
			"the right gate column is unusable on row %d" % (row + 1)
		)
	expect(not bool(grid.call("is_occupied", Vector2i(0, 3))), "the Starting Cell starts free")


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

	# Walk onto the Next Stage Cell (12,3) and confirm the button enables.
	await _place_player(Vector2i(11, 3))
	_player().call("try_move", Vector2i.RIGHT)
	await flush_frames(2)
	expect_eq(_player().call("get_grid_position"), Vector2i(12, 3), "hero stepped onto the exit")
	expect_contains(_status_text(), "ON THE EXIT — NEXT STAGE READY", "reaching the exit is reported")
	expect(not bool(button.disabled), "next-stage enabled while standing on the exit")

	# Press NEXT STAGE -> stage 2 starts, the hero arrives beyond the start gate.
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_stage_number(), 2, "advanced to stage 2")
	expect_eq(_player().call("get_grid_position"), Vector2i(1, 3), "stage 2 hero enters right of the Starting Cell")
	expect_eq(_phase(), TurnStateScript.PLAYER_TURN, "stage 2 begins on the player turn")


## Rule: the Starting Cell is the gate BACK into the previous stage. Stepping onto
## it moves the battle one stage back, and the backward arrival is one cell to the
## left of that stage's Next Stage Cell — the mirror of the forward arrival.
func test_stepping_on_the_starting_cell_returns_to_the_previous_stage() -> void:
	await _mount_game()
	await _defeat_all_enemies()
	expect(await _stand_on_exit_while_fighting(), "the hero stands on the exit after the clear")
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_stage_number(), 2, "the battle advanced to stage 2")
	expect_eq(_player().call("get_grid_position"), Vector2i(1, 3), "stage 2 starts right of the Starting Cell")

	# One step left IS the Starting Cell, so this move must move the battle back.
	_player().call("try_move", Vector2i.LEFT)
	await flush_frames(6)
	expect_eq(_stage_number(), 1, "stepping onto the Starting Cell returned to the previous stage")
	expect_eq(_player().call("get_grid_position"), Vector2i(11, 3), "the walk back arrives one left of the Next Stage Cell")
	expect_eq(_phase(), TurnStateScript.PLAYER_TURN, "the previous stage begins on the player turn")
	expect_contains(_status_text(), "BACK THROUGH THE STARTING POINT", "the walk back is reported")
	expect(_find_living_enemy() != null, "the previous stage is a real fight again")


## The mirror of the forward gate on stage 1: there is nothing behind the first
## stage, so the Starting Cell is only a cell there.
func test_the_starting_cell_leads_nowhere_on_stage_1() -> void:
	await _mount_game()
	expect_eq(_stage_number(), 1, "the boot stage is stage 1")
	expect(not bool(_grid_test.call("can_return_to_previous_stage")), "stage 1 has no previous stage")
	_player().call("try_move", Vector2i.LEFT)
	await flush_frames(4)
	expect_eq(_stage_number(), 1, "stepping onto the Starting Cell kept the battle on stage 1")
	expect_eq(_player().call("get_grid_position"), Vector2i(0, 3), "the hero is standing on the Starting Cell")


func test_auto_walks_to_exit_when_enabled() -> void:
	await _mount_game()
	await _defeat_all_enemies()
	expect_eq(_phase(), TurnStateScript.VICTORY, "clear reaches VICTORY")
	# Place the hero one cell left of the exit so the walk is short and certain.
	await _place_player(Vector2i(11, 3))
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


## Regression: a FARMING re-spawn must not rebuild the wave while the LAST enemy's
## final blow is still on screen. The clear is decided the moment its HP reaches
## zero, so a re-spawn triggered from the clear alone frees that enemy before its
## damage number spawns and before its death animation runs — it then simply
## disappears instead of dying.
func test_farming_respawn_waits_for_the_final_blow() -> void:
	await _mount_game()
	_auto().call("set_farming_enabled", true)
	# Leave exactly one enemy standing. The extras die through handle_defeat, which
	# runs no presentation, so the final blow below is the only sequence on screen.
	var guard := 0
	while guard < 80:
		var standing: Array = _living_enemies()
		if standing.size() <= 1:
			break
		standing[0].call("handle_defeat")
		guard += 1
		await flush_frames(1)
	var last: Node = _find_living_enemy()
	expect(last != null, "a last enemy is standing before the final blow")
	if last == null:
		return
	var token: Node = last.get_node_or_null(^"CharacterToken")
	expect(token != null, "the last enemy owns a presentation token")
	var number_layer: Node = _presentation().find_child("NumberLayer", false, false)

	# A real attack through the combat system, so the presentation sequence runs.
	_combat().call("resolve_attack", _player(), last, 9999.0, 99)
	expect(bool(last.call("is_defeated")), "the final blow defeats the last enemy")
	expect(_stage_is_complete(), "the clear is recorded as soon as the enemy dies")

	# The sequence must actually play while the wave is still the old one ...
	var saw_number := false
	var saw_death := false
	for _i in 60:
		if number_layer != null and is_instance_valid(number_layer) and number_layer.get_child_count() > 0:
			saw_number = true
		if token != null and is_instance_valid(token) and bool(token.call("is_dying")):
			saw_death = true
		if saw_number and saw_death:
			break
		await flush_frames(1)
	expect(saw_number, "the final blow shows its damage number")
	expect(saw_death, "the last enemy plays its death animation")

	# ... and only then is the stage re-spawned.
	for _i in 120:
		if _find_living_enemy() != null:
			break
		await flush_frames(1)
	expect(_find_living_enemy() != null, "the wave re-spawns once the final blow finished")
	expect_eq(_stage_number(), 1, "farming re-spawned the same stage")


# --- The replay rule ------------------------------------------------------
# A stage the player has already walked through stays enterable. When the stage
# AFTER the one being replayed is itself already cleared, the exit does not owe
# the player a second clear: the fight may be abandoned by walking out of it.

func test_replay_skips_the_fight_when_the_next_stage_is_cleared() -> void:
	await _mount_game()
	# The player already played 1-3, so stage 3 is done and replaying stage 2 is
	# a walk back through ground that is already cleared.
	_mark_cleared([1, 2, 3])
	await _enter_typed_stage(2)

	expect_eq(_stage_number(), 2, "the replay stage is the one that was entered")
	expect_eq(_phase(), TurnStateScript.PLAYER_TURN, "a replay still starts a real fight")
	expect(not _stage_is_complete(), "nothing is cleared yet on the replay")
	expect(_find_living_enemy() != null, "the replay starts with enemies standing")
	expect_contains(_status_text(), "STAGE 03 ALREADY CLEARED", "starting a replay announces the open exit")

	var button: Button = _next_stage_button()
	expect(button != null, "NextStageButton exists")
	if button == null:
		return

	expect(await _stand_on_exit_while_fighting(), "the hero can stand on the exit cell mid-fight")
	expect_eq(_phase(), TurnStateScript.PLAYER_TURN, "the exit was reached during the player's own turn")
	expect(_find_living_enemy() != null, "enemies are still standing when the exit opens")
	expect(not _stage_is_complete(), "the exit is open without a clear")
	expect(bool(_grid_test.call("can_leave_stage_uncleared")), "the replay skip is available on the exit")
	expect(bool(button.visible) and not bool(button.disabled), "NEXT STAGE is offered mid-fight on a replay")

	# Pressing it abandons the fight and moves the battle on.
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_stage_number(), 3, "the replay skip advanced to the already-cleared stage 3")
	expect_eq(int(_progress().get("current_stage_number")), 3, "the position followed the skip")
	expect_eq(_player().call("get_grid_position"), Vector2i(1, 3), "the new stage enters right of the Starting Cell")
	expect_eq(_phase(), TurnStateScript.PLAYER_TURN, "the new stage begins on the player turn")


func test_the_clear_is_still_required_when_the_next_stage_is_not_cleared() -> void:
	await _mount_game()
	# 1-2 played, 3 not: the stage stands on ground that is done, but the way
	# FORWARD is not, so the enemies still decide when the exit opens.
	_mark_cleared([1, 2])
	await _enter_typed_stage(2)
	expect(_find_living_enemy() != null, "the stage starts with enemies standing")

	var button: Button = _next_stage_button()
	expect(button != null, "NextStageButton exists")
	if button == null:
		return

	expect(await _stand_on_exit_while_fighting(), "the hero can stand on the exit cell mid-fight")
	expect_eq(_phase(), TurnStateScript.PLAYER_TURN, "still the player's own turn")
	expect(not _stage_is_complete(), "the stage is not cleared")
	expect(not bool(_grid_test.call("can_leave_stage_uncleared")), "no skip: the next stage is not cleared")
	expect(not bool(button.visible), "NEXT STAGE is not offered mid-fight here")

	_hud().emit_signal("next_stage_requested")
	await flush_frames(4)
	expect_eq(_stage_number(), 2, "pressing NEXT STAGE mid-fight changes nothing")

	# The classic rule still opens the exit, on the same cell, after a clear.
	await _defeat_all_enemies()
	expect(_stage_is_complete(), "defeating every enemy clears the stage")
	expect_eq(_phase(), TurnStateScript.VICTORY, "the clear reaches VICTORY")
	expect(bool(button.visible) and not bool(button.disabled), "the exit is offered after the clear while standing on it")
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_stage_number(), 3, "the classic clear-then-exit advance still works")


func test_farming_blocks_the_replay_skip() -> void:
	# FARMING means "stay on this stage", so it is not a way around the replay
	# rule: the exit stays shut until FARMING is switched off.
	await _mount_game()
	_mark_cleared([1, 2, 3])
	await _enter_typed_stage(2)
	_auto().call("set_farming_enabled", true)

	expect(await _stand_on_exit_while_fighting(), "the hero can stand on the exit cell mid-fight")
	expect(not bool(_grid_test.call("can_leave_stage_uncleared")), "FARMING keeps the hero on the stage")
	var button: Button = _next_stage_button()
	expect(button != null and bool(button.disabled), "NEXT STAGE stays unavailable while FARMING is on")
	_hud().emit_signal("next_stage_requested")
	await flush_frames(4)
	expect_eq(_stage_number(), 2, "FARMING refuses the replay skip")
