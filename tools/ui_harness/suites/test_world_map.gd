extends "res://tools/ui_harness/ui_harness_suite.gd"

## Phase 6 headless suite: the WorldMapView inside the running combat scene.
##
## The map must be a data-driven presenter: stage nodes are generated from each
## area's StageDatabase RANGE (never a hard-coded Stage 01..10 list and never
## `if stage == 6` type checks), states (LOCKED / AVAILABLE / COMPLETED /
## CURRENT) come from PlayerProgress, and clicking an unlocked stage routes into
## the matching gameplay through the existing grid_combat host.
##
## Phase 7.6: the numbers on the nodes are GLOBAL stage numbers, so an area that
## starts at 11 shows 11..20 rather than restarting at 1.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")
const StageDatabaseScript := preload("res://scripts/data/stage_database.gd")
const AreaViewScript := preload("res://scripts/ui/area_view.gd")
const StageTypeScript := preload("res://scripts/data/stage_type.gd")

var _grid_test: Node


func suite_name() -> String:
	return "test_world_map"


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_grid_test = instance.find_child("grid_combat", true, false)
	# Let stage generation, turn start, and HUD refresh settle.
	await flush_frames(5)


func _hud() -> Node:
	return _grid_test.find_child("MobileCombatHUD", true, false)


func _combat_view() -> Node:
	var hud: Node = _hud()
	return hud.get_node("%CombatView") if hud != null else null


func _world_map() -> Node:
	var hud: Node = _hud()
	return hud.get_node("%WorldMapView") if hud != null else null


func _stage_manager() -> Node:
	return _grid_test.get_node_or_null("StageManager")


func _stage_number() -> int:
	var manager: Node = _stage_manager()
	var state: Resource = manager.get("stage_state") if manager != null else null
	return int(state.get("stage_number")) if state != null else -1


func _progress() -> Resource:
	return _grid_test.call("get_stage_progress") as Resource if _grid_test != null and _grid_test.has_method("get_stage_progress") else null


func _open_map() -> void:
	_grid_test.call("open_world_map")
	await flush_frames(2)


func _forest_view() -> Node:
	var map: Node = _world_map()
	return map.call("get_area_view", &"forest") if map != null else null


func test_map_button_opens_and_closes_the_map() -> void:
	await _mount_game()
	var hud: Node = _hud()
	var combat: Node = _combat_view()
	var map: Node = _world_map()
	expect(hud != null and combat != null and map != null, "hud/combat/map views present")
	if hud == null or combat == null or map == null:
		return

	var map_button: Button = hud.get_node("%MapButton") as Button
	expect(map_button != null, "combat view exposes a MAP button")
	expect(not bool(map.get("visible")), "world map hidden by default")
	expect(bool(combat.get("visible")), "combat view visible by default")

	map_button.pressed.emit()
	await flush_frames(2)
	expect(bool(map.get("visible")), "MAP button opens the world map")
	expect(not bool(combat.get("visible")), "combat view hidden while the map is open")

	map.emit_signal("close_requested")
	await flush_frames(2)
	expect(not bool(map.get("visible")), "map close hides the world map")
	expect(bool(combat.get("visible")), "map close restores the combat view")


