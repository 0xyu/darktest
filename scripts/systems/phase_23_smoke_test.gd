extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var main_scene := load("res://scenes/world/Main.tscn") as PackedScene
	_expect(main_scene != null, "main scene can be loaded")
	if main_scene == null:
		_quit_with_result()
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var game := main.get_node("GridTest") as GridTest
	var panel := game.hud.get_node("Root/InventoryPanel") as EquipmentInventoryPanel
	_expect(panel != null, "combat HUD contains the inventory panel")
	if panel == null:
		_quit_with_result()
		return

	var weapon := _make_item("Duskbrand", 120.0)
	_expect(game.player.add_equipment(weapon), "equipment can be added to inventory")
	panel.show_inventory()
	await process_frame
	_expect(panel.visible, "inventory panel opens")
	_expect("1 /" in panel.get_node("Panel/Margin/Content/InventoryCount").text, "inventory count is displayed")
	_expect(panel.get_node("Panel/Margin/Content/EquippedGrid").get_child_count() == 7, "all equipment slots are displayed")
	_expect(panel.get_node("Panel/Margin/Content/InventoryScroll/InventoryGrid").get_child_count() == 1, "inventory grid displays stored equipment")
	var inventory_button := panel.get_node("Panel/Margin/Content/InventoryScroll/InventoryGrid").get_child(0) as Button
	inventory_button.pressed.emit()
	await process_frame
	_expect(panel.get_selected_item() == weapon, "clicking an inventory item is safe")

	_expect(panel.select_item(weapon), "inventory item can be selected")
	await process_frame
	_expect(panel.get_selected_item() == weapon, "selected equipment is retained")
	_expect("Duskbrand" in panel.get_node("Panel/Margin/Content/DetailsPanel/DetailsMargin/Details/ItemName").text, "item details display the selected equipment")
	_expect("Attack" in panel.get_node("Panel/Margin/Content/DetailsPanel/DetailsMargin/Details/ItemDetails").text, "item details display affixes")
	_expect("EMPTY SLOT" in panel.get_node("Panel/Margin/Content/DetailsPanel/DetailsMargin/Details/ComparisonLabel").text, "comparison displays the empty slot baseline")
	_expect(panel.equip_selected_item() and weapon.is_equipped, "selected equipment can be equipped")

	var spare := _make_item("Grave Charm", 3.0)
	_expect(game.player.add_equipment(spare), "a second item can be added")
	_expect(panel.select_item(spare), "second item can be selected")
	_expect(panel.discard_selected_item(), "selected unequipped item can be discarded")
	_expect(not game.player.get_inventory().has_item(spare), "discard removes the selected item")

	panel.hide_inventory()
	_expect(not panel.visible, "inventory panel closes")
	main.free()
	await process_frame
	if _failures.is_empty():
		print("Phase 23 smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	_quit_with_result()


func _make_item(item_name: String, attack_value: float) -> EquipmentInstance:
	var definition := EquipmentDefinition.new()
	definition.display_name = item_name
	definition.slot = EquipmentSlot.WEAPON
	definition.rarity = EquipmentRarity.RARE
	definition.item_level = 12
	var affix := EquipmentAffix.new()
	affix.stat_id = &"attack"
	affix.value = attack_value
	affix.display_name = "Attack"
	var item := EquipmentInstance.new()
	item.instance_id = StringName(item_name.to_lower().replace(" ", "_"))
	item.definition = definition
	item.affixes = [affix]
	return item


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)


func _quit_with_result() -> void:
	quit(0 if _failures.is_empty() else 1)
