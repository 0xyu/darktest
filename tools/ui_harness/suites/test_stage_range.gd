extends "res://tools/ui_harness/ui_harness_suite.gd"

## Phase 7.6 headless suite: the GLOBAL stage range model, end to end.
##
## The model: one never-resetting stage counter; an Area is a RANGE on it; the
## current area is DERIVED from the position; the position has exactly one writer.
## These tests drive the real game scene (res://scenes/world/Main.tscn) and prove
## the three places that used to disagree — the stage bar, PlayerProgress and the
## world map's HERE marker — always carry the same number, across an area
## boundary and across a defeat rollback.
##
## A second area (11-20) is modelled through StageDatabase's explicit area table
## instead of shipping a .tres, so this phase adds no content. T6 covers the
## authoring rule that keeps ranges resolvable: they must not overlap.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")
const StageDatabaseScript := preload("res://scripts/data/stage_database.gd")
const StageTypeScript := preload("res://scripts/data/stage_type.gd")
const AreaViewScript := preload("res://scripts/ui/area_view.gd")

var _grid_test: Node


func suite_name() -> String:
	return "test_stage_range"


## Every test starts from the same authored table: Forest 1-10 (shipped) plus an
## in-memory Forest 2 that covers 11-20. Both are installed BEFORE the scene
## mounts, because the boot battle's area is derived from the table.
func setup() -> void:
	StageDatabaseScript.set_area_table_override(_two_area_table())


## The override is process-global state, so it must never leak into another suite.
func suite_teardown() -> void:
	StageDatabaseScript.clear_area_table_override()


func _two_area_table() -> Array[StageDatabase]:
	var table: Array[StageDatabase] = []
	var forest: StageDatabase = StageDatabaseScript.load_area(&"forest")
	if forest != null:
		table.append(forest)
	var forest2 := StageDatabaseScript.new() as StageDatabase
	forest2.area_id = &"forest2"
	forest2.display_name = "Forest 2"
	forest2.first_stage = 11
	forest2.stage_count = 10
	forest2.default_stage_type = StageTypeScript.COMBAT
	table.append(forest2)
	return table


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_grid_test = instance.find_child("grid_combat", true, false)
	await flush_frames(6)


func _hud() -> Node:
	return _grid_test.find_child("MobileCombatHUD", true, false)


func _stage() -> Node:
	return _grid_test.find_child("StageManager")


func _auto() -> Node:
	return _grid_test.find_child("AutoCombatController")


func _player() -> Node:
	return _grid_test.find_child("Player", true, false)


func _world_map() -> Node:
	var hud: Node = _hud()
	return hud.get_node("%WorldMapView") if hud != null else null


func _stage_bar() -> Node:
	return _hud().find_child("StageControl", true, false) if _hud() != null else null


func _progress() -> Resource:
	return _grid_test.call("get_stage_progress") as Resource if _grid_test != null and _grid_test.has_method("get_stage_progress") else null


func _status_text() -> String:
	return str(_grid_test.get("_last_move_text")) if _grid_test != null else ""


func _stage_number() -> int:
	var manager: Node = _stage()
	var state: Resource = manager.get("stage_state") as Resource if manager != null else null
	return int(state.get("stage_number")) if state != null else -1


func _position() -> int:
	var progress: Resource = _progress()
	return int(progress.get("current_stage_number")) if progress != null else -1


func _area_of_position() -> String:
	var progress: Resource = _progress()
	return String(progress.call("get_current_area_id")) if progress != null else ""


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


func _place_player(cell: Vector2i) -> void:
	_player().call("place_at", cell)
	await flush_frames(1)


## The Next Stage Point of the current arena: the extra right cell of row 4.
func _exit_cell() -> Vector2i:
	return _stage().call("get_stage_exit_cell")


func _grid() -> Node:
	return _grid_test.find_child("Grid", true, false)


func _turn() -> Node:
	return _grid_test.find_child("TurnManager")


