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
