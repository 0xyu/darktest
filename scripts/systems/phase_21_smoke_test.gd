extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var hud_scene := load("res://scenes/ui/MobileCombatHUD.tscn") as PackedScene
	_expect(hud_scene != null, "combat HUD scene can be loaded")
	if hud_scene == null:
		_quit_with_result()
		return
	var hud := hud_scene.instantiate()
	root.add_child(hud)
	var presentation := hud.get_node("Root/LootPresentation") as LootPresentation
	_expect(presentation != null, "HUD contains a loot presentation component")
	if presentation == null:
		_quit_with_result()
		return
	presentation.presentation_speed_scale = 0.05
	await process_frame

	var common := _make_item("Ashen Blade", EquipmentRarity.COMMON)
	var mythic := _make_item("Crown of Dusk", EquipmentRarity.MYTHIC)
	presentation.present_loot([common, mythic], [mythic], "Test Chest")
	_expect(presentation.is_presenting(), "loot presentation starts immediately")
	_expect(presentation.get_pending_count() == 1, "additional loot is queued")

	for _frame in range(180):
		await process_frame
		if not presentation.is_presenting() and presentation.get_pending_count() == 0:
			break

	_expect(presentation.get_last_revealed_item() == mythic, "queued Mythic item is revealed")
	_expect(presentation.was_last_revealed_new_best(), "new best indicator is retained for the revealed item")
	_expect(not presentation.is_presenting(), "loot presentation finishes without blocking")

	hud.free()
	await process_frame
	if _failures.is_empty():
		print("Phase 21 smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _quit_with_result() -> void:
	quit(0 if _failures.is_empty() else 1)


func _make_item(item_name: String, rarity: int) -> EquipmentInstance:
	var definition := EquipmentDefinition.new()
	definition.display_name = item_name
	definition.rarity = rarity
	definition.slot = EquipmentSlot.WEAPON
	definition.item_level = 20
	var item := EquipmentInstance.new()
	item.instance_id = StringName(item_name.to_lower().replace(" ", "_"))
	item.definition = definition
	return item


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
