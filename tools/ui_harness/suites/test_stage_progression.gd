extends "res://tools/ui_harness/ui_harness_suite.gd"

## Phase 7 headless suite: the authored stage completion / return flow.
##
## Loop under test:
##   WorldMap → Stage → Gameplay → Complete (PlayerProgress) → unlock next → map
##
## Battle stages (COMBAT/BOSS) complete when their authored battle clears; TOWN
## and EVENT (placeholder) stages complete on entry (the visit IS the clear, so
## the linear unlock chain can advance). Completing the final stage of an area
## finishes it. The endless default boot battle NEVER writes progress and keeps
## advancing battles exactly as before.

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


func _enter_typed_stage(area_id: StringName, stage_number: int) -> void:
	_grid_test.call("enter_area_stage", area_id, stage_number)
	await flush_frames(3)


func _click_map_node(stage_number: int) -> void:
	var forest := _forest_view()
	var node: Button = forest.call("get_stage_node", stage_number) as Button
	expect(node != null, "map node %d exists before click" % stage_number)
	if node != null:
		node.pressed.emit()
	await flush_frames(3)


# --- Tests ---------------------------------------------------------------

func test_typed_battle_clear_records_completion_and_returns_to_map() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	await _enter_typed_stage(&"forest", 1)
	await _defeat_all_enemies()

	expect(bool(progress.call("is_stage_completed", &"forest", 1)), "clearing authored forest 01 records the completion")
	expect(bool(progress.call("is_stage_unlocked", &"forest", 2)), "clearing stage 1 unlocks stage 2")
	expect_contains(_status_text(), "AREA FOREST", "typed clear status names the area")
	expect_contains(_status_text(), "STAGE 02 (COMBAT) UNLOCKED", "typed clear status reports the next authored stage from data")

	# Manual free-roam victory: reaching the exit and pressing NEXT STAGE must
	# return to the refreshed world map, not start an endless battle 2.
	await _place_player(Vector2i(10, 3))
	_hud().emit_signal("next_stage_requested")
	await flush_frames(4)
	var map: Node = _world_map()
	var combat: Node = _combat_view()
	expect(map != null and bool(map.get("visible")), "exit after a typed clear returns to the world map")
	expect(combat != null and not bool(combat.get("visible")), "combat view hidden behind the world map")
	expect_eq(_stage_number(), 1, "no endless battle 2 was started by the exit")
	expect(bool(progress.call("is_stage_completed", &"forest", 1)), "completion survives the return to the map")

	var forest := _forest_view()
	var node2: Button = forest.call("get_stage_node", 2) as Button
	expect(node2 != null and not bool(node2.disabled), "stage 2 is AVAILABLE on the refreshed map")
	var node1: Button = forest.call("get_stage_node", 1) as Button
	expect(int(node1.get_meta("stage_state")) == AreaViewScript.NodeState.COMPLETED, "cleared stage 1 shows COMPLETED")


func test_mid_path_clear_unlocks_next_authored_type_from_data() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	# 06 is authored EVENT; the unlock text must come from StageDatabase, not a
	# hard-coded rule ("完成 05 → 06 unlocked（类型=EVENT，由 stage_type 决定）").
	for number in range(1, 5):
		progress.call("complete_stage", &"forest", number)
	await _enter_typed_stage(&"forest", 5)
	await _defeat_all_enemies()

	expect(bool(progress.call("is_stage_completed", &"forest", 5)), "clearing forest 05 records the completion")
	expect(bool(progress.call("is_stage_unlocked", &"forest", 6)), "clearing stage 5 unlocks stage 6")
	expect_contains(_status_text(), "STAGE 06 (EVENT) UNLOCKED", "the authored EVENT type is reported for the next stage")


func test_map_entry_to_town_counts_as_completed_and_closes_back_to_map() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 8):
		progress.call("complete_stage", &"forest", number)

	await _open_map()
	await _click_map_node(8)
	var town: Node = _town_view()
	var combat: Node = _combat_view()
	expect(town != null and bool(town.get("visible")), "clicking the town stage opens the town view")
	expect(combat != null and not bool(combat.get("visible")), "combat view hidden while the town is open")
	expect(bool(progress.call("is_stage_completed", &"forest", 8)), "entering the town stage counts as completed")
	expect(bool(progress.call("is_stage_unlocked", &"forest", 9)), "the town visit unlocks stage 9")

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


