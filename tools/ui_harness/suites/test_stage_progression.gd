extends "res://tools/ui_harness/ui_harness_suite.gd"

## Phase 7 headless suite: the authored stage completion / return flow.
##
## Loop under test:
##   WorldMap → Stage → Gameplay → Complete (PlayerProgress) → unlock next → map
##
## Battle stages (COMBAT/BOSS) complete when their authored battle clears; a TOWN
## stage completes on entry (the visit IS the clear, so the linear unlock chain
## can advance). Completing the final stage of an area finishes it.
##
## Phase 7.6: stage numbers are GLOBAL and the area is derived from the position,
## so the boot battle is simply stage 1 of the first authored area — clearing it
## records progress like any other clear, and the loop keeps advancing past the
## end of the authored path without any special "endless" branch.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")
const AreaViewScript := preload("res://scripts/ui/area_view.gd")

var _grid_test: Node


func suite_name() -> String:
	return "test_stage_progression"


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


func _combat_view() -> Node:
	var hud: Node = _hud()
	return hud.get_node("%CombatView") if hud != null else null


func _town_view() -> Node:
	var hud: Node = _hud()
	return hud.get_node("%TownView") if hud != null else null


func _world_map() -> Node:
	var hud: Node = _hud()
	return hud.get_node("%WorldMapView") if hud != null else null


func _stage_number() -> int:
	var manager: Node = _stage()
	var state: Resource = manager.get("stage_state") as Resource if manager != null else null
	return int(state.get("stage_number")) if state != null else -1


func _progress() -> Resource:
	return _grid_test.call("get_stage_progress") as Resource if _grid_test != null and _grid_test.has_method("get_stage_progress") else null


func _status_text() -> String:
	return str(_grid_test.get("_last_move_text")) if _grid_test != null else ""


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


func _open_map() -> void:
	_grid_test.call("open_world_map")
	await flush_frames(2)


func _forest_view() -> Node:
	var map: Node = _world_map()
	return map.call("get_area_view", &"forest") if map != null else null


func _enter_typed_stage(stage_number: int) -> void:
	_grid_test.call("enter_area_stage", stage_number)
	await flush_frames(3)


func _click_map_node(stage_number: int) -> void:
	var forest := _forest_view()
	var node: Button = forest.call("get_stage_node", stage_number) as Button
	expect(node != null, "map node %d exists before click" % stage_number)
	if node != null:
		node.pressed.emit()
	await flush_frames(3)


# --- Tests ---------------------------------------------------------------

func test_authored_battle_clear_records_completion_and_continues_endless() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	await _enter_typed_stage(1)
	await _defeat_all_enemies()

	expect(bool(progress.call("is_stage_completed", 1)), "clearing authored stage 01 records the completion")
	expect(bool(progress.call("is_stage_unlocked", 2)), "clearing stage 1 unlocks stage 2")
	expect_contains(_status_text(), "AREA FOREST", "authored clear status names the area")
	expect_contains(_status_text(), "STAGE 02 (COMBAT) UNLOCKED", "authored clear status reports the next authored stage from data")

	# The game is primarily endless: the exit / NEXT STAGE moves the battle one
	# stage on. The world map is an always-available shortcut, not a hub the
	# player is forced back to after every clear.
	await _place_player(Vector2i(10, 3))
	_hud().emit_signal("next_stage_requested")
	await flush_frames(4)
	var map: Node = _world_map()
	var combat: Node = _combat_view()
	expect(map != null and not bool(map.get("visible")), "clearing an authored stage does not force the world map open")
	expect(combat != null and bool(combat.get("visible")), "the combat view stays up after the authored clear")
	expect_eq(_stage_number(), 2, "the exit continues the endless loop into battle 2")
	expect(bool(progress.call("is_stage_completed", 1)), "the completion survives the advance")

	# The finished area is inspectable on demand through the map shortcut.
	await _open_map()
	var forest := _forest_view()
	var node2: Button = forest.call("get_stage_node", 2) as Button
	expect(node2 != null and not bool(node2.disabled), "stage 2 is AVAILABLE on the refreshed map")
	var node1: Button = forest.call("get_stage_node", 1) as Button
	expect(int(node1.get_meta("stage_state")) == AreaViewScript.NodeState.COMPLETED, "cleared stage 1 shows COMPLETED")


