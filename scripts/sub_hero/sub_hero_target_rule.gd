class_name SubHeroTargetRule
extends RefCounted

## Targeting is kept in data so future Sub Heroes can opt into boss-focused
## behavior without changing the combat manager's data contract.
enum {
	LOWEST_HP,
	BOSS_FIRST,
	CLOSEST_TO_DEFEAT,
}


static func get_display_name(rule: int) -> String:
	match rule:
		LOWEST_HP:
			return "Lowest HP"
		BOSS_FIRST:
			return "Boss First"
		CLOSEST_TO_DEFEAT:
			return "Closest to Defeat"
		_:
			return "Lowest HP"


static func is_valid(rule: int) -> bool:
	return rule >= LOWEST_HP and rule <= CLOSEST_TO_DEFEAT