## Kills the hero the way combat does: wound them so the next enemy blow is
## lethal, stand next to a living enemy and let the ENEMY PHASE run for real. The
## turn manager is what authorizes an enemy attack, so driving the death through
## it exercises the production path rather than a poked-in defeat phase.
##
## The defeat itself is transient in this build — the host revives the hero and
## rolls the battle back a stage as soon as it lands — so this waits for the
## OBSERVABLE outcome (the position moving back) and asserts the status line the
## rollback prints. The wait is real time, not frames: entering the enemy phase
## waits on the hero's attack presentation, which is a timer.
func _kill_player() -> void:
	# Start from a clean fight so the enemy phase certainly has a living enemy in
	# the turn order and the scene is on the player's turn.
	await _grid_test.call("enter_area_stage", _position())
	await flush_frames(3)
	var position_before: int = _position()
	var enemy := _find_living_enemy()
	expect(enemy != null, "a living enemy is available to land the killing blow")
	if enemy == null:
		return
	_player().get("player_stats").set("current_hp", 1)
	await _stand_next_to(enemy)
	_turn().call("complete_player_turn")
	var waited: float = 0.0
	while waited < 10.0 and _position() == position_before:
		await _tree.create_timer(0.05).timeout
		waited += 0.05
	expect(_position() < position_before, "the defeat rolled the position back (was %d, now %d)" % [position_before, _position()])
	expect_contains(_status_text(), "DEFEAT — RETURNED TO STAGE", "the rollback reports the defeat")
	# The rollback is deferred by the host, so let it settle before reading state.
	await flush_frames(8)


## Teleports the hero onto a walkable cell neighbouring `enemy`, so a melee
## attacker has a legal target.
func _stand_next_to(enemy: Node) -> void:
	var enemy_cell: Vector2i = enemy.call("get_grid_position")
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var cell: Vector2i = enemy_cell + direction
		if not bool(_grid().call("is_walkable", cell)) or bool(_grid().call("is_occupied", cell)):
			continue
		if bool(_player().call("place_at", cell)):
			await flush_frames(1)
			return


func _open_map() -> void:
	_grid_test.call("open_world_map")
	await flush_frames(3)


func _area_view(area_id: StringName) -> Node:
	var map: Node = _world_map()
	return map.call("get_area_view", area_id) if map != null else null


## The GLOBAL stage number an area view currently marks HERE, or -1 when it marks
## none (which is the correct answer for an area that does not hold the position).
func _here_stage_in(area_view: Node) -> int:
	if area_view == null:
		return -1
	var database: Resource = area_view.call("get_database")
	if database == null:
		return -1
	for number in range(int(database.get("first_stage")), int(database.call("get_last_stage")) + 1):
		var node: Button = area_view.call("get_stage_node", number) as Button
		if node != null and int(node.get_meta("stage_state")) == AreaViewScript.NodeState.CURRENT:
			return number
	return -1


## The single check this whole phase exists for: the stage bar, the battle's own
## stage number, PlayerProgress and the map's HERE marker are one number.
##
## The expected HERE marker is derived from the same rule the view uses: a stage
## the player has not cleared yet is marked HERE, while a stage they are standing
## on after being pushed back shows DONE instead (COMPLETED outranks CURRENT in
## AreaView). Either way no OTHER stage may claim HERE — the old defect was the
## map pointing at a stage the player had already lost.
func _expect_one_position(message: String) -> void:
	var bar: Node = _stage_bar()
	expect(bar != null, "the HUD exposes a stage bar")
	if bar == null:
		return
	expect_eq(int(bar.call("get_current_stage")), _position(), "%s: stage bar == PlayerProgress position" % message)
	expect_eq(_stage_number(), _position(), "%s: battle stage == PlayerProgress position" % message)
	var cleared: bool = bool(_progress().call("is_stage_completed", _position()))
	var expected_here: int = -1 if cleared else _position()
	var area: String = _area_of_position()
	if area == "forest":
		expect_eq(_here_stage_in(_area_view(&"forest")), expected_here, "%s: forest HERE matches the position" % message)
		expect_eq(_here_stage_in(_area_view(&"forest2")), -1, "%s: forest2 marks no HERE" % message)
	elif area == "forest2":
		expect_eq(_here_stage_in(_area_view(&"forest2")), expected_here, "%s: forest2 HERE matches the position" % message)
		expect_eq(_here_stage_in(_area_view(&"forest")), -1, "%s: forest marks no HERE" % message)
	else:
		expect_eq(_here_stage_in(_area_view(&"forest")), -1, "%s: forest marks no HERE past its range" % message)
		expect_eq(_here_stage_in(_area_view(&"forest2")), -1, "%s: forest2 marks no HERE past its range" % message)


