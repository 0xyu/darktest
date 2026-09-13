class_name EquipmentInstance
extends Resource

## A concrete item with its own rolled affixes and ownership state.
@export var instance_id: StringName = &""
@export var definition: EquipmentDefinition
@export var affixes: Array[EquipmentAffix] = []
@export var is_equipped: bool = false


## A FIXED item: the definition's authored affixes are copied as they are, so the
## instance carries no rolled values and every copy of the definition is identical.
## The instance id is the definition id, which is what makes such an item
## recognisable as the one-of-a-kind it is (see StageDefinition.guaranteed_loot).
static func create_from_definition(definition: EquipmentDefinition) -> EquipmentInstance:
	var instance := EquipmentInstance.new()
	if definition == null:
		return instance
	instance.definition = definition
	instance.instance_id = definition.definition_id
	for affix in definition.base_affixes:
		if affix != null:
			instance.affixes.append(affix.duplicate(true) as EquipmentAffix)
	return instance


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


## Plain-Dictionary form of the whole item: its identity, the equipped flag that
## says where it lives, the definition it was created from and the affixes it
## actually carries (see StageProgressSave).
##
## The equipped flag is part of the item's OWN state (`is_equipped`) rather than a
## slot table written beside the list, so restoring a collection restores the
## loadout with it.
func to_save_data() -> Dictionary:
	var affix_data: Array[Dictionary] = []
	for affix in affixes:
		if affix != null:
			affix_data.append(affix.to_save_data())
	return {
		"instance_id": String(instance_id),
		"is_equipped": is_equipped,
		"definition": definition.to_save_data() if definition != null else {},
		"affixes": affix_data,
	}


## Rebuilds an item from [method to_save_data], or null when the payload carries
## no usable definition — an item with no identity or stat block cannot be
## displayed, equipped, priced or scored, so it is dropped rather than restored
## as a blank "Equipment".
##
## An empty instance id falls back to the definition id, which is exactly how a
## FIXED item is identified (`create_from_definition`).
static func from_save_data(save_data: Dictionary) -> EquipmentInstance:
	var raw_definition: Variant = save_data.get("definition", {})
	if not (raw_definition is Dictionary):
		return null
	var definition := EquipmentDefinition.from_save_data(raw_definition as Dictionary)
	if definition == null:
		return null
	var instance := EquipmentInstance.new()
	instance.definition = definition
	var saved_instance_id := String(str(save_data.get("instance_id", "")))
	instance.instance_id = StringName(saved_instance_id) if not saved_instance_id.is_empty() else definition.definition_id
	instance.is_equipped = bool(save_data.get("is_equipped", false))
	var raw_affixes: Variant = save_data.get("affixes", [])
	if raw_affixes is Array:
		for raw_affix in (raw_affixes as Array):
			if not (raw_affix is Dictionary):
				continue
			var affix := EquipmentAffix.from_save_data(raw_affix as Dictionary)
			if affix != null:
				instance.affixes.append(affix)
	return instance
