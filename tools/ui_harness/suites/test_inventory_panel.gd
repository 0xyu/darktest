extends "res://tools/ui_harness/ui_harness_suite.gd"

## Demo suite for the EquipmentInventoryPanel. Proves every harness dimension:
## Scene loading / Script presence / State / Interaction / Data Binding, plus
## two regression tests (the slot-filter feature and the inventory-rebind trap).
##
## Gotchas encoded here (see docs/ui-harness.md):
##   - UIFixture.apply_character_to_player REPLACES the inventory object, so
##     set_player(player) must be re-called on the panel afterwards.
##   - The panel frees + rebuilds all cells on every _refresh(), so cell
##     references are re-queried after any data change / click.

const UIFixtureScript := preload("res://tests/fixtures/ui_fixture.gd")
const PANEL_SCENE := preload("res://scenes/ui/EquipmentInventoryPanel.tscn")
const PANEL_SCRIPT := preload("res://scripts/ui/equipment_inventory_panel.gd")

var _player: PlayerController
var _panel: Control
var _inventory: EquipmentInventory


func _mount_panel_with_player() -> void:
	_player = PlayerController.new()
	track_node(_player)
	UIFixtureScript.apply_character_to_player(_player)
	var mounted: Node = await mount_scene("res://scenes/ui/EquipmentInventoryPanel.tscn")
	_panel = mounted as Control
	_panel.call("set_player", _player)
	_panel.call("show_inventory")
	await flush_frames(2)
	_inventory = _player.get_inventory()


func _panel_get(member: String) -> Variant:
	return _panel.get(member)


# --- Scene loading ----------------------------------------------------------

func test_scene_loads() -> void:
	expect(PANEL_SCENE != null, "inventory panel scene loads")
	if PANEL_SCENE == null:
		return
	var instance := PANEL_SCENE.instantiate()
	expect(instance is Control, "panel root is a Control")
	expect(instance.get_script() == PANEL_SCRIPT, "panel root uses equipment_inventory_panel.gd")
	instance.free()


# --- Script presence / API --------------------------------------------------

func test_public_api() -> void:
	await _mount_panel_with_player()
	for method_name in [
		"set_player", "show_inventory", "hide_inventory", "toggle_inventory",
		"select_item", "get_selected_item", "equip_selected_item", "discard_selected_item",
	]:
		expect(_panel.has_method(method_name), "panel exposes %s" % method_name)
	var has_closed_signal := false
	for signal_info in _panel.get_signal_list():
		if signal_info.get("name", "") == "panel_closed":
			has_closed_signal = true
	expect(has_closed_signal, "panel emits panel_closed")


# --- State ------------------------------------------------------------------

func test_open_close_and_selection() -> void:
	await _mount_panel_with_player()
	# The mount helper already shows the panel; verify the full show/hide cycle.
	_panel.call("hide_inventory")
	await flush_frames()
	expect(not _panel.visible, "hide_inventory hides the panel")
	_panel.call("show_inventory")
	await flush_frames()
	expect(_panel.visible, "show_inventory shows the panel")
	_panel.call("toggle_inventory")
	await flush_frames()
	expect(not _panel.visible, "toggle_inventory closes the panel")
	_panel.call("toggle_inventory")
	await flush_frames()
	expect(_panel.visible, "toggle_inventory reopens the panel")

	var items: Array = _inventory.get_items()
	expect(items.size() >= 1, "fixture inventory is not empty")
	if items.is_empty():
		return
	expect(_panel.call("select_item", items[0]), "select_item accepts a bag item")
	await flush_frames()
	expect(_panel.call("get_selected_item") == items[0], "selected item is retained")
	expect(_panel.call("equip_selected_item"), "equip_selected_item succeeds (idempotent)")
	await flush_frames()
	expect(items[0].is_equipped, "selected item is equipped after equip")
	expect(_panel.call("discard_selected_item") == false, "equipped item cannot be discarded")

	_panel.call("hide_inventory")
	await flush_frames()
	expect(not _panel.visible, "hide_inventory hides the panel")


# --- Interaction ------------------------------------------------------------

func test_cell_interaction_emit() -> void:
	await _mount_panel_with_player()
	var grid: Node = _panel_get("_inventory_grid")
	expect(count_cells(grid) >= 5, "inventory grid shows the fixture items")
	var cell: Node = find_cell(grid, 0)
	expect(cell != null, "inventory grid has a first cell")
	if cell == null:
		return
	var expected_item = cell.get("item")
	expect(expected_item != null, "first cell carries an item")
	click_cell(cell)
	await flush_frames()
	expect(_panel.call("get_selected_item") == expected_item, "clicking a cell selects its item")
	var popup: Control = _panel_get("_item_popup")
	expect(popup != null and popup.visible, "clicking a cell opens the item popup")
	if popup != null:
		expect(popup.call("get_item") == expected_item, "popup shows the clicked item")


