extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var inventory := EquipmentInventory.new()
	var current := _make_item("Current Sword", EquipmentSlot.WEAPON, [
		_make_affix(&"attack", 100.0),
		_make_affix(&"hp", 200.0),
		_make_affix(&"critical_chance", 0.08),
	])
	var candidate := _make_item("New Sword", EquipmentSlot.WEAPON, [
		_make_affix(&"attack", 129.0),
		_make_affix(&"hp", 100.0),
		_make_affix(&"critical_chance", 0.12),
	])
	_expect(inventory.add_items([current, candidate]) == 2, "comparison items can be stored")
	_expect(inventory.equip_item(current), "comparison has an equipped baseline")

	var comparison: EquipmentComparison = inventory.create_comparison(candidate)
	_expect(comparison != null, "comparison object is created")
	if comparison != null:
		_expect(comparison.current_item == current, "comparison identifies current equipment")
		_expect(is_equal_approx(comparison.get_stat_delta(&"attack"), 29.0), "comparison reports positive attack delta")
		_expect(is_equal_approx(comparison.get_stat_delta(&"hp"), -100.0), "comparison reports negative HP delta")
		_expect(is_equal_approx(comparison.get_stat_delta(&"critical_chance"), 0.04), "comparison reports fractional percentage delta")
		_expect(comparison.get_changed_stat_ids().size() == 3, "comparison lists only changed stats")
		var lines: Array[String] = comparison.get_formatted_lines()
		_expect("Attack +29" in lines, "comparison formats flat stat deltas for UI")
		_expect("HP -100" in lines, "comparison formats negative stat deltas for UI")
		_expect("Critical Chance +4%" in lines, "comparison formats percentage deltas for UI")

	var dictionary_comparison: Dictionary = inventory.compare_item(candidate)
	_expect(dictionary_comparison.get("stat_rows") is Array, "dictionary comparison exposes presentation rows")
	_expect(dictionary_comparison.get("current_stats") is Dictionary, "dictionary comparison exposes current values")
	_expect(dictionary_comparison.get("candidate_stats") is Dictionary, "dictionary comparison exposes candidate values")

	if _failures.is_empty():
		print("Phase 18 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _make_item(item_name: String, slot: int, item_affixes: Array[EquipmentAffix]) -> EquipmentInstance:
	var definition := EquipmentDefinition.new()
	definition.display_name = item_name
	definition.slot = slot
	definition.rarity = EquipmentRarity.RARE
	definition.item_level = 10
	var item := EquipmentInstance.new()
	item.instance_id = StringName(item_name.to_lower().replace(" ", "_"))
	item.definition = definition
	item.affixes = item_affixes
	return item


func _make_affix(stat_id: StringName, value: float) -> EquipmentAffix:
	var affix := EquipmentAffix.new()
	affix.stat_id = stat_id
	affix.value = value
	affix.is_percentage = EquipmentAffix.is_percentage_stat(stat_id)
	affix.display_name = EquipmentAffix.get_display_name_for_stat(stat_id)
	return affix


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