func test_auto_and_manual_advance_share_one_seam() -> void:
	# The bug this replaced: AUTO called StageManager.start_next_stage() directly
	# and bypassed the host, so the SAME clear advanced into an endless battle
	# when AUTO was on, but returned to the world map when the player pressed
	# NEXT STAGE. AUTO and manual now share one seam, so the outcome — the
	# recorded completion, the reported next stage, and whether the map opens —
	# is identical either way.
	await _mount_game()
	var progress: Resource = _progress()
	var auto: Node = _auto()
	# Drive the auto walker without depending on real-time deltas in headless.
	auto.set("action_delay_seconds", 0.0)
	auto.call("set_game_speed", 2)  # GameSpeed.FASTEST -> action_delay_seconds

	# --- Manual advance: clear authored stage 02, then press NEXT STAGE -------
	await _enter_typed_stage(2)
	await _defeat_all_enemies()
	expect(bool(progress.call("is_stage_completed", 2)), "manual clear records stage 02")
	await _place_player(Vector2i(10, 3))
	_hud().emit_signal("next_stage_requested")
	await flush_frames(4)
	expect_eq(_stage_number(), 3, "manual advance moves on to battle 3")
	var manual_map_visible: bool = bool(_world_map().get("visible"))

	# --- AUTO advance: same clear, advanced by the auto walker ---------------
	await _enter_typed_stage(4)
	await _place_player(Vector2i(10, 3))
	await _defeat_all_enemies()
	expect(bool(progress.call("is_stage_completed", 4)), "AUTO clear records the authored completion exactly like manual")
	expect_contains(_status_text(), "STAGE 05 (COMBAT) UNLOCKED", "AUTO clear reports the same authored next stage")
	expect(not bool(progress.call("is_stage_completed", 5)), "the AUTO clear does not complete the stage it has not played")

	# AUTO is only asked to advance once it is running, so it walks to the exit
	# and raises the same request the NEXT STAGE button raises.
	auto.call("set_auto_enabled", true)
	await flush_frames(12)
	expect_eq(_stage_number(), 5, "AUTO advance reaches the same next battle as the manual press")
	expect(bool(_world_map().get("visible")) == manual_map_visible, "AUTO and manual agree on whether the map opens")
	expect(bool(progress.call("is_stage_completed", 4)), "the AUTO clear's completion survives the advance")


func test_mid_path_clear_unlocks_next_authored_type_from_data() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	# 08 is authored TOWN; the unlock text must come from StageDatabase, not a
	# hard-coded rule ("完成 07 → 08 unlocked（类型=TOWN，由 stage_type 决定）").
	for number in range(1, 7):
		progress.call("complete_stage", number)
	await _enter_typed_stage(7)
	await _defeat_all_enemies()

	expect(bool(progress.call("is_stage_completed", 7)), "clearing stage 07 records the completion")
	expect(bool(progress.call("is_stage_unlocked", 8)), "clearing stage 7 unlocks stage 8")
	expect_contains(_status_text(), "STAGE 08 (TOWN) UNLOCKED", "the authored TOWN type is reported for the next stage")


func test_map_entry_to_town_counts_as_completed_and_closes_back_to_map() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 8):
		progress.call("complete_stage", number)

	await _open_map()
	await _click_map_node(8)
	var town: Node = _town_view()
	var combat: Node = _combat_view()
	expect(town != null and bool(town.get("visible")), "clicking the town stage opens the town view")
	expect(combat != null and not bool(combat.get("visible")), "combat view hidden while the town is open")
	expect(bool(progress.call("is_stage_completed", 8)), "entering the town stage counts as completed")
	expect(bool(progress.call("is_stage_unlocked", 9)), "the town visit unlocks stage 9")
	expect_eq(int(progress.get("current_stage_number")), 8, "the town visit moves the position onto the town stage")

	town.emit_signal("close_requested")
	await flush_frames(4)
	var map: Node = _world_map()
	expect(map != null and bool(map.get("visible")), "a map-origin town visit closes back to the world map")
	expect(town != null and not bool(town.get("visible")), "town hidden after close")
	var forest := _forest_view()
	var node9: Button = forest.call("get_stage_node", 9) as Button
	expect(node9 != null and not bool(node9.disabled), "stage 9 is AVAILABLE after the town visit")
	var node8: Button = forest.call("get_stage_node", 8) as Button
	expect(int(node8.get_meta("stage_state")) == AreaViewScript.NodeState.COMPLETED, "visited town stage shows COMPLETED")


func test_map_entry_to_combat_stage_starts_battle_and_hides_map() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 6):
		progress.call("complete_stage", number)

	await _open_map()
	await _click_map_node(6)
	var map: Node = _world_map()
	var combat: Node = _combat_view()
	expect(map != null and not bool(map.get("visible")), "entering a stage from the map hides the map")
	expect(combat != null and bool(combat.get("visible")), "a map-entered combat stage shows the combat view")
	expect(_stage_number() == 6, "map entry starts the battle for the clicked stage")


func test_direct_typed_town_visit_closes_back_to_combat() -> void:
	# DEV / direct typed town entries keep the classic close behavior: back to
	# the combat view (only map-origin visits return to the map).
	await _mount_game()
	var progress: Resource = _progress()
	await _enter_typed_stage(8)
	var town: Node = _town_view()
	var combat: Node = _combat_view()
	expect(town != null and bool(town.get("visible")), "typed town entry opens the town view")
	expect(bool(progress.call("is_stage_completed", 8)), "a direct typed town visit also counts as completed")

	town.emit_signal("close_requested")
	await flush_frames(4)
	expect(not bool(town.get("visible")), "town hidden after close")
	expect(combat != null and bool(combat.get("visible")), "direct typed town close restores the combat view")
	var map: Node = _world_map()
	expect(map != null and not bool(map.get("visible")), "no world map shown for a direct typed town close")


