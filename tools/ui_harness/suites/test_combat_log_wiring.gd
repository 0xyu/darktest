extends "res://tools/ui_harness/ui_harness_suite.gd"

## Headless integration suite for the combat event log wiring.
##
## Mounts the real game scene (res://scenes/world/Main.tscn), drives an actual
## kill through CombatSystem.resolve_attack, and asserts the bottom-left
## CombatLogPanel records the kill + rewards through the existing signal chain
## (combat_system.actor_died -> grid_test.gd -> hud.log_event).
##
## Kept headless so it does not depend on the editor's game window being
## focused (the window freezes its main loop when backgrounded).

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")

var _grid_test: Node


func suite_name() -> String:
	return "test_combat_log_wiring"


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_grid_test = instance.find_child("GridTest", true, false)
	# Let stage generation, turn start, and HUD refresh settle.
	await flush_frames(5)


func _find_living_enemy() -> Node:
	var stage: Node = _grid_test.find_child("StageManager")
	for enemy in stage.call("get_spawned_enemies"):
		if enemy != null and is_instance_valid(enemy) and not bool(enemy.call("is_defeated")):
			return enemy
	return null


func test_kill_logs_event_end_to_end() -> void:
	await _mount_game()
	expect(_grid_test != null, "GridTest scene mounted")
	if _grid_test == null:
		return
	var player: Node = _grid_test.find_child("Player", true, false)
	var grid: Node = player.get_node(player.get("grid_path"))
	var combat: Node = _grid_test.find_child("CombatSystem")
	var hud: Node = _grid_test.find_child("MobileCombatHUD", true, false)
	var log: Node = hud.get("_combat_log")
	log.call("clear")

	var enemy: Node = _find_living_enemy()
	expect(enemy != null, "stage spawned a living enemy")
	if enemy == null:
		return

	# Put the player adjacent so attacks resolve.
	var enemy_cell: Vector2i = enemy.get("grid_position")
	grid.call("clear_occupied", player.get("grid_position"), player.get("player_id"))
	player.set("grid_position", enemy_cell + Vector2i(0, -1))
	grid.call("set_occupied", player.get("grid_position"), player.get("player_id"))
	player.set("global_position", grid.call("grid_to_world", player.get("grid_position")))

	var hits: int = 0
	while not bool(enemy.call("is_defeated")) and hits < 60:
		combat.call("resolve_attack", player, enemy)
		hits += 1
		await flush_frames(1)
	expect(bool(enemy.call("is_defeated")), "enemy defeated by player attacks")

	var has_kill: bool = false
	var kill_text: String = ""
	for entry_text in log.call("get_visible_entries"):
		if (entry_text as String).contains("Killed"):
			has_kill = true
			kill_text = entry_text as String
			break
	expect(has_kill, "kill event logged")
	expect_contains(kill_text, "EXP +", "exp amount logged")
	expect_contains(kill_text, "[color=#ffffff]", "enemy name highlighted white")
	expect_contains(kill_text, "【", "enemy name wrapped in brackets")
	expect(log.call("get_entry_count") >= 2, "kill + reward entries logged")


func test_log_hidden_when_overlay_panel_open() -> void:
	await _mount_game()
	var hud: Node = _grid_test.find_child("MobileCombatHUD", true, false)
	var log: Node = hud.get("_combat_log")
	var inventory: Node = hud.get_node("%InventoryPanel")
	expect(inventory != null, "inventory panel present")
	expect(bool(log.get("visible")), "combat log visible in combat view")
	inventory.call("show_inventory")
	await flush_frames(1)
	expect(bool(inventory.get("visible")), "inventory panel opened")
	expect(not bool(log.get("visible")), "combat log hidden while inventory open")
	inventory.call("hide_inventory")
	await flush_frames(1)
	expect(bool(log.get("visible")), "combat log visible again after inventory closes")
