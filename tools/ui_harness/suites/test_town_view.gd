extends "res://tools/ui_harness/ui_harness_suite.gd"

## Headless integration suite for the town hub flow on the combat HUD.
##
## Mounts the real game scene (res://scenes/world/Main.tscn) and drives the
## DEV panel town entry -> TownView -> facility (warehouse / skill mentor)
## navigation, asserting the HUD toggles CombatView/TownView and routes each
## facility to the correct existing panel.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")

var _grid_test: Node


func suite_name() -> String:
	return "test_town_view"


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_grid_test = instance.find_child("grid_combat", true, false)
	# Let stage generation, turn start, and HUD refresh settle.
	await flush_frames(5)


func _hud() -> Node:
	return _grid_test.find_child("MobileCombatHUD", true, false)


func test_dev_entry_opens_town_and_returns() -> void:
	await _mount_game()
	var hud: Node = _hud()
	expect(hud != null, "MobileCombatHUD mounted")
	if hud == null:
		return
	var combat: Node = hud.get_node("%CombatView")
	var town: Node = hud.get_node("%TownView")
	var dev: Node = hud.get_node("%DevelopmentPanel")
	expect(combat != null and town != null and dev != null, "combat/town/dev nodes present")
	if combat == null or town == null or dev == null:
		return

	expect(bool(combat.get("visible")), "combat view visible by default")
	expect(not bool(town.get("visible")), "town view hidden by default")

	dev.call("open_town")
	await flush_frames(1)
	expect(not bool(combat.get("visible")), "dev town entry hides the combat view")
	expect(bool(town.get("visible")), "dev town entry reveals the town view")

	town.emit_signal("close_requested")
	await flush_frames(1)
	expect(not bool(town.get("visible")), "town close hides the town view")
	expect(bool(combat.get("visible")), "town close restores the combat view")


func test_town_facilities_open_correct_panels() -> void:
	await _mount_game()
	var hud: Node = _hud()
	if hud == null:
		return
	var town: Node = hud.get_node("%TownView")
	var inventory: Node = hud.get_node("%InventoryPanel")
	var skill: Node = hud.get_node("%SkillPanel")
	if town == null or inventory == null or skill == null:
		expect(false, "town/facility panels present")
		return

	# Enter the town so the facility overlays open above it.
	town.call("show")
	expect(bool(town.get("visible")), "town shown for facility test")

	expect(not bool(inventory.get("visible")), "inventory hidden before warehouse entry")
	town.emit_signal("warehouse_requested")
	await flush_frames(2)
	expect(bool(inventory.get("visible")), "warehouse entry opens the inventory panel")
	inventory.call("hide_inventory")
	await flush_frames(1)
	expect(bool(town.get("visible")), "inventory closes back to the town view")

	expect(not bool(skill.get("visible")), "skill panel hidden before mentor entry")
	town.emit_signal("skills_requested")
	await flush_frames(2)
	expect(bool(skill.get("visible")), "mentor entry opens the skill learning panel")
	skill.call("hide_panel")
	await flush_frames(1)
	expect(bool(town.get("visible")), "skill panel closes back to the town view")