# --- T1 -------------------------------------------------------------------

func test_t1_boot_is_inside_the_first_area() -> void:
	await _mount_game()
	expect_eq(_position(), 1, "boot stands on global stage 1")
	expect_eq(_area_of_position(), "forest", "the area is DERIVED as forest from the position")
	expect_eq(_stage_number(), 1, "the boot battle runs stage 1")
	await _open_map()
	expect_eq(_here_stage_in(_area_view(&"forest")), 1, "the map marks stage 1 HERE")
	expect_eq(_here_stage_in(_area_view(&"forest2")), -1, "the second area marks no HERE")
	expect_eq(int(_stage_bar().call("get_current_stage")), 1, "the stage bar shows stage 1")
	await _expect_one_position("at boot")


# --- T2 -------------------------------------------------------------------

func test_t2_clearing_an_area_boundary_switches_the_derived_area() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 10):
		progress.call("complete_stage", number)
	await _open_map()
	await _click_map_node(10)
	await _defeat_all_enemies()

	# The 10th clear reports the NEXT area's stage, read from data: the chain does
	# not stop at the boundary.
	expect_contains(_status_text(), "STAGE 11 (COMBAT) UNLOCKED", "clearing 10 opens 11 from the second area's data")
	expect_eq(_position(), 10, "the position is the area's last stage")
	expect_eq(_area_of_position(), "forest", "which is still the first area")

	# Advancing across the boundary switches the derived area with no special rule.
	await _place_player(_exit_cell())
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_stage_number(), 11, "the advance crossed into global stage 11")
	expect_eq(_position(), 11, "the position followed the advance")
	expect_eq(_area_of_position(), "forest2", "the area switched to forest2 automatically")

	await _open_map()
	var second := _area_view(&"forest2")
	expect(second != null, "the map lists the second area")
	expect_eq(_here_stage_in(second), 11, "the second area's HERE marker is on stage 11")
	expect_eq(_here_stage_in(_area_view(&"forest")), -1, "the first area marks no HERE any more")
	expect_eq(int(second.call("get_window_start")), 11, "the visible window is the one holding stage 11")
	await _expect_one_position("after crossing the boundary")


func _click_map_node(stage_number: int) -> void:
	var forest := _area_view(&"forest")
	var node: Button = forest.call("get_stage_node", stage_number) as Button
	expect(node != null, "map node %d exists before the click" % stage_number)
	if node != null:
		node.pressed.emit()
	await flush_frames(4)


# --- T3 -------------------------------------------------------------------

func test_t3_the_unlock_chain_is_global() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	expect(not bool(progress.call("is_stage_unlocked", 11)), "stage 11 starts locked behind stage 10")
	for number in range(1, 10):
		progress.call("complete_stage", number)
	expect(not bool(progress.call("is_stage_unlocked", 11)), "stage 11 needs stage 10, not just stages 1-9")
	progress.call("complete_stage", 10)
	expect(bool(progress.call("is_stage_unlocked", 11)), "clearing stage 10 unlocks stage 11 across the boundary")
	expect(not bool(progress.call("is_stage_unlocked", 12)), "and does not unlock stage 12")
	expect(StageDatabaseScript.lookup(11) != null, "stage 11 is authored by the second area")


# --- T4 -------------------------------------------------------------------

