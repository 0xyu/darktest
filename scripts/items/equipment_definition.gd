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