func test_click_cell_via_synthetic_input() -> void:
	await _mount_panel_with_player()
	# Switch to the EQUIPMENT tab so the equipment grid sits high in the viewport.
	var tab_buttons: Array = _panel_get("_tab_buttons")
	if tab_buttons.size() >= 2:
		var equipment_tab: TextureButton = tab_buttons[1]
		equipment_tab.pressed.emit()
		await flush_frames()
	var grid: Node = _panel_get("_equipment_grid")
	expect(count_cells(grid) == 7, "equipment grid shows all 7 slots")
	var cell: Control = find_cell(grid, 0) as Control
	expect(cell != null and cell.get("slot") == EquipmentSlot.WEAPON, "first equipment cell is the weapon slot")
	if cell == null:
		return
	push_click(cell)
	await flush_frames()
	expect_eq(_panel_get("_filter_slot"), EquipmentSlot.WEAPON, "synthetic click routed to the slot filter")


# --- Data binding -----------------------------------------------------------

func test_data_binding() -> void:
	await _mount_panel_with_player()
	var stats: PlayerStats = _player.player_stats
	var progression: PlayerProgression = _player.player_progression
	expect_eq(_panel_get("_header_gold_label").text, _fmt_thousands(progression.gold), "gold label binds to progression.gold")
	expect_eq(_panel_get("_header_level_label").text, str(maxi(progression.level, 1)), "level label binds to progression.level")
	var power: int = roundi(stats.attack * 2.0 + stats.defense * 2.0 + stats.max_hp * 0.5)
	expect_eq(_panel_get("_header_power_label").text, _fmt_thousands(power), "power label binds to derived combat power")
	expect_eq(_panel_get("_attack_value_label").text, str(stats.attack), "attack label binds to stats.attack")
	expect_eq(_panel_get("_defense_value_label").text, str(stats.defense), "defense label binds to stats.defense")
	expect_eq(_panel_get("_hp_value_label").text, _fmt_thousands(stats.max_hp), "hp label binds to stats.max_hp")
	expect_eq(
		_panel_get("_inventory_count_label").text,
		"%d/%d" % [_inventory.get_item_count(), _inventory.capacity],
		"count label binds to the inventory",
	)


# --- Regressions ------------------------------------------------------------

func test_slot_filter_toggles() -> void:
	await _mount_panel_with_player()
	var inventory_grid: Node = _panel_get("_inventory_grid")
	var full_count: int = count_cells(inventory_grid)
	expect(full_count >= 1, "inventory grid has items before filtering")

	# Click the WEAPON slot in the equipment grid -> filter to weapon items.
	var equipment_grid: Node = _panel_get("_equipment_grid")
	var weapon_slot: Control = find_cell(equipment_grid, 0) as Control
	expect(weapon_slot != null and weapon_slot.get("slot") == EquipmentSlot.WEAPON, "equipment grid exposes the weapon slot")
	if weapon_slot == null:
		return
	click_cell(weapon_slot)
	await flush_frames()
	expect_eq(_panel_get("_filter_slot"), EquipmentSlot.WEAPON, "clicking a slot sets the filter")
	expect(_panel_get("_filter_row").visible, "filter status row is shown while filtering")
	expect_eq(count_cells(_panel_get("_inventory_grid")), 2, "item list filters to the 2 weapon items")
	expect_eq(_panel_get("_inventory_count_label").text, "2/10", "count label reflects the filtered list")

	# Toggle off by clicking the SAME slot again. The grid was rebuilt by the
	# refresh, so the cell reference MUST be re-queried.
	weapon_slot = find_cell(equipment_grid, 0) as Control
	expect(weapon_slot != null, "equipment grid exposes the weapon slot again after rebuild")
	if weapon_slot == null:
		return
	click_cell(weapon_slot)
	await flush_frames()
	expect_eq(_panel_get("_filter_slot"), -1, "clicking the active slot again clears the filter")
	expect(not _panel_get("_filter_row").visible, "filter status row hides after clearing")
	expect_eq(count_cells(_panel_get("_inventory_grid")), full_count, "item list returns to the full set")


