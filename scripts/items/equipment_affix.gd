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

## §12's affix roll band. `roll_ratio` is a factor inside it, normalized to 0..1.
const ROLL_MIN: float = 0.80
const ROLL_MAX: float = 1.20

@export var stat_id: StringName = &"attack"
@export var value: float = 0.0
## Where this roll landed inside the affix's valid range, normalized to 0..1
## (gameplay-spec §19). Rolled affixes set it from the §12 roll factor; authored affixes
## keep the neutral 0.5. It is persisted because `value` is rounded and floored, so the
## ratio cannot be recovered from it afterwards.
@export_range(0.0, 1.0, 0.01) var roll_ratio: float = 0.5
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


## The affix's economic weight (gameplay-spec §19): economic desirability, NOT combat
## strength. It deliberately disagrees with `get_weight()`, which is the combat roll
## weight — a rare, build-defining affix is worth more than a common one.
static func get_economic_weight(stat_id: StringName) -> float:
	match stat_id:
		&"attack":
			return 1.0
		&"defense":
			return 0.9
		&"hp":
			return 0.8
		&"critical_chance":
			return 1.5
		&"critical_damage":
			return 1.4
		&"dodge":
			return 1.3
		&"movement":
			return 2.5
		&"attack_range":
			return 2.0
		&"life_steal":
			return 2.0
		&"damage_vs_elite":
			return 1.5
		&"damage_vs_boss":
			return 1.8
		_:
			return 0.0


## The mean economic weight over every affix — the reference point the §19 calibration
## means are derived from.
static func get_economic_weight_mean() -> float:
	var stat_ids: Array[StringName] = get_stat_ids()
	if stat_ids.is_empty():
		return 0.0
	var total: float = 0.0
	for stat_id in stat_ids:
		total += get_economic_weight(stat_id)
	return total / float(stat_ids.size())


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


## The affix value for a known roll factor. Split out of `roll_value()` so that
## `create_rolled()` can keep the factor it drew — the ratio is derived from that factor
## and must not be re-rolled to recover it.
static func compute_value(
	stat_id: StringName,
	item_level: int,
	rarity: int,
	roll: float
) -> float:
	var safe_level: int = maxi(item_level, 1)
	var safe_rarity: int = clampi(rarity, EquipmentRarity.COMMON, EquipmentRarity.MYTHIC)
	var level_multiplier: float = 1.0 + float(safe_level - 1) * 0.08
	var rarity_multiplier: float = 1.0 + float(safe_rarity) * 0.35
	var rolled_value: float = get_base_value(stat_id) * level_multiplier * rarity_multiplier * roll
	if is_percentage_stat(stat_id):
		return maxf(roundf(rolled_value * 100.0) / 100.0, 0.01)
	return maxf(float(roundi(rolled_value)), 1.0)


## The roll factor normalized to 0..1. The range is the one valid at the item's own level
## and rarity, because both feed `compute_value()` — so the ratio stays comparable across
## rarities instead of tracking the rarity multiplier a second time.
static func get_roll_ratio(roll: float) -> float:
	return clampf((roll - ROLL_MIN) / (ROLL_MAX - ROLL_MIN), 0.0, 1.0)


static func roll_value(
	stat_id: StringName,
	item_level: int,
	rarity: int,
	random_number_generator: RandomNumberGenerator
) -> float:
	return compute_value(
		stat_id,
		item_level,
		rarity,
		random_number_generator.randf_range(ROLL_MIN, ROLL_MAX)
	)


static func create_rolled(
	stat_id: StringName,
	item_level: int,
	rarity: int,
	random_number_generator: RandomNumberGenerator
) -> EquipmentAffix:
	var roll: float = random_number_generator.randf_range(ROLL_MIN, ROLL_MAX)
	var affix := EquipmentAffix.new()
	affix.stat_id = stat_id
	affix.value = compute_value(stat_id, item_level, rarity, roll)
	affix.roll_ratio = get_roll_ratio(roll)
	affix.is_percentage = is_percentage_stat(stat_id)
	affix.display_name = get_display_name_for_stat(stat_id)
	return affix
