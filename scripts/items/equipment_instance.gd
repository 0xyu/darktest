class_name EquipmentInstance
extends Resource

## A concrete item with its own rolled affixes and ownership state.
@export var instance_id: StringName = &""
@export var definition: EquipmentDefinition
@export var affixes: Array[EquipmentAffix] = []
@export var is_equipped: bool = false


func get_rarity() -> int:
	if definition == null:
		return EquipmentRarity.COMMON
	return definition.rarity


func get_display_name() -> String:
	if definition == null:
		return "Equipment"
	return definition.display_name


func get_slot() -> int:
	if definition == null:
		return EquipmentSlot.WEAPON
	return definition.slot


func get_item_level() -> int:
	if definition == null:
		return 1
	return maxi(definition.item_level, 1)


## Consumable items (potions) can be used from the bag instead of equipped.
func is_consumable() -> bool:
	return definition != null and definition.is_consumable


func get_heal_ratio() -> float:
	if definition == null:
		return 0.0
	return definition.heal_ratio


func get_affix_value(stat_id: StringName) -> float:
	var total: float = 0.0
	for affix in affixes:
		if affix != null and affix.stat_id == stat_id:
			total += affix.value
	return total


func has_affix(stat_id: StringName) -> bool:
	for affix in affixes:
		if affix != null and affix.stat_id == stat_id:
			return true
	return false


func get_equipment_score() -> float:
	var score: float = float(get_item_level()) * (1.0 + float(get_rarity()) * 0.25)
	for affix in affixes:
		if affix != null:
			score += absf(affix.value) * (100.0 if affix.is_percentage else 1.0)
	return score
