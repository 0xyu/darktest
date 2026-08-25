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