func test_apply_character_rebind() -> void:
	await _mount_panel_with_player()
	# Fixture inventory holds 9 owned items, 2 of which are equipped; equipped
	# gear does not occupy bag slots, so the bag shows 7/10.
	expect_eq(_panel_get("_inventory_count_label").text, "7/10", "panel bound to the first fixture inventory")
	# apply_character_to_player REPLACES the inventory object, orphaning the panel.
	UIFixtureScript.apply_character_to_player(_player)
	var fresh: EquipmentInventory = _player.get_inventory()
	expect(fresh.remove_item(fresh.get_items()[0]), "one item removed from the fresh inventory")
	await flush_frames()
	expect_eq(_panel_get("_inventory_count_label").text, "7/10", "panel still reads the stale (orphaned) inventory")
	_panel.call("set_player", _player)
	await flush_frames()
	expect_eq(_panel_get("_inventory_count_label").text, "6/10", "re-binding set_player refreshes to the fresh inventory")


# --- Storage (warehouse) ----------------------------------------------------

func test_storage_section_and_withdraw() -> void:
	await _mount_panel_with_player()
	var storage: StorageInventory = _player.get_storage()
	var stored: EquipmentInstance = UIFixtureScript.create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, 12)
	expect(storage.add_item(stored), "storage accepts an item")
	await flush_frames()
	expect_eq(_panel_get("_storage_count_label").text, "1/%d" % storage.capacity, "storage count label binds to storage")
	var grid: Node = _panel_get("_storage_grid")
	expect(count_cells(grid) == 1, "storage grid shows the stored item")
	var cell: Node = find_cell(grid, 0)
	expect(cell != null and cell.get("item") == stored, "storage cell carries its item")
	click_cell(cell)
	await flush_frames()
	var popup: Control = _panel_get("_item_popup")
	expect(popup != null and popup.visible, "clicking a storage cell opens the popup")
	if popup == null:
		return
	var withdraw_button: Button = popup.get("_withdraw_button")
	expect(withdraw_button != null and withdraw_button.visible, "storage popup offers withdraw")
	withdraw_button.pressed.emit()
	await flush_frames()
	expect(storage.get_item_count() == 0, "withdraw removes the item from storage")
	expect(_player.get_inventory().has_item(stored), "withdraw moves the item into the bag")


func test_storage_pagination() -> void:
	await _mount_panel_with_player()
	var storage: StorageInventory = _player.get_storage()
	# Mirrors STORAGE_PAGE_SIZE in equipment_inventory_panel.gd.
	var page_size: int = 24
	var extra: int = 5
	for index in page_size + extra:
		storage.add_item(UIFixtureScript.create_equipment(EquipmentRarity.COMMON, EquipmentSlot.WEAPON, 1))
	await flush_frames()
	expect_eq(
		_panel_get("_storage_count_label").text,
		"%d/%d" % [page_size + extra, storage.capacity],
		"storage count shows the full total across pages",
	)
	expect(count_cells(_panel_get("_storage_grid")) == page_size, "first page shows exactly one page of items")
	var page_label: Label = _panel_get("_storage_page_label")
	expect_contains(page_label.text, "1/2", "page label reads page 1 of 2")
	var prev_button: Button = _panel_get("_storage_prev_button")
	var next_button: Button = _panel_get("_storage_next_button")
	expect(prev_button != null and prev_button.disabled, "prev disabled on the first page")
	expect(next_button != null and not next_button.disabled, "next enabled with a second page")
	next_button.pressed.emit()
	await flush_frames()
	expect(count_cells(_panel_get("_storage_grid")) == extra, "second page shows the remaining items")
	expect_contains(page_label.text, "2/2", "page label reads page 2 of 2")
	expect(prev_button != null and not prev_button.disabled, "prev enabled on the last page")
	expect(next_button != null and next_button.disabled, "next disabled on the last page")


func test_bag_grid_excludes_equipped_items() -> void:
	await _mount_panel_with_player()
	# The fixture equips Legendary gloves + Mythic ring; they must not appear in
	# the bag grid (only in the equipment section).
	var bag_cells: int = count_cells(_panel_get("_inventory_grid"))
	expect_eq(bag_cells, _player.get_inventory().get_item_count(), "bag grid matches non-equipped bag count")
	expect(bag_cells < _player.get_inventory().get_items().size(), "equipped items are excluded from the bag grid")


# ---------------------------------------------------------------------------

func _fmt_thousands(value: int) -> String:
	var text_value: String = str(maxi(value, 0))
	var formatted: String = ""
	while text_value.length() > 3:
		formatted = "," + text_value.substr(text_value.length() - 3, 3) + formatted
		text_value = text_value.substr(0, text_value.length() - 3)
	return text_value + formatted