func test_t4_all_three_places_agree_on_the_position() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 4):
		progress.call("complete_stage", number)

	# (a) manual advance
	await _grid_test.call("enter_area_stage", 4)
	await flush_frames(3)
	await _open_map()
	await _expect_one_position("after a map entry")
	await _defeat_all_enemies()
	await _place_player(_exit_cell())
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_position(), 5, "the manual advance moved the position")
	await _open_map()
	await _expect_one_position("after a manual advance")

	# (b) AUTO advance — the same seam, so the same number everywhere
	var auto: Node = _auto()
	auto.set("action_delay_seconds", 0.0)
	auto.call("set_game_speed", 2)
	await _grid_test.call("enter_area_stage", 6)
	await _place_player(_exit_cell())
	await _defeat_all_enemies()
	auto.call("set_auto_enabled", true)
	await flush_frames(16)
	# AUTO keeps playing, so pin down only what this phase is about: the position
	# moved on, and every place still agrees on it.
	auto.call("set_auto_enabled", false)
	await flush_frames(3)
	expect(_position() > 5, "the AUTO advance moved the position past the manual one (now %d)" % _position())
	await _open_map()
	await _expect_one_position("after an AUTO advance")

	# (c) defeat rollback — the position follows the battle backwards while the
	#     unlock ceiling stays where the player got to
	var ceiling_before: int = int(progress.get("highest_stage_reached"))
	var position_before: int = _position()
	await _kill_player()
	expect_eq(_stage_number(), _position(), "the rollback kept the battle and the position together")
	expect_eq(_position(), position_before - 1, "the defeat moved the position one stage back (%d -> %d)" % [position_before, _position()])
	expect(int(progress.get("highest_stage_reached")) == ceiling_before, "the unlock ceiling did not roll back")
	await _open_map()
	await _expect_one_position("after a defeat rollback")


# --- T5 -------------------------------------------------------------------

func test_t5_past_the_last_authored_area_still_advances() -> void:
	# Forest 2 ends at 20, so 21+ is the endless tail: no area authors it, yet the
	# progression must keep working (no completion to record, no HERE to show,
	# and the unlock ceiling still rising — otherwise the game would deadlock).
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 20):
		progress.call("complete_stage", number)
	await _open_map()
	var second := _area_view(&"forest2")
	var node20: Button = second.call("get_stage_node", 20) as Button
	expect(node20 != null and not bool(node20.disabled), "the last authored stage is enterable")
	if node20 != null:
		node20.pressed.emit()
	await flush_frames(4)
	await _defeat_all_enemies()
	expect_eq(progress.get("completed_stages").size(), 20, "the last authored stage recorded its completion")

	await _place_player(_exit_cell())
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_position(), 21, "the position advanced past the authored path")
	expect_eq(_area_of_position(), "", "and derives no area")
	expect_eq(_status_text().find("AREA"), -1, "the clear falls back to the endless status text")

	await _defeat_all_enemies()
	await flush_frames(2)
	expect_eq(progress.get("completed_stages").size(), 20, "an un-authored stage records no completion")
	expect(int(progress.get("highest_stage_reached")) >= 21, "the unlock ceiling still rose (no deadlock)")
	await _open_map()
	expect_eq(_here_stage_in(_area_view(&"forest2")), -1, "no area marks HERE past its range")
	expect_contains(_world_map().call("get_endless_text"), "ENDLESS — stage 21", "the map states the endless position instead")
	await _expect_one_position("past the authored path")


# --- T6 -------------------------------------------------------------------

func test_t6_overlapping_ranges_are_rejected() -> void:
	# Two areas claiming the same global stage number would make "which area is
	# this?" ambiguous, so the authoring rule is checked explicitly.
	var first := StageDatabaseScript.new() as StageDatabase
	first.area_id = &"first"
	first.first_stage = 1
	first.stage_count = 10
	var second := StageDatabaseScript.new() as StageDatabase
	second.area_id = &"second"
	second.first_stage = 5
	second.stage_count = 10
	var table: Array[StageDatabase] = [first, second]
	var conflicts: PackedStringArray = StageDatabaseScript.collect_range_conflicts(table)
	expect(conflicts.size() == 1, "an overlapping pair reports one conflict")
	expect_contains(" ".join(conflicts), "overlap", "the conflict names the overlap")

	# Touching ranges (10 then 11) are NOT an overlap: that is the normal layout.
	second.first_stage = 11
	var touching: Array[StageDatabase] = [first, second]
	expect(StageDatabaseScript.collect_range_conflicts(touching).is_empty(), "adjacent ranges do not conflict")

	# The shipped content must satisfy the rule.
	expect(StageDatabaseScript.get_authored_range_conflicts().is_empty(), "the authored areas have disjoint ranges")