## Phase 7.6 reverses the old "the endless boot loop must never write progress"
## rule: boot IS stage 1 of the first authored area, so clearing it records the
## completion and reports the authored "what's next" exactly like any other clear.
## There is no separate un-authored boot state any more.
func test_boot_clear_records_area_1_progress_and_advances() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	var boot: Dictionary = progress.call("get_current_stage")
	expect_eq(int(boot["stage_number"]), 1, "boot stands on global stage 1")
	expect(String(boot["area_id"]) == "forest", "boot is inside the authored Forest area (derived, not stored)")

	await _defeat_all_enemies()
	expect(bool(progress.call("is_stage_completed", 1)), "clearing the boot stage records stage 01")
	expect_contains(_status_text(), "AREA FOREST", "the boot clear is reported as authored progress")
	expect_contains(_status_text(), "STAGE 02 (COMBAT) UNLOCKED", "the boot clear reports the authored next stage")

	await _place_player(Vector2i(10, 3))
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_stage_number(), 2, "the loop still advances to battle 2 from the exit")
	expect_eq(int(progress.get("current_stage_number")), 2, "the position follows the advance")
	var map: Node = _world_map()
	expect(map != null and not bool(map.get("visible")), "advancing does not open the world map")


func test_farming_on_typed_stage_records_once_and_stays() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	_auto().call("set_farming_enabled", true)
	await _enter_typed_stage(1)
	await _defeat_all_enemies()
	# FARMING re-spawns the same authored stage; the first clear records the
	# completion and later re-clears are idempotent (one dictionary key).
	await flush_frames(16)
	expect_eq(_stage_number(), 1, "farming stays on the typed stage")
	expect_eq(progress.get("completed_stages").size(), 1, "farming re-clears keep a single completion record")

	await _defeat_all_enemies()
	await flush_frames(4)
	expect_eq(progress.get("completed_stages").size(), 1, "second farming clear does not duplicate the completion")
	expect(bool(progress.call("is_stage_completed", 1)), "typed farming clear recorded stage 01")


func test_boss_clear_finishes_the_area() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 10):
		progress.call("complete_stage", number)

	await _open_map()
	await _click_map_node(10)
	await _defeat_all_enemies()
	expect(bool(progress.call("is_stage_completed", 10)), "clearing the authored BOSS stage records the completion")
	expect_contains(_status_text(), "AREA FOREST COMPLETE (10/10)", "final stage clear reports the area is complete")

	# The authored path is finished, so the endless loop simply carries on past
	# it; the map is opened on demand to inspect the finished area.
	await _place_player(Vector2i(10, 3))
	_hud().emit_signal("next_stage_requested")
	await flush_frames(4)
	expect_eq(_stage_number(), 11, "the endless loop continues past the finished area")
	var map: Node = _world_map()
	expect(map != null and not bool(map.get("visible")), "finishing the area does not force the world map open")

	# Battle 11 is past every authored area: it writes no completion, yet the
	# position (and the unlock ceiling) still advance — that is what keeps the
	# game from deadlocking at the end of the authored content.
	await _defeat_all_enemies()
	await flush_frames(2)
	expect_eq(progress.get("completed_stages").size(), 10, "battles past the authored path write no completion")
	expect_eq(int(progress.get("current_stage_number")), 11, "the position advanced past the authored path")
	expect(int(progress.get("highest_stage_reached")) >= 11, "the unlock ceiling advanced with the position")

	await _open_map()
	var forest := _forest_view()
	var node10: Button = forest.call("get_stage_node", 10) as Button
	expect(int(node10.get_meta("stage_state")) == AreaViewScript.NodeState.COMPLETED, "the boss stage shows COMPLETED")
	expect_eq(progress.get("completed_stages").size(), 10, "all ten forest stages are completed")
	# The map must not invent a HERE marker for a stage no area authors.
	expect_eq(_here_stage_on_map(), -1, "no stage node is marked CURRENT past the authored path")
	expect_contains(_world_map().call("get_endless_text"), "ENDLESS — stage 11", "the map reports the endless position")


## The GLOBAL stage number the map currently marks HERE, or -1 when none is.
func _here_stage_on_map() -> int:
	var forest := _forest_view()
	if forest == null:
		return -1
	var database: Resource = forest.call("get_database")
	if database == null:
		return -1
	for number in range(int(database.get("first_stage")), int(database.call("get_last_stage")) + 1):
		var node: Button = forest.call("get_stage_node", number) as Button
		if node != null and int(node.get_meta("stage_state")) == AreaViewScript.NodeState.CURRENT:
			return number
	return -1
