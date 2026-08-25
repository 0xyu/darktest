class_name EquipmentRarity
extends RefCounted

enum {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
	MYTHIC,
}


static func affix_count(rarity: int) -> int:
	match rarity:
		EquipmentRarity.COMMON:
			return 1
		EquipmentRarity.UNCOMMON:
			return 2
		EquipmentRarity.RARE:
			return 3
		EquipmentRarity.EPIC:
			return 4
		EquipmentRarity.LEGENDARY, EquipmentRarity.MYTHIC:
			return 5
		_:
			return 1
