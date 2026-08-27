extends SceneTree

const EquipmentGeneratorResource = preload("res://scripts/systems/equipment_generator.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var generator = EquipmentGeneratorResource.new(1401)
	var item = generator.generate_equipment(12, EquipmentSlot.WEAPON, EquipmentRarity.EPIC)
	_expect(item != null, "equipment generator creates an instance")
	_expect(item.definition != null, "equipment instance contains a definition")
	_expect(item.instance_id != &"", "equipment instance has a unique identity")
	_expect(item.definition.item_level == 12, "generated equipment preserves item level")
	_expect(item.get_slot() == EquipmentSlot.WEAPON, "generated equipment preserves its slot")
	_expect(item.get_rarity() == EquipmentRarity.EPIC, "generated equipment preserves its rarity")
	_expect(item.get_display_name() == "Epic Weapon", "generated equipment has a readable name")
	_expect(item.get_equipment_score() > 0.0, "equipment exposes a usable score")

	for slot in range(EquipmentSlot.WEAPON, EquipmentSlot.AMULET + 1):
		var slot_item = generator.generate_equipment(1, slot, EquipmentRarity.COMMON)
		_expect(slot_item.get_slot() == slot, "all equipment slots can be generated")
	for rarity in range(EquipmentRarity.COMMON, EquipmentRarity.MYTHIC + 1):
		var rarity_item = generator.generate_equipment(1, EquipmentSlot.RING, rarity)
		_expect(rarity_item.get_rarity() == rarity, "all equipment rarities can be generated")

	if _failures.is_empty():
		print("Phase 14 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
