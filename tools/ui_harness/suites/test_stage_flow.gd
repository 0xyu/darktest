extends "res://tools/ui_harness/ui_harness_suite.gd"

## Phase 5 headless suite: the running combat scene (grid_combat) acting as the
## StageRouter host. Entering authored Forest stages through enter_area_stage()
## must start the right existing gameplay: COMBAT/BOSS -> a real battle at the
## matching level, TOWN -> TownView replaces CombatView, EVENT -> placeholder
## (no battle started). Unknown / un-authored stages are cleanly rejected.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")

var _grid_test: Node


func suite_name() -> String:
	return "test_stage_flow"


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


func _town_view() -> Node:
	var hud: Node = _hud()
	return hud.get_node("%TownView") if hud != null else null


func _stage_manager() -> Node:
	return _grid_test.get_node_or_null("StageManager")


func _stage_number() -> int:
	var manager: Node = _stage_manager()
	var state: Resource = manager.get("stage_state") if manager != null else null
	return int(state.get("stage_number")) if state != null else -1


func _current_stage_number() -> int:
	var progress: Resource = _grid_test.call("get_stage_progress") if _grid_test != null and _grid_test.has_method("get_stage_progress") else null
	return int(progress.get("current_stage_number")) if progress != null else -1


func test_enter_combat_stage_starts_battle() -> void:
	await _mount_game()
	var combat: Node = _combat_view()
	var town: Node = _town_view()
	expect(combat != null and town != null, "combat/town views present")
	if combat == null or town == null:
		return

	# Boot is already battle stage 1; entering the authored Forest 01 keeps the
	# scene in combat and reports the stage position on the progress object.
	expect(bool(_grid_test.call("enter_area_stage", &"forest", 1)), "enter forest 01 should succeed")
	await flush_frames(2)
	expect(_stage_number() == 1, "forest 01 should run battle level 1")
	expect(_current_stage_number() == 1, "progress current stage should be 1 after forest 01")
	expect(bool(combat.get("visible")), "combat view stays visible after a combat stage")
	expect(not bool(town.get("visible")), "town view stays hidden after a combat stage")


func test_enter_boss_stage_starts_boss_battle() -> void:
	await _mount_game()
	var combat: Node = _combat_view()
	expect(combat != null, "combat view present")
	expect(bool(_grid_test.call("enter_area_stage", &"forest", 10)), "enter forest boss 10 should succeed")
	await flush_frames(2)
	expect(_stage_number() == 10, "forest 10 (BOSS) should run battle level 10")
	expect(_current_stage_number() == 10, "progress current stage should be 10 after forest 10")
	var manager: Node = _stage_manager()
	var state: Resource = manager.get("stage_state") if manager != null else null
	expect(int(state.get("spawned_enemy_count")) > 0, "boss battle should actually spawn enemies")
	expect(bool(combat.get("visible")), "combat view stays visible for the boss battle")


func test_enter_town_stage_shows_town_and_returns() -> void:
	await _mount_game()
	var combat: Node = _combat_view()
	var town: Node = _town_view()
	expect(combat != null and town != null, "combat/town views present")
	if combat == null or town == null:
		return

	expect(not bool(town.get("visible")), "town hidden by default")
	expect(bool(_grid_test.call("enter_area_stage", &"forest", 8)), "enter forest 08 (TOWN) should succeed")
	await flush_frames(2)
	expect(_current_stage_number() == 8, "progress current stage should be 8 after forest 08")
	expect(bool(town.get("visible")), "town view shown after a town stage entry")
	expect(not bool(combat.get("visible")), "combat view hidden while the town is open")

	town.emit_signal("close_requested")
	await flush_frames(2)
	expect(not bool(town.get("visible")), "town close hides the town view")
	expect(bool(combat.get("visible")), "town close restores the combat view")


func test_enter_event_stage_is_placeholder() -> void:
	await _mount_game()
	var combat: Node = _combat_view()
	expect(combat != null, "combat view present")
	var battle_before: int = _stage_number()

	expect(bool(_grid_test.call("enter_area_stage", &"forest", 6)), "enter forest 06 (EVENT) should succeed")
	await flush_frames(2)
	expect(_current_stage_number() == 6, "progress current stage should be 6 after forest 06")
	# EVENT has no gameplay yet: it must not start a battle for stage 6.
	expect(_stage_number() == battle_before, "EVENT stage should not start a battle (battle stage unchanged)")
	expect(bool(combat.get("visible")), "combat view stays visible for the event placeholder")


func test_invalid_stages_are_rejected() -> void:
	await _mount_game()
	var progress: Resource = _grid_test.call("get_stage_progress")
	var area_before: String = String(progress.get("current_area_id"))
	expect(not bool(_grid_test.call("enter_area_stage", &"forest", 0)), "forest stage 0 should be rejected")
	expect(not bool(_grid_test.call("enter_area_stage", &"forest", 11)), "forest stage 11 (past stage_count) should be rejected")
	expect(not bool(_grid_test.call("enter_area_stage", &"swamp", 1)), "un-authored area swamp should be rejected")
	expect(_current_stage_number() == 1, "rejected entries must not change the current stage (stays at its default)")
	expect(String(progress.get("current_area_id")) == area_before, "rejected entries must not change the current area")
