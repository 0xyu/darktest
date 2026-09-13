class_name EquipmentDefinition
extends Resource

## Static identity and configuration shared by equipment instances.
@export var definition_id: StringName = &"equipment"
@export var display_name: String = "Equipment"
@export_enum("Weapon", "Helmet", "Armor", "Gloves", "Boots", "Ring", "Amulet") var slot: int = EquipmentSlot.WEAPON
@export_enum("Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic") var rarity: int = EquipmentRarity.COMMON
@export_range(1, 999999, 1) var item_level: int = 1
@export var base_affixes: Array[EquipmentAffix] = []
@export var unique_effect_id: StringName = &""
@export_multiline var description: String = ""
## Consumable items (e.g. potions) live in the bag as slot-less equipment.
## `slot` should stay invalid (-1) so they can never be equipped or filtered.
@export var is_consumable: bool = false
@export_range(0.0, 1.0, 0.01) var heal_ratio: float = 0.0
## Whether the Scavenger Shop's buyback book may stock this definition (gameplay-spec §19).
## Only authored, `.tres`-backed definitions can opt in: a runtime-generated definition
## (`EquipmentDefinition.new()`) has no resource path and is never stockable. Default
## false, so a new definition is never buybackable by accident.
@export var can_buy_back: bool = false


func get_slot_name() -> String:
	return EquipmentSlot.get_display_name(slot)


func get_rarity_name() -> String:
	return EquipmentRarity.get_display_name(rarity)


## Plain-Dictionary form, so a definition travels with the item that owns it.
##
## The definition is stored INLINE (fields, not a `.tres` path) because a
## generated item builds its definition at runtime (`EquipmentGenerator`) and has
## no resource path to point at. An authored `.tres` definition travels the same
## way, which keeps one code path for both — and means a saved item keeps the
## numbers it was created with instead of silently changing under a re-authored
## `.tres` file.
func to_save_data() -> Dictionary:
	var base_affix_data: Array[Dictionary] = []
	for affix in base_affixes:
		if affix != null:
			base_affix_data.append(affix.to_save_data())
	return {
		"definition_id": String(definition_id),
		"display_name": display_name,
		"slot": slot,
		"rarity": rarity,
		"item_level": item_level,
		"base_affixes": base_affix_data,
		"unique_effect_id": String(unique_effect_id),
		"description": description,
		"is_consumable": is_consumable,
		"heal_ratio": heal_ratio,
		"can_buy_back": can_buy_back,
	}


## Rebuilds a definition from [method to_save_data], or null when the payload has
## no definition id — an item whose identity cannot be named is not restored.
static func from_save_data(save_data: Dictionary) -> EquipmentDefinition:
	var saved_definition_id := String(str(save_data.get("definition_id", "")))
	if saved_definition_id.is_empty():
		return null
	var definition := EquipmentDefinition.new()
	definition.definition_id = StringName(saved_definition_id)
	definition.display_name = str(save_data.get("display_name", "Equipment"))
	definition.slot = int(save_data.get("slot", EquipmentSlot.WEAPON))
	definition.rarity = clampi(int(save_data.get("rarity", EquipmentRarity.COMMON)), EquipmentRarity.COMMON, EquipmentRarity.MYTHIC)
	definition.item_level = maxi(int(save_data.get("item_level", 1)), 1)
	definition.description = str(save_data.get("description", ""))
	definition.unique_effect_id = StringName(str(save_data.get("unique_effect_id", "")))
	definition.is_consumable = bool(save_data.get("is_consumable", false))
	definition.heal_ratio = clampf(float(save_data.get("heal_ratio", 0.0)), 0.0, 1.0)
	definition.can_buy_back = bool(save_data.get("can_buy_back", false))
	var raw_affixes: Variant = save_data.get("base_affixes", [])
	if raw_affixes is Array:
		for raw_affix in (raw_affixes as Array):
			if not (raw_affix is Dictionary):
				continue
			var affix := EquipmentAffix.from_save_data(raw_affix as Dictionary)
			if affix != null:
				definition.base_affixes.append(affix)
	return definition
