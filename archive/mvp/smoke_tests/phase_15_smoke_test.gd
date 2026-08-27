extends SceneTree

const EquipmentGeneratorResource = preload("res://scripts/systems/equipment_generator.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var generator = EquipmentGeneratorResource.new(1501)
	var expected_counts: Array[int] = [1, 2, 3, 4, 5, 5]
	for rarity in range(EquipmentRarity.COMMON, EquipmentRarity.MYTHIC + 1):
		var item = generator.generate_equipment(10, EquipmentSlot.RING, rarity)
		_expect(item.affixes.size() == expected_counts[rarity], "rarity rolls the configured number of affixes")
		var seen_stats: Dictionary = {}
		for affix in item.affixes:
			_expect(affix != null and not seen_stats.has(affix.stat_id), "one item does not roll duplicate affix stats")
			if affix != null:
				seen_stats[affix.stat_id] = true
				_expect(affix.stat_id in EquipmentAffix.get_stat_ids(), "rolled affix uses a supported stat")

	var first_generator = EquipmentGeneratorResource.new(1510)
	var second_generator = EquipmentGeneratorResource.new(1511)
	var first_item = first_generator.generate_equipment(20, EquipmentSlot.WEAPON, EquipmentRarity.RARE)
	var second_item = second_generator.generate_equipment(20, EquipmentSlot.WEAPON, EquipmentRarity.RARE)
	var items_differ: bool = false
	for affix in first_item.affixes:
		if not is_equal_approx(affix.value, second_item.get_affix_value(affix.stat_id)):
			items_differ = true
			break
	_expect(items_differ, "same-slot items can roll meaningfully different affix values")

	var low_level_generator = EquipmentGeneratorResource.new(1520)
	var high_level_generator = EquipmentGeneratorResource.new(1520)
	var low_level_item = low_level_generator.generate_equipment(1, EquipmentSlot.HELMET, EquipmentRarity.EPIC)
	var high_level_item = high_level_generator.generate_equipment(50, EquipmentSlot.HELMET, EquipmentRarity.EPIC)
	_expect(high_level_item.get_equipment_score() > low_level_item.get_equipment_score(), "affix strength increases with equipment level")

	var critical_item = EquipmentGeneratorResource.new(1530).generate_equipment(10, EquipmentSlot.AMULET, EquipmentRarity.MYTHIC)
	var has_percentage_affix: bool = false
	for affix in critical_item.affixes:
		if affix.is_percentage:
			has_percentage_affix = true
			_expect(affix.value > 0.0 and affix.value < 1.0, "percentage affixes use normalized fractional values")
	_expect(has_percentage_affix, "the affix pool includes percentage-based attributes")

	if _failures.is_empty():
		print("Phase 15 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