func test_event_visit_from_map_completes_and_stays_on_map() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 6):
		progress.call("complete_stage", &"forest", number)

	await _open_map()
	await _click_map_node(6)
	var map: Node = _world_map()
	var combat: Node = _combat_view()
	expect(map != null and bool(map.get("visible")), "an EVENT (placeholder) visit keeps the world map open")
	expect(combat != null and not bool(combat.get("visible")), "combat view stays hidden for the event visit")
	expect(bool(progress.call("is_stage_completed", &"forest", 6)), "the event visit counts as completed")
	expect(bool(progress.call("is_stage_unlocked", &"forest", 7)), "the event visit unlocks stage 7")

	var forest := _forest_view()
	var node7: Button = forest.call("get_stage_node", 7) as Button
	expect(node7 != null and not bool(node7.disabled), "stage 7 is AVAILABLE on the refreshed map")
	var node6: Button = forest.call("get_stage_node", 6) as Button
	expect(int(node6.get_meta("stage_state")) == AreaViewScript.NodeState.COMPLETED, "visited event stage shows COMPLETED")


func test_direct_typed_town_visit_closes_back_to_combat() -> void:
	# DEV / direct typed town entries keep the classic close behavior: back to
	# the combat view (only map-origin visits return to the map).
	await _mount_game()
	var progress: Resource = _progress()
	await _enter_typed_stage(&"forest", 8)
	var town: Node = _town_view()
	var combat: Node = _combat_view()
	expect(town != null and bool(town.get("visible")), "typed town entry opens the town view")
	expect(bool(progress.call("is_stage_completed", &"forest", 8)), "a direct typed town visit also counts as completed")

	town.emit_signal("close_requested")
	await flush_frames(4)
	expect(not bool(town.get("visible")), "town hidden after close")
	expect(combat != null and bool(combat.get("visible")), "direct typed town close restores the combat view")
	var map: Node = _world_map()
	expect(map != null and not bool(map.get("visible")), "no world map shown for a direct typed town close")


func test_endless_boot_clear_writes_no_progress_and_still_advances() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	await _defeat_all_enemies()
	expect_eq(int(progress.call("get_current_stage")["stage_number"]), 1, "boot battle is battle level 1 (never typed)")
	expect(progress.get("completed_stages").is_empty(), "endless boot clears must not write authored progress")

	await _place_player(Vector2i(10, 3))
	_hud().emit_signal("next_stage_requested")
	await flush_frames(6)
	expect_eq(_stage_number(), 2, "the endless loop still advances to battle 2 from the exit")
	expect(progress.get("completed_stages").is_empty(), "endless battle 2 clear path never touches authored progress")
	var map: Node = _world_map()
	expect(map != null and not bool(map.get("visible")), "endless advance does not open the world map")


func test_farming_on_typed_stage_records_once_and_stays() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	_auto().call("set_farming_enabled", true)
	await _enter_typed_stage(&"forest", 1)
	await _defeat_all_enemies()
	# FARMING re-spawns the same authored stage; the first clear records the
	# completion and later re-clears are idempotent (one dictionary key).
	await flush_frames(16)
	expect_eq(_stage_number(), 1, "farming stays on the typed stage")
	expect_eq(progress.get("completed_stages").size(), 1, "farming re-clears keep a single completion record")

	await _defeat_all_enemies()
	await flush_frames(4)
	expect_eq(progress.get("completed_stages").size(), 1, "second farming clear does not duplicate the completion")
	expect(bool(progress.call("is_stage_completed", &"forest", 1)), "typed farming clear recorded forest 01")


func test_boss_clear_finishes_the_area() -> void:
	await _mount_game()
	var progress: Resource = _progress()
	for number in range(1, 10):
		progress.call("complete_stage", &"forest", number)

	await _open_map()
	await _click_map_node(10)
	await _defeat_all_enemies()
	expect(bool(progress.call("is_stage_completed", &"forest", 10)), "clearing the authored BOSS stage records the completion")
	expect_contains(_status_text(), "AREA FOREST COMPLETE (10/10)", "final stage clear reports the area is complete")

	await _place_player(Vector2i(10, 3))
	_hud().emit_signal("next_stage_requested")
	await flush_frames(4)
	var map: Node = _world_map()
	expect(map != null and bool(map.get("visible")), "clearing the final stage returns to the world map")
	var forest := _forest_view()
	var node10: Button = forest.call("get_stage_node", 10) as Button
	expect(int(node10.get_meta("stage_state")) == AreaViewScript.NodeState.COMPLETED, "the boss stage shows COMPLETED")
	expect_eq(progress.get("completed_stages").size(), 10, "all ten forest stages are completed")