func test_stage_nodes_are_generated_from_stage_database() -> void:
	await _mount_game()
	await _open_map()
	var map: Node = _world_map()
	expect(map != null, "world map present")
	expect(bool(map.get("visible")), "world map shown after open")
	expect(map.call("get_area_views").size() >= 1, "map lists at least one authored area")

	var forest := _forest_view()
	expect(forest != null, "forest area view present")
	if forest == null:
		return
	var database: Resource = StageDatabaseScript.load_area(&"forest")
	expect(database != null, "forest StageDatabase loads")
	if database == null:
		return
	var first_stage: int = int(database.get("first_stage"))
	var last_stage: int = int(database.call("get_last_stage"))

	# The node list must come from the authored RANGE, not a hard-coded 01..10 list.
	var present: Array[int] = []
	for number in range(first_stage, last_stage + 1):
		if forest.call("get_stage_node", number) != null:
			present.append(number)
	expect_eq(present.size(), int(database.get("stage_count")), "one stage node per authored stage")
	expect_eq(forest.call("get_window_start"), first_stage, "the first window starts at the area's first global stage")
	expect_eq(forest.call("get_window_end"), last_stage, "the first window ends at the area's last global stage")
	expect(forest.call("get_stage_node", last_stage + 1) == null, "no node exists past the area's range")

	# Every node's type must equal the authored stage_type from the database —
	# proving icons/labels are stage_type driven, never `if stage == 6`.
	for number in range(first_stage, last_stage + 1):
		var node: Button = forest.call("get_stage_node", number) as Button
		var stage: Resource = database.call("get_stage", number)
		expect(int(node.get_meta("stage_type")) == int(stage.get("stage_type")),
			"stage %d node type matches authored stage_type" % number)


func test_default_progress_stands_on_stage_one() -> void:
	await _mount_game()
	await _open_map()
	var forest := _forest_view()
	expect(forest != null, "forest area view present")
	if forest == null:
		return
	var node1: Button = forest.call("get_stage_node", 1) as Button
	var node2: Button = forest.call("get_stage_node", 2) as Button
	expect(node1 != null and node2 != null, "nodes 1 and 2 are built")
	if node1 == null or node2 == null:
		return
	# Boot is global stage 1, which IS Forest 01: the map marks it HERE, and the
	# next stage is still locked because 01 has not been cleared yet.
	expect(not bool(node1.disabled), "stage 1 is enterable")
	expect(bool(node2.disabled), "stage 2 is locked")
	expect(int(node1.get_meta("stage_state")) == AreaViewScript.NodeState.CURRENT,
		"node 1 state is CURRENT (the boot position is there)")
	expect(int(node2.get_meta("stage_state")) == AreaViewScript.NodeState.LOCKED,
		"node 2 state is LOCKED")


func test_map_states_reflect_completion_and_current() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 4):
		expect(bool(progress.call("complete_stage", number)),
			"complete stage %d" % number)
	# The position is one number; the area it belongs to is derived from it, so
	# there is nothing else to set. Reaching it also raises the unlock ceiling.
	progress.set("current_stage_number", 4)
	progress.call("mark_reached", 4)

	await _open_map()
	var forest := _forest_view()
	expect(forest != null, "forest area view present")
	if forest == null:
		return
	var states: Dictionary = {}
	for number in range(1, 6):
		var node: Button = forest.call("get_stage_node", number) as Button
		if node == null:
			continue
		states[number] = int(node.get_meta("stage_state"))
	expect(states.get(1) == AreaViewScript.NodeState.COMPLETED, "stage 1 completed")
	expect(states.get(2) == AreaViewScript.NodeState.COMPLETED, "stage 2 completed")
	expect(states.get(3) == AreaViewScript.NodeState.COMPLETED, "stage 3 completed")
	expect(states.get(4) == AreaViewScript.NodeState.CURRENT, "stage 4 is CURRENT (standing there)")
	expect(states.get(5) == AreaViewScript.NodeState.LOCKED, "stage 5 locked (4 not completed yet)")
	var node4: Button = forest.call("get_stage_node", 4) as Button
	expect(node4 != null and not bool(node4.disabled), "the current stage is enterable")


func test_clicking_a_locked_stage_does_not_enter() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	var position_before: int = int(progress.get("current_stage_number"))
	await _open_map()
	var forest := _forest_view()
	expect(forest != null, "forest area view present")
	if forest == null:
		return
	var node2: Button = forest.call("get_stage_node", 2) as Button
	expect(node2 != null and bool(node2.disabled), "stage 2 node disabled while locked")

	# A real click must not reach a disabled node (so no stage entry occurs).
	push_click(node2)
	await flush_frames(2)
	expect_eq(int(progress.get("current_stage_number")), position_before, "locked click must not move the position")
	expect(_stage_number() == 1, "locked click must not start a battle for stage 2")


