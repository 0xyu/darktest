extends SceneTree

const EquipmentGeneratorResource = preload("res://scripts/systems/equipment_generator.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var generator := EquipmentGeneratorResource.new(1701)
	var inventory := EquipmentInventory.new()
	inventory.capacity = 3
	var weapon := generator.generate_equipment(10, EquipmentSlot.WEAPON, EquipmentRarity.RARE)
	var replacement := generator.generate_equipment(12, EquipmentSlot.WEAPON, EquipmentRarity.EPIC)
	var helmet := generator.generate_equipment(10, EquipmentSlot.HELMET, EquipmentRarity.UNCOMMON)
	var boots := generator.generate_equipment(10, EquipmentSlot.BOOTS, EquipmentRarity.COMMON)

	_expect(inventory.add_item(weapon), "inventory accepts equipment")
	_expect(inventory.add_items([replacement, helmet]) == 2, "inventory accepts multiple equipment items")
	_expect(not inventory.add_item(boots), "inventory enforces capacity")
	_expect(inventory.equip_item(weapon), "inventory equips an owned item")
	_expect(inventory.get_equipped_item(EquipmentSlot.WEAPON) == weapon, "equipped item is available by slot")
	_expect(weapon.is_equipped, "equipped item records its state")
	_expect(inventory.equip_item(replacement), "inventory replaces an equipped item")
	_expect(not weapon.is_equipped and replacement.is_equipped, "replacing an item clears the previous equipped state")
	_expect(inventory.get_equipped_item(EquipmentSlot.WEAPON) == replacement, "slot points to the replacement")

	var comparison: Dictionary = inventory.compare_item(weapon)
	_expect(comparison.get("current_item") == replacement, "comparison identifies the current slot item")
	_expect(comparison.get("stat_deltas") is Dictionary, "comparison exposes per-stat deltas")
	_expect((comparison.get("stat_deltas") as Dictionary).has(&"attack"), "comparison includes supported stat keys")
	_expect(inventory.select_item(helmet), "inventory selects an owned item")
	_expect(inventory.get_selected_item() == helmet, "selected item is readable")
	_expect(inventory.unequip_item(EquipmentSlot.WEAPON) == replacement, "inventory unequips by slot")
	_expect(not replacement.is_equipped, "unequipped item clears its state")
	_expect(inventory.equip_item(replacement), "inventory can equip the replacement again")
	_expect(not inventory.discard_item(replacement), "equipped items cannot be discarded")
	_expect(inventory.unequip_item(EquipmentSlot.WEAPON) == replacement, "inventory can unequip before discarding")
	_expect(inventory.discard_item(helmet), "inventory discards an unequipped item")
	_expect(inventory.get_item_count() == 2, "discard removes the item from ownership")

	var player := PlayerController.new()
	player.player_stats = PlayerStats.new()
	player.set_equipment_inventory(EquipmentInventory.new())
	var stat_item := generator.generate_equipment(1, EquipmentSlot.GLOVES, EquipmentRarity.COMMON)
	var attack_affix := EquipmentAffix.new()
	attack_affix.stat_id = &"attack"
	attack_affix.value = 25.0
	stat_item.affixes = [attack_affix]
	_expect(player.add_equipment(stat_item), "player accepts equipment into its inventory")
	_expect(player.equip_item(stat_item), "player equips inventory equipment")
	_expect(player.player_stats.attack == 35, "equipping applies ordinary stat affixes")
	_expect(player.get_equipped_item(EquipmentSlot.GLOVES) == stat_item, "player exposes equipped items by slot")
	_expect(player.unequip_item(EquipmentSlot.GLOVES) == stat_item, "player unequips equipment")
	_expect(player.player_stats.attack == 10, "unequipping removes ordinary stat affixes")
	player.free()

	if _failures.is_empty():
		print("Phase 17 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
