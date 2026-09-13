extends "res://tools/ui_harness/ui_harness_suite.gd"

## Headless integration suite for the DEV panel's AUTO BACKWARD option: the existing
## AUTO automation pointed at the OTHER gate — the previous stage — through the same
## pathfinder, with enemies IGNORED (no target is picked and nothing is attacked).
##
## Mounts the real game scene (res://scenes/world/Main.tscn) and asserts the retreat
## through the Stage Starting Point, the untouched enemies along the way, the mutual
## exclusion with forward AUTO, and the stop on stage 01. The forward AUTO behavior
## itself is covered by the existing suites (test_stage_exit_advance, test_stage_range).

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")

const FASTEST_SPEED: int = 2

var _grid_test: Node


func suite_name() -> String:
	return "test_auto_backward"


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


func _auto() -> Node:
	return _grid_test.find_child("AutoCombatController")


func _hud() -> Node:
	return _grid_test.find_child("MobileCombatHUD", true, false)


func _panel() -> Node:
	return _grid_test.find_child("DevelopmentPanel", true, false)


func _stage_number() -> int:
	return int(_stage().get("stage_state").get("stage_number"))


func _position() -> Vector2i:
	return _player().call("get_grid_position")


func _auto_backward_on() -> bool:
	return bool(_auto().call("is_auto_backward_enabled"))


func _find_living_enemy() -> Node:
	for enemy in _stage().call("get_spawned_enemies"):
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


func _place_player(cell: Vector2i) -> bool:
	var placed: bool = bool(_player().call("place_at", cell))
	await flush_frames(1)
	return placed


## Advances to stage 2 the manual way: clear the fight, stand on the exit, NEXT
## STAGE — so the retreat below has a previous stage to walk back into.
func _start_stage_two() -> void:
	await _defeat_all_enemies()
	expect(await _place_player(_stage().call("get_stage_exit_cell")), "the hero stands on the exit")
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)


## Enemy instance id -> current HP, so "nothing was attacked" can be proven after
## the hero has walked for a while.
func _enemy_hp() -> Dictionary:
	var hp: Dictionary = {}
	for enemy in _stage().call("get_spawned_enemies"):
		if enemy == null or not is_instance_valid(enemy) or bool(enemy.call("is_defeated")):
			continue
		var runtime: Variant = enemy.get("enemy_runtime")
		if runtime == null:
			continue
		hp[enemy.get_instance_id()] = int(runtime.get("current_hp"))
	return hp


func _enemies_undamaged(before: Dictionary) -> bool:
	for id in before:
		var enemy := instance_from_id(id) as Node
		# A vanished enemy means the retreat killed it, which is exactly what must
		# never happen: AUTO BACKWARD ignores enemies.
		if enemy == null or not is_instance_valid(enemy):
			return false
		var runtime: Variant = enemy.get("enemy_runtime")
		if runtime == null or int(runtime.get("current_hp")) != int(before[id]):
			return false
	return true


func _wait_until(condition: Callable, frames: int) -> bool:
	for _i in frames:
		if bool(condition.call()):
			return true
		await flush_frames(1)
	return bool(condition.call())


## The DEV panel is the option's entry point: it toggles the live controller, turns
## on AUTO BACKWARD alone, and reports the mode on its own button.
func test_dev_panel_toggles_auto_backward() -> void:
	await _mount_game()
	var panel := _panel()
	expect(panel != null, "the DEV panel is mounted with the HUD")
	if panel == null:
		return
	expect(bool(panel.call("dev_set_auto_backward", true)), "the DEV panel can start AUTO BACKWARD")
	expect(_auto_backward_on(), "AUTO BACKWARD is on")
	expect(not bool(_auto().call("is_auto_enabled")), "forward AUTO stays off")
	expect(bool(_auto().call("is_automation_active")), "an automation is driving the turn")
	var button := panel.get("_auto_backward_button") as Button
	expect(button != null, "the AUTO BACKWARD button exists")
	if button != null:
		expect_eq(button.text, "AUTO BACKWARD: ON", "the button reports the mode")
	expect(bool(panel.call("dev_set_auto_backward", false)), "the DEV panel can stop AUTO BACKWARD")
	expect(not _auto_backward_on(), "AUTO BACKWARD is off again")
	if button != null:
		expect_eq(button.text, "AUTO BACKWARD: OFF", "the button reports the stop")


