class_name LootTable
extends Resource

## Configurable equipment-drop rules for one encounter category.
@export var table_id: StringName = &"normal"
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.25
@export_range(0, 99, 1) var guaranteed_drop_count: int = 0
@export_range(0, 99, 1) var max_drop_count: int = 1
@export_range(0, 5, 1) var minimum_rarity: int = EquipmentRarity.COMMON
@export var rarity_weights: Dictionary = {}


func roll_rarity(random_number_generator: RandomNumberGenerator) -> int:
	var total_weight: float = 0.0
	var available_rarities: Array[int] = []
	for rarity in range(minimum_rarity, EquipmentRarity.MYTHIC + 1):
		var weight: float = maxf(float(rarity_weights.get(rarity, 0.0)), 0.0)
		if weight <= 0.0:
			continue
		available_rarities.append(rarity)
		total_weight += weight
	if available_rarities.is_empty() or total_weight <= 0.0:
		return clampi(minimum_rarity, EquipmentRarity.COMMON, EquipmentRarity.MYTHIC)

	var roll: float = random_number_generator.randf_range(0.0, total_weight)
	var cumulative_weight: float = 0.0
	for rarity in available_rarities:
		cumulative_weight += maxf(float(rarity_weights.get(rarity, 0.0)), 0.0)
		if roll <= cumulative_weight:
			return rarity
	return available_rarities.back()


func get_total_weight() -> float:
	var total_weight: float = 0.0
	for rarity in range(minimum_rarity, EquipmentRarity.MYTHIC + 1):
		total_weight += maxf(float(rarity_weights.get(rarity, 0.0)), 0.0)
	return total_weight


static func create_normal() -> LootTable:
	return _create_table(
		&"normal",
		0.25,
		0,
		1,
		EquipmentRarity.COMMON,
		{EquipmentRarity.COMMON: 60.0, EquipmentRarity.UNCOMMON: 25.0, EquipmentRarity.RARE: 10.0, EquipmentRarity.EPIC: 4.0, EquipmentRarity.LEGENDARY: 1.0, EquipmentRarity.MYTHIC: 0.0}
	)


static func create_elite() -> LootTable:
	return _create_table(
		&"elite",
		0.50,
		0,
		1,
		EquipmentRarity.UNCOMMON,
		{EquipmentRarity.COMMON: 0.0, EquipmentRarity.UNCOMMON: 45.0, EquipmentRarity.RARE: 35.0, EquipmentRarity.EPIC: 15.0, EquipmentRarity.LEGENDARY: 5.0, EquipmentRarity.MYTHIC: 0.0}
	)


static func create_special() -> LootTable:
	return _create_table(
		&"special",
		0.75,
		0,
		1,
		EquipmentRarity.RARE,
		{EquipmentRarity.COMMON: 0.0, EquipmentRarity.UNCOMMON: 20.0, EquipmentRarity.RARE: 40.0, EquipmentRarity.EPIC: 30.0, EquipmentRarity.LEGENDARY: 10.0, EquipmentRarity.MYTHIC: 0.0}
	)


static func create_mini_boss() -> LootTable:
	return _create_table(
		&"mini_boss",
		1.0,
		1,
		1,
		EquipmentRarity.RARE,
		{EquipmentRarity.COMMON: 0.0, EquipmentRarity.UNCOMMON: 0.0, EquipmentRarity.RARE: 55.0, EquipmentRarity.EPIC: 30.0, EquipmentRarity.LEGENDARY: 13.0, EquipmentRarity.MYTHIC: 2.0}
	)


static func _create_table(
	table_id_value: StringName,
	drop_chance_value: float,
	guaranteed_drop_count_value: int,
	max_drop_count_value: int,
	minimum_rarity_value: int,
	rarity_weights_value: Dictionary
) -> LootTable:
	var table := LootTable.new()
	table.table_id = table_id_value
	table.drop_chance = drop_chance_value
	table.guaranteed_drop_count = guaranteed_drop_count_value
	table.max_drop_count = max_drop_count_value
	table.minimum_rarity = minimum_rarity_value
	table.rarity_weights = rarity_weights_value
	return table
