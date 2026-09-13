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

## §12 / §3.2's roll band lives in the balance profile ([member BalanceProfile.affix_roll_min] /
## [member BalanceProfile.affix_roll_max]) so the band has ONE owner; every entry point below
## takes the profile it should roll under and falls back to the shipped default when a caller
## (headless tooling, a fixture) has none to inject.

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
## The signed base a HAND-AUTHORED affix was rebuilt from during the v3 → v4 migration
## (`docs/balance-rework-implementation.md` §9). Empty for every generated affix: it exists so a
## legacy authored value can be re-derived without being mistaken for a positive random roll, and
## it is what `source_kind` = `legacy_authored` refers to.
@export var signed_base: float = 0.0
## `""` for a rolled affix, `"legacy_authored"` for an affix the migration rebuilt from an
## authored value with no recoverable roll.
@export var source_kind: String = ""


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
		"signed_base": signed_base,
		"source_kind": source_kind,
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
	affix.signed_base = _to_float(save_data.get("signed_base"), 0.0)
	affix.source_kind = str(save_data.get("source_kind", ""))
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


## The affix base of a stat (§3.2). The three core stats take 10 % of their OWN `b_X`
## (12.12 / 5.18 / 0.50) from the profile, so one HP affix is worth the same budget as one
## attack affix; the utility bases are catalogue constants and never scale with `G`.
static func get_base_value(stat_id: StringName, profile: BalanceProfile = null) -> float:
	var active_profile: BalanceProfile = profile if profile != null else BalanceProfile.get_default()
	if stat_id in BalanceProfile.STAT_IDS:
		if active_profile == null:
			return 0.0
		return active_profile.get_base_stat(stat_id) * active_profile.affix_core_base_share
	match stat_id:
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
##
## §3.2: a CORE affix value already carries `item_scale(il)` and the aggregation adds it as a
## flat number exactly once; a utility affix never carries it, so no probability grows with the
## item level.
static func compute_value(
	stat_id: StringName,
	item_level: int,
	rarity: int,
	roll: float,
	profile: BalanceProfile = null
) -> float:
	var active_profile: BalanceProfile = profile if profile != null else BalanceProfile.get_default()
	if active_profile == null:
		return 0.0
	return BalanceFormulas.affix_value(
		active_profile,
		get_base_value(stat_id, active_profile),
		item_level,
		rarity,
		roll,
		BalanceFormulas.is_core_stat(stat_id)
	)


## The roll factor normalized to 0..1 inside the profile's band.
static func get_roll_ratio(roll: float, profile: BalanceProfile = null) -> float:
	var active_profile: BalanceProfile = profile if profile != null else BalanceProfile.get_default()
	if active_profile == null:
		return 0.5
	var span: float = active_profile.affix_roll_max - active_profile.affix_roll_min
	if is_zero_approx(span):
		return 0.5
	return clampf((roll - active_profile.affix_roll_min) / span, 0.0, 1.0)


static func roll_value(
	stat_id: StringName,
	item_level: int,
	rarity: int,
	random_number_generator: RandomNumberGenerator,
	profile: BalanceProfile = null
) -> float:
	var active_profile: BalanceProfile = profile if profile != null else BalanceProfile.get_default()
	if active_profile == null:
		return 0.0
	return compute_value(
		stat_id,
		item_level,
		rarity,
		random_number_generator.randf_range(active_profile.affix_roll_min, active_profile.affix_roll_max),
		active_profile
	)


static func create_rolled(
	stat_id: StringName,
	item_level: int,
	rarity: int,
	random_number_generator: RandomNumberGenerator,
	profile: BalanceProfile = null
) -> EquipmentAffix:
	var active_profile: BalanceProfile = profile if profile != null else BalanceProfile.get_default()
	if active_profile == null:
		return null
	var roll: float = random_number_generator.randf_range(active_profile.affix_roll_min, active_profile.affix_roll_max)
	var affix := EquipmentAffix.new()
	affix.stat_id = stat_id
	affix.value = compute_value(stat_id, item_level, rarity, roll, active_profile)
	affix.roll_ratio = get_roll_ratio(roll, active_profile)
	affix.is_percentage = is_percentage_stat(stat_id)
	affix.display_name = get_display_name_for_stat(stat_id)
	return affix