## Both automations drive the same player turn, so starting one stops the other.
func test_auto_and_auto_backward_are_mutually_exclusive() -> void:
	await _mount_game()
	_auto().call("set_auto_enabled", true)
	expect(bool(_auto().call("is_auto_enabled")), "forward AUTO is on first")
	_auto().call("set_auto_backward_enabled", true)
	expect(not bool(_auto().call("is_auto_enabled")), "starting AUTO BACKWARD stopped forward AUTO")
	expect(_auto_backward_on(), "AUTO BACKWARD is on")
	_auto().call("set_auto_enabled", true)
	expect(bool(_auto().call("is_auto_enabled")), "forward AUTO is on again")
	expect(not _auto_backward_on(), "starting forward AUTO stopped AUTO BACKWARD")


## The retreat itself: the hero walks to the Stage Starting Point, every enemy it
## passes is left untouched, and the step onto the gate moves the battle back.
func test_auto_backward_retreats_ignoring_enemies() -> void:
	await _mount_game()
	await _start_stage_two()
	expect_eq(_stage_number(), 2, "the fixture starts on stage 2")
	expect_eq(_position(), Vector2i(1, 3), "stage 2 starts right of its Starting Cell")

	# Start part-way across the arena, so the walk is long enough to inspect it.
	var start_cell := Vector2i(8, 3)
	expect(await _place_player(start_cell), "the hero is placed before the retreat")
	if _position() != start_cell:
		return
	var hp_before: Dictionary = _enemy_hp()
	expect(hp_before.size() > 0, "stage 2 is a real fight")

	_auto().set("action_delay_seconds", 0.0)
	_auto().call("set_game_speed", FASTEST_SPEED)
	_auto().call("set_auto_backward_enabled", true)

	# Mid-walk: the hero is closing on the Starting Cell while the fight is untouched.
	var moved := await _wait_until(func() -> bool: return _position().x < start_cell.x, 240)
	expect(moved, "AUTO BACKWARD walks the hero toward the Starting Cell")
	expect_eq(_stage_number(), 2, "the retreat is still on stage 2 mid-walk")
	expect(_enemies_undamaged(hp_before), "no enemy was attacked during the retreat")
	expect(_find_living_enemy() != null, "enemies are still standing during the retreat")

	# On to the end: stepping onto the gate moves the battle into the previous stage.
	var returned := await _wait_until(func() -> bool: return _stage_number() == 1, 480)
	expect(returned, "the retreat moved the battle into the previous stage")
	expect_eq(_position(), Vector2i(11, 3), "the walk back arrives one left of the Next Stage Point")

	# Stage 01 has nothing behind it, so the retreat finishes instead of idling.
	var stopped := await _wait_until(func() -> bool: return not _auto_backward_on(), 240)
	expect(stopped, "AUTO BACKWARD stops on stage 01")
	expect(not bool(_auto().call("is_auto_enabled")), "the stop left forward AUTO off")
	expect(_find_living_enemy() != null, "the previous stage is a real fight again")


## Stage 01 is the mirror of the forward gate: there is nothing before it, so the
## retreat never starts walking and the mode turns itself off.
func test_auto_backward_stops_on_the_first_stage() -> void:
	await _mount_game()
	expect_eq(_stage_number(), 1, "the boot stage is stage 1")
	_auto().set("action_delay_seconds", 0.0)
	_auto().call("set_game_speed", FASTEST_SPEED)
	_auto().call("set_auto_backward_enabled", true)
	expect(_auto_backward_on(), "AUTO BACKWARD is armed on stage 1")
	var stopped := await _wait_until(func() -> bool: return not _auto_backward_on(), 120)
	expect(stopped, "AUTO BACKWARD stops on stage 01")
	expect_eq(_position(), Vector2i(1, 3), "the hero stayed put on the first stage")
	expect_eq(_stage_number(), 1, "the battle stayed on stage 1")
