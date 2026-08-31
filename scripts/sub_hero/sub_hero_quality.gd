class_name SubHeroQuality
extends RefCounted

## Initial Sub Hero quality tiers. These are intentionally separate from
## EquipmentRarity because Sub Heroes have their own three-tier progression.
enum {
	COMMON,
	RARE,
	LEGENDARY,
}


static func get_display_name(quality: int) -> String:
	match quality:
		COMMON:
			return "Common"
		RARE:
			return "Rare"
		LEGENDARY:
			return "Legendary"
		_:
			return "Unknown Quality"


static func get_color(quality: int) -> Color:
	match quality:
		COMMON:
			return Color("#e8e8e8")
		RARE:
			return Color("#c56cff")
		LEGENDARY:
			return Color("#ffc64d")
		_:
			return Color.WHITE


static func is_valid(quality: int) -> bool:
	return quality >= COMMON and quality <= LEGENDARY
