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
	## §12 Stun affix: chance per landed hit to stun the target, which then loses
	## `StatusEffectComponent.STUN_TURNS` turn.
	STUN_CHANCE,
}

## §12's affix roll band. `roll_ratio` is a factor inside it, normalized to 0..1.
const ROLL_MIN: float = 0.80
const ROLL_MAX: float = 1.20

@export var stat_id: StringName = &"attack"
## Authored values may be negative — a cursed `HP -10` affix is a valid §12 item —
## so nothing here clamps the sign. Only rolled affixes are generated positive.
@export var value: float = 0.0
## Where this roll landed inside the affix's valid range, normalized to 0..1
## (gameplay-spec §19). Rolled affixes set it from the §12 roll factor; authored affixes
## keep the neutral 0.5. It is persisted because `value` is rounded and floored, so the
## ratio cannot be recovered from it afterwards.
@export_range(0.0, 1.0, 0.01) var roll_ratio: float = 0.5
@export var is_percentage: bool = false
## Optional. An authored affix may leave it empty and inherit the catalogue name of
## its `stat_id` instead (see `get_label()`), so a new affix cannot ship as the
## misleading default "Attack".
@export var display_name: String = ""


## Plain-Dictionary form, so a rolled affix survives a save / load round trip
## (see StageProgressSave). The numbers travel WITH the item: `value` is rounded
## and floored and `roll_ratio` is the only record of where the roll landed, so
## neither can be recomputed from the definition or the stat catalogue.
func to_save_data() -> Dictionary:
	return {
		"stat_id": String(stat_id),
		"value": value,
		"roll_ratio": roll_ratio,
		"is_percentage": is_percentage,
		"display_name": display_name,
	}


## Rebuilds an affix from [method to_save_data], or null when the payload has no
## stat id at all — a damaged entry is dropped instead of producing an affix the
## rest of the game would display and never apply.
##
## A stat id this build does not know is KEPT, because a missing number is not a
## reason to delete an item the player owns (`EquipmentAffix` authoring rejects
## unknown ids, but a save is not an authoring tool).
static func from_save_data(save_data: Dictionary) -> EquipmentAffix:
	var saved_stat_id := String(str(save_data.get("stat_id", "")))
	if saved_stat_id.is_empty():
		return null
	var affix := EquipmentAffix.new()
	affix.stat_id = StringName(saved_stat_id)
	affix.value = _to_float(save_data.get("value"), 0.0)
	affix.roll_ratio = clampf(_to_float(save_data.get("roll_ratio"), 0.5), 0.0, 1.0)
	affix.is_percentage = bool(save_data.get("is_percentage", false))
	affix.display_name = str(save_data.get("display_name", ""))
	return affix


## JSON writes every number as a float, so an int, float or numeric string all
## have to be accepted for a value slot.
static func _to_float(value: Variant, fallback: float) -> float:
	if value is float:
		return value
	if value is int:
		return float(value)
	if value is String and (value as String).is_valid_float():
		return (value as String).to_float()
	return fallback


## The label to show for this affix: the authored name when there is one, otherwise
## the catalogue name for its stat.
func get_label() -> String:
	return display_name if not display_name.is_empty() else get_display_name_for_stat(stat_id)


## Whether `stat_id` is an affix the game knows how to apply. An id outside this
## catalogue would be rolled, displayed and score-counted while never reaching
## combat, so authoring tools reject it.
static func is_known_stat(stat_id: StringName) -> bool:
	return stat_id in get_stat_ids()


## The one place an affix value becomes text, so a negative value reads correctly
## everywhere it is displayed (§12).
static func format_value(value: float, is_percentage: bool) -> String:
	if is_percentage:
		return "%+.0f%%" % (value * 100.0)
	return "%+d" % roundi(value)


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
		&"stun_chance",
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
		&"stun_chance":
			return "Stun Chance"
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
		&"stun_chance",
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
		&"stun_chance":
			return 0.35
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
		&"stun_chance":
			return 2.2
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
		&"stun_chance":
			return 0.03
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
