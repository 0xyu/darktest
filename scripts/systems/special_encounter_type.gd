class_name SpecialEncounterType
extends RefCounted

enum {
	NONE = -1,
	ELITE,
	TREASURE_MONSTER,
	SPECIAL_MONSTER,
	RANDOM_MINI_BOSS,
	GOLD_MONSTER,
	CURSED_MONSTER,
}


static func get_display_name(encounter_type: int) -> String:
	match encounter_type:
		ELITE:
			return "Elite"
		TREASURE_MONSTER:
			return "Treasure Monster"
		SPECIAL_MONSTER:
			return "Special Monster"
		RANDOM_MINI_BOSS:
			return "Random Mini Boss"
		GOLD_MONSTER:
			return "Gold Monster"
		CURSED_MONSTER:
			return "Cursed Monster"
		_:
			return "None"
