class_name EquipmentSlot
extends RefCounted

enum {
	WEAPON,
	HELMET,
	ARMOR,
	GLOVES,
	BOOTS,
	RING,
	AMULET,
}


static func get_display_name(slot: int) -> String:
	match slot:
		WEAPON:
			return "Weapon"
		HELMET:
			return "Helmet"
		ARMOR:
			return "Armor"
		GLOVES:
			return "Gloves"
		BOOTS:
			return "Boots"
		RING:
			return "Ring"
		AMULET:
			return "Amulet"
		_:
			return "Unknown Slot"


static func is_valid(slot: int) -> bool:
	return slot >= WEAPON and slot <= AMULET
