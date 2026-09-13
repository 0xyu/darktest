extends "res://tools/ui_harness/ui_harness_suite.gd"

## Headless integration suite for the bottom navigation bar and the character
## sheet it opens.
##
## Mounts the real game scene (res://scenes/world/Main.tscn) and clicks the real
## buttons through a SYNTHESIZED MOUSE EVENT rather than emitting `pressed`
## directly. A direct signal emit only proves the [connection] entries exist;
## it cannot catch a child Control that swallows the click before the
## TextureButton sees it, which is exactly how the navigation bar was broken.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")

var _hud: Node
var _nav: Node


func suite_name() -> String:
	return "test_character_panel"


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_hud = instance.find_child("MobileCombatHUD", true, false)
	if _hud != null:
		_nav = _hud.get("_main_navigation")
	# Let stage generation, HUD refresh, and panel binding settle.
	await flush_frames(5)


## Sends a real press/release pair at the center of `control`.
func _click(control: Control, label: String) -> void:
	expect(control != null, "%s found" % label)
	if control == null:
		return
	var at: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	_tree.root.push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		_tree.root.push_input(event)
	await flush_frames(2)


func _click_nav(button_name: String) -> void:
	await _click(_nav.find_child(button_name, true, false) as Control, button_name)


## Reads the character sheet's visible text as "LABEL=VALUE" rows.
func _read_stat_rows(panel: Node) -> Dictionary:
	var rows: Dictionary = {}
	var list: Node = panel.get_node("%StatList")
	for line in list.get_children():
		var labels: Array[Node] = line.get_children()
		if labels.size() == 2:
			rows[(labels[0] as Label).text] = (labels[1] as Label).text
	return rows


func test_character_button_click_opens_character_panel() -> void:
	await _mount_game()
	expect(_hud != null, "hud mounted")
	if _hud == null:
		return
	var panel: Control = _hud.get("_character_panel")
	expect(panel != null, "character panel is present in the hud")
	if panel == null:
		return
	expect(not panel.visible, "character panel starts hidden")

	await _click_nav("CharacterBtn")
	expect(panel.visible, "clicking CharacterBtn opens the character panel")

	# The open panel covers the navigation bar, so it closes through its own CLOSE button.
	await _click(panel.get_node("%CloseButton") as Control, "character panel CLOSE button")
	expect(not panel.visible, "CLOSE button hides the character panel")

	await _click_nav("CharacterBtn")
	expect(panel.visible, "CharacterBtn re-opens the panel after closing")


func test_character_panel_lists_player_stats() -> void:
	await _mount_game()
	expect(_hud != null, "hud mounted")
	if _hud == null:
		return
	var panel: Control = _hud.get("_character_panel")
	var player: Node = _hud.get("_player")
	expect(panel != null and player != null, "panel and player are bound")
	if panel == null or player == null:
		return

	await _click_nav("CharacterBtn")
	expect(panel.visible, "panel opened via CharacterBtn")

	var stats: PlayerStats = player.player_stats
	var rows: Dictionary = _read_stat_rows(panel)
	expect(rows.size() > 0, "stat rows were built")
	expect(rows.has("ATTACK"), "ATTACK row listed")
	expect(rows.get("ATTACK", "") == str(stats.attack), "ATTACK shows the live PlayerStats value")
	expect(rows.has("MAX HP"), "MAX HP row listed")
	expect(rows.get("MAX HP", "") == str(stats.max_hp), "MAX HP shows the live PlayerStats value")
	# Ratios are rendered as whole percentages (0.05 -> 5%).
	expect(rows.get("CRITICAL CHANCE", "") == "%d%%" % roundi(stats.critical_chance * 100.0),
		"critical chance rendered as a percentage")
	var level_label: Label = panel.get_node("%LevelLabel")
	expect_contains(level_label.text, "LEVEL", "level label shows the progression level")


func test_inventory_and_shop_nav_clicks_still_work() -> void:
	await _mount_game()
	if _hud == null:
		expect(false, "hud mounted")
		return
	var inventory: Control = _hud.get("_inventory_panel")
	var shop: Control = _hud.get("_shop_panel")

	await _click_nav("InventoryBtn")
	expect(inventory.visible, "clicking InventoryBtn opens the inventory panel")

	await _click_nav("ShopBtn")
	expect(shop.visible, "clicking ShopBtn opens the shop panel")
