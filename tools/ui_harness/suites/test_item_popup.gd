extends "res://tools/ui_harness/ui_harness_suite.gd"

## Headless suite for the item popup dialog (scripts/ui/item_popup.gd) driven
## through the inventory panel:
##   - equipment items: popup shows info + a side-by-side comparison (current
##     slot item left, clicked item right), and Equip equips + closes the dialog
##   - consumables (potion): popup shows a Use button (no equip/comparison), and
##     Use heals the player and removes the item
##   - Close / backdrop close the dialog
##
## Follows the same mount pattern as test_inventory_panel.gd.

const UIFixtureScript := preload("res://tests/fixtures/ui_fixture.gd")

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


func _popup() -> Control:
	return _panel_get("_item_popup") as Control


func _grid() -> Node:
	return _panel_get("_inventory_grid")


func _find_cell_where(predicate: Callable) -> Node:
	var grid := _grid()
	for index in count_cells(grid):
		var cell := find_cell(grid, index)
		if cell != null and predicate.call(cell.get("item")):
			return cell
	return null


func _potion_cell() -> Node:
	return _find_cell_where(func(item): return item != null and item.is_consumable())


func _equipment_cell() -> Node:
	return _find_cell_where(func(item): return item != null and not item.is_consumable() and not item.is_equipped)


# --- Equipment popup --------------------------------------------------------

func test_equipment_popup_shows_info_and_comparison() -> void:
	await _mount_panel_with_player()
	var cell: Node = _equipment_cell()
	expect(cell != null, "a non-equipped equipment cell exists")
	if cell == null:
		return
	var expected_item: EquipmentInstance = cell.get("item")
	click_cell(cell)
	await flush_frames()
	var popup := _popup()
	expect(popup != null and popup.visible, "clicking an equipment cell opens the popup")
	expect(popup.call("get_item") == expected_item, "popup holds the clicked item")
	var use_button: Button = popup.get("_use_button")
	var equip_button: Button = popup.get("_equip_button")
	var comparison_section: Control = popup.get("_comparison_section")
	expect(use_button != null and not use_button.visible, "use button hidden for equipment")
	expect(equip_button != null and equip_button.visible and not equip_button.disabled, "equip button shown and enabled")
	expect(comparison_section != null and comparison_section.visible, "side-by-side comparison section shown for equipment")
	var current_name: Label = popup.get("_current_name_label")
	if current_name is Label:
		expect_contains(current_name.text, "空部位", "left column shows the empty current slot")
	var clicked_name: Label = popup.get("_clicked_name_label")
	if clicked_name is Label:
		expect_contains(clicked_name.text, expected_item.get_display_name(), "right column shows the clicked item")


func test_equipment_equip_flow() -> void:
	await _mount_panel_with_player()
	var cell: Node = _equipment_cell()
	expect(cell != null, "a non-equipped equipment cell exists")
	if cell == null:
		return
	var item: EquipmentInstance = cell.get("item")
	click_cell(cell)
	await flush_frames()
	var popup := _popup()
	var equip_button: Button = popup.get("_equip_button")
	expect(not item.is_equipped, "item starts un-equipped")
	equip_button.pressed.emit()
	await flush_frames()
	expect(item.is_equipped, "equip from popup equips the item")
	expect(not popup.visible, "equip closes the popup")
	expect(popup.call("is_open") == false, "is_open reports closed after equip")


func test_equipment_comparison_shows_current_slot_item() -> void:
	await _mount_panel_with_player()
	# Equip the rare weapon first so the weapon slot has a current item.
	var rare_weapon: EquipmentInstance = null
	for item in _inventory.get_items():
		if item.get_rarity() == EquipmentRarity.RARE and item.get_slot() == EquipmentSlot.WEAPON:
			rare_weapon = item
			break
	expect(rare_weapon != null, "fixture inventory has a rare weapon")
	if rare_weapon == null:
		return
	expect(_player.equip_item(rare_weapon), "rare weapon equipped")
	var cell: Node = _find_cell_where(func(item): return item != null and item.get_slot() == EquipmentSlot.WEAPON and item != rare_weapon)
	expect(cell != null, "a second weapon cell exists")
	if cell == null:
		return
	click_cell(cell)
	await flush_frames()
	var popup := _popup()
	var current_name: Label = popup.get("_current_name_label")
	expect(current_name != null, "current item label present")
	if current_name is Label:
		expect_contains(current_name.text, rare_weapon.get_display_name(), "left column names the currently equipped item")
	var current_details: Label = popup.get("_current_details_label")
	if current_details is Label:
		expect_contains(current_details.text, "物品等级", "left column shows the current item's details")
	var comparison_label: Label = popup.get("_comparison_label")
	expect(comparison_label != null and comparison_label.visible, "comparison deltas shown when both items present")
	if comparison_label is Label:
		expect_contains(comparison_label.text, "强度", "comparison shows the strength delta")


# --- Consumable popup -------------------------------------------------------

func test_potion_popup_use_flow() -> void:
	await _mount_panel_with_player()
	# Damage the player so the potion is actually usable.
	_player.player_stats.current_hp = _player.player_stats.max_hp / 2
	await flush_frames()
	var cell: Node = _potion_cell()
	expect(cell != null, "fixture inventory has a potion")
	if cell == null:
		return
	var potion: EquipmentInstance = cell.get("item")
	var potion_count_before: int = _inventory.get_item_count()
	var hp_before: int = _player.player_stats.current_hp
	click_cell(cell)
	await flush_frames()
	var popup := _popup()
	expect(popup != null and popup.visible, "clicking the potion opens the popup")
	expect(popup.call("get_item") == potion, "popup holds the potion")
	var use_button: Button = popup.get("_use_button")
	var equip_button: Button = popup.get("_equip_button")
	expect(use_button != null and use_button.visible and not use_button.disabled, "use button shown and enabled")
	expect(equip_button != null and not equip_button.visible, "equip button hidden for consumables")
	use_button.pressed.emit()
	await flush_frames()
	expect(_player.player_stats.current_hp > hp_before, "using the potion heals the player")
	expect(_inventory.get_item_count() == potion_count_before - 1, "using the potion removes it from the bag")
	expect(not popup.visible, "popup closes after use")


func test_potion_use_disabled_at_full_hp() -> void:
	await _mount_panel_with_player()
	# The fixture character starts below max HP (equipment bonuses raise max_hp
	# after current_hp is set), so top the HP up first: the use button must then
	# be disabled.
	_player.player_stats.current_hp = _player.player_stats.max_hp
	await flush_frames()
	var cell: Node = _potion_cell()
	expect(cell != null, "fixture inventory has a potion")
	if cell == null:
		return
	click_cell(cell)
	await flush_frames()
	var use_button: Button = _popup().get("_use_button")
	expect(use_button != null and use_button.disabled, "use button disabled at full HP")


# --- Close ------------------------------------------------------------------

func test_popup_close() -> void:
	await _mount_panel_with_player()
	var cell: Node = _equipment_cell()
	expect(cell != null, "a non-equipped equipment cell exists")
	if cell == null:
		return
	click_cell(cell)
	await flush_frames()
	var popup := _popup()
	expect(popup.visible, "popup opens on click")
	var close_button: Button = popup.get("_close_button")
	close_button.pressed.emit()
	await flush_frames()
	expect(not popup.visible, "close button hides the popup")
	expect(popup.call("is_open") == false, "is_open reports closed")