func test_clicking_an_unlocked_boss_stage_starts_its_battle() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	# Unlock the boss stage the honest way: clear stages 1..9.
	for number in range(1, 10):
		progress.call("complete_stage", number)

	await _open_map()
	var forest := _forest_view()
	expect(forest != null, "forest area view present")
	if forest == null:
		return
	var boss_node: Button = forest.call("get_stage_node", 10) as Button
	expect(boss_node != null, "boss stage node built")
	if boss_node == null:
		return
	expect(not bool(boss_node.disabled), "boss stage 10 unlocked after clearing 1..9")
	expect(int(boss_node.get_meta("stage_type")) == StageTypeScript.BOSS,
		"stage 10 node is authored BOSS")

	boss_node.pressed.emit()
	await flush_frames(3)
	expect(_stage_number() == 10, "clicking stage 10 starts the battle at level 10")
	expect(int(progress.get("current_stage_number")) == 10, "progress now stands on stage 10")
	var combat: Node = _combat_view()
	var map: Node = _world_map()
	expect(combat != null and bool(combat.get("visible")), "combat view shown after entering the stage")
	expect(map != null and not bool(map.get("visible")), "map hidden once gameplay starts")


func test_very_large_area_is_paginated_not_materialized() -> void:
	# Synthetic 1,000-stage database through the same AreaView code path: only
	# one window of Controls is ever built, so 10K-scale areas stay light.
	var database := StageDatabaseScript.new()
	database.area_id = &"huge"
	database.display_name = "Huge"
	database.stage_count = 1000
	database.default_stage_type = StageTypeScript.COMBAT

	var view = AreaViewScript.new()
	view.setup(database, null)
	track_node(view)
	await flush_frames(2)

	expect(view.get_window_count() == ceili(1000.0 / 24.0), "1,000 stages page into windows of 24")
	expect(view.call("get_stage_node", 1) != null, "window 0 builds stage 1")
	expect(view.call("get_stage_node", 24) != null, "window 0 builds stage 24")
	expect(view.call("get_stage_node", 25) == null, "window 0 does not pre-build stage 25")

	view.show_window(1)
	await flush_frames(2)
	expect(view.call("get_stage_node", 25) != null, "window 1 builds stage 25")
	expect(view.call("get_stage_node", 1) == null, "window 1 no longer holds stage 1")

	view.show_window(view.get_window_count() - 1)
	await flush_frames(2)
	expect(view.call("get_stage_node", 1000) != null, "last window still reaches stage 1000")


func test_paginated_area_with_a_non_default_first_stage() -> void:
	# An area that starts at global stage 11 pages on the SAME numbers it shows:
	# window 0 holds 11..34, window 1 continues at 35 — never a restart at 1.
	var database := StageDatabaseScript.new()
	database.area_id = &"late"
	database.display_name = "Late"
	database.first_stage = 11
	database.stage_count = 1000
	database.default_stage_type = StageTypeScript.COMBAT

	var view = AreaViewScript.new()
	view.setup(database, null)
	track_node(view)
	await flush_frames(2)

	expect(view.call("get_window_start") == 11, "the first window starts at the area's first global stage")
	expect(view.call("get_window_end") == 34, "the first window ends 24 global stages later")
	expect(view.call("get_stage_node", 11) != null, "window 0 builds the area's first stage (11)")
	expect(view.call("get_stage_node", 34) != null, "window 0 builds global stage 34")
	expect(view.call("get_stage_node", 35) == null, "window 0 does not pre-build global stage 35")
	expect(view.call("get_stage_node", 10) == null, "a number before the range is never built")
	expect(view.call("show_window_for_stage", 40), "the view can jump to the window holding a global stage")
	await flush_frames(2)
	expect(view.call("get_stage_node", 40) != null, "the jumped-to window builds global stage 40")
	expect(view.call("get_stage_node", 11) == null, "and no longer holds the first window")

	view.show_window(view.get_window_count() - 1)
	await flush_frames(2)
	expect(view.call("get_stage_node", 1010) != null, "the last window reaches the range's last stage (1010)")
