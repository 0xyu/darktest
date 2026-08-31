class_name SubHeroData
extends Resource

## Shared, immutable content definition for one Sub Hero type.
##
## Mutable progression belongs to SubHeroInstance. Keeping these separate
## allows one definition to be referenced by many owned instances.
@export var id: StringName = &"sub_hero"
@export var display_name: String = "Sub Hero"
@export_enum("Common", "Rare", "Legendary") var quality: int = SubHeroQuality.COMMON
@export_range(1, 999999, 1) var attack_damage: int = 10
@export_range(0.1, 60.0, 0.1) var attack_interval: float = 2.0
@export_enum("Lowest HP", "Boss First", "Closest to Defeat") var target_rule: int = SubHeroTargetRule.LOWEST_HP
@export var unique_effect: SubHeroEffect
@export var tags: Array[StringName] = []
@export var portrait: Texture2D


func is_valid() -> bool:
	return not id.is_empty() \
		and not display_name.is_empty() \
		and SubHeroQuality.is_valid(quality) \
		and attack_damage >= 1 \
		and attack_interval > 0.0 \
		and SubHeroTargetRule.is_valid(target_rule)


func has_tag(tag: StringName) -> bool:
	return tag in tags
