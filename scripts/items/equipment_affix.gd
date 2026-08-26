class_name EquipmentAffix
extends Resource

## One rolled or configured equipment modifier.
enum Type {
	ATTACK,
	DEFENSE,
	HP,
	CRITICAL_CHANCE,
	CRITICAL_DAMAGE,
	DODGE,
	MOVEMENT,
	ATTACK_RANGE,
	LIFE_STEAL,
	DAMAGE_VS_ELITE,
	DAMAGE_VS_BOSS,
}

@export var stat_id: StringName = &"attack"
@export var value: float = 0.0
@export var is_percentage: bool = false
@export var display_name: String = "Attack"


static func get_stat_ids() -> Array[StringName]:
	return [
		&"attack",
		&"defense",
		&"hp",
		&"critical_chance",
		&"critical_damage",
		&"dodge",
		&"movement",
		&"attack_range",
		&"life_steal",
		&"damage_vs_elite",
		&"damage_vs_boss",
	]


static func get_display_name_for_stat(stat_id: StringName) -> String:
	match stat_id:
		&"attack":
			return "Attack"
		&"defense":
			return "Defense"
		&"hp":
			return "HP"
		&"critical_chance":
			return "Critical Chance"
		&"critical_damage":
			return "Critical Damage"
		&"dodge":
			return "Dodge"
		&"movement":
			return "Movement"
		&"attack_range":
			return "Attack Range"
		&"life_steal":
			return "Life Steal"
		&"damage_vs_elite":
			return "Damage vs Elite"
		&"damage_vs_boss":
			return "Damage vs Boss"
		_:
			return "Unknown Affix"


static func is_percentage_stat(stat_id: StringName) -> bool:
	return stat_id in [
		&"critical_chance",
		&"critical_damage",
		&"dodge",
		&"life_steal",
		&"damage_vs_elite",
		&"damage_vs_boss",
	]


static func get_weight(stat_id: StringName) -> float:
	match stat_id:
		&"attack", &"defense":
			return 1.2
		&"hp":
			return 1.1
		&"critical_chance":
			return 0.8
		&"critical_damage":
			return 0.7
		&"dodge":
			return 0.9
		&"movement":
			return 0.45
		&"attack_range":
			return 0.25
		&"life_steal":
			return 0.6
		&"damage_vs_elite":
			return 0.55
		&"damage_vs_boss":
			return 0.45
		_:
			return 0.0


static func get_base_value(stat_id: StringName) -> float:
	match stat_id:
		&"attack":
			return 5.0
		&"defense":
			return 4.0
		&"hp":
			return 20.0
		&"critical_chance":
			return 0.03
		&"critical_damage":
			return 0.15
		&"dodge":
			return 0.03
		&"movement":
			return 1.0
		&"attack_range":
			return 1.0
		&"life_steal":
			return 0.03
		&"damage_vs_elite", &"damage_vs_boss":
			return 0.05
		_:
			return 0.0


static func roll_value(
	stat_id: StringName,
	item_level: int,
	rarity: int,
	random_number_generator: RandomNumberGenerator
) -> float:
	var safe_level: int = maxi(item_level, 1)
	var safe_rarity: int = clampi(rarity, EquipmentRarity.COMMON, EquipmentRarity.MYTHIC)
	var level_multiplier: float = 1.0 + float(safe_level - 1) * 0.08
	var rarity_multiplier: float = 1.0 + float(safe_rarity) * 0.35
	var random_multiplier: float = random_number_generator.randf_range(0.80, 1.20)
	var rolled_value: float = get_base_value(stat_id) * level_multiplier * rarity_multiplier * random_multiplier
	if is_percentage_stat(stat_id):
		return maxf(roundf(rolled_value * 100.0) / 100.0, 0.01)
	return maxf(float(roundi(rolled_value)), 1.0)


static func create_rolled(
	stat_id: StringName,
	item_level: int,
	rarity: int,
	random_number_generator: RandomNumberGenerator
) -> EquipmentAffix:
	var affix := EquipmentAffix.new()
	affix.stat_id = stat_id
	affix.value = roll_value(stat_id, item_level, rarity, random_number_generator)
	affix.is_percentage = is_percentage_stat(stat_id)
	affix.display_name = get_display_name_for_stat(stat_id)
	return affix
