class_name BalanceMigrationV4
extends RefCounted

## The v3 → v4 player-save migration (`docs/balance-rework-implementation.md` §9).
##
## Why this is its own object: the conversion reads the OLD formulas and must keep reading them
## after every live consumer has switched to the v4 ones. A formula that exists only to interpret a
## save written by a previous build cannot live in [PlayerProgression] or [EquipmentAffix] — those
## are the v4 implementations now, and a future refactor of them must not silently change how a
## three-year-old save is read.
##
## The conversion is PURE: it takes a loaded payload and returns a converted payload plus the
## audit rows, and it never touches the filesystem, the scene tree or the live player state. The
## owner of the save file ([StageProgressSave]) is the one that writes the backup, the temporary
## file and the atomic replacement, so a caller can run the whole conversion in memory and abandon
## it without a half-written save.
##
## What is preserved, per §9:
##   * level, skill points, skill levels and character identity — the panel is rebuilt from them
##   * the level's EXP as a FRACTION of the level's requirement, not as an absolute number
##   * approximate Gold PURCHASING POWER in the services and items of the highest unlocked stage
##   * item id, slot, item level, rarity, affix stat ids, rolls and unique effects — never a re-roll
##   * Sub Hero identity, level and duplicate count; the investment coordinate and the price are
##     rebuilt rather than stored
##
## What is deliberately NOT claimed: an absolute-stat affix from the old scale cannot be "kept
## unchanged" (§9). The old scale can outgrow the new economy, so an old-authored `+40 attack` must
## be re-derived from the authored definition (or from its own old level multiplier) and then
## re-expressed in the v4 scale. Carrying it through untouched is exactly the failure mode §9
## warns about.

## The format version that predates the v4 balance. A payload at this version (or normalized up to
## it from v1/v2) is converted exactly once.
const LEGACY_VERSION: int = 3
## The format version this migration produces.
const TARGET_VERSION: int = 4
## §5: the level requirement rate of the LEGACY curve, `need_old = round(100 * 1.15^(L-1))`.
const LEGACY_EXP_BASE: float = 100.0
const LEGACY_EXP_RATE: float = 1.15
## §6.1: the legacy Gold curve's stage rate, `gold * 1.18^(S-1)`.
const LEGACY_GOLD_RATE: float = 1.18
## §3.2/§12: the legacy affix generation constants, `value = base * (1 + 0.08*(il-1)) *
## (1 + 0.35*rarity) * roll` with `roll` uniform in this band. They are the ONLY way to recover a
## rolled affix's roll from a v3 value, so they stay here rather than in the v4 catalogue.
const LEGACY_AFFIX_LEVEL_STEP: float = 0.08
const LEGACY_AFFIX_RARITY_STEP: float = 0.35
const LEGACY_ROLL_MIN: float = 0.80
const LEGACY_ROLL_MAX: float = 1.20
## How far outside the legacy roll band a recovered roll may sit before the affix is treated as
## hand-authored rather than rolled. `compute_value()` rounded/truncated the stored value, so an
## exact band test would misfile a perfectly normal roll.
const LEGACY_ROLL_TOLERANCE: float = 0.03
## §9: "a legacy integer utility that cannot be reversed takes the neutral 0.5".
const NEUTRAL_ROLL_RATIO: float = 0.5
## Float slack when a stored value is compared against a recomputed one (JSON round-trips).
const VALUE_EPSILON: float = 0.005

const EquipmentRarityScript := preload("res://scripts/items/equipment_rarity.gd")


## One normalized conversion. `data` is a payload at [constant TARGET_VERSION]; `snapshot` records
## what the values were BEFORE the conversion, so a player can be shown what happened to their
## save, and `audit` lists every row that moved (bounded, for the debug surface).
##
## `migrate()` is idempotent in the sense that matters here: a payload that already declares
## balance version 4 is returned unchanged with `migrated = false`, so a second load of the
## migrated file cannot convert it twice.
static func migrate(data: Dictionary, profile: BalanceProfile = null) -> Dictionary:
	var resolved: BalanceProfile = profile if profile != null else BalanceProfile.get_default()
	var payload: Dictionary = data.duplicate(true)
	var audit: Array[Dictionary] = []
	if resolved == null:
		return _result(payload, false, {}, audit)
	if not _needs_migration(payload):
		return _result(payload, false, {}, audit)

	var snapshot: Dictionary = build_snapshot(payload, resolved)
	_migrate_character(payload, resolved, snapshot, audit)
	_migrate_items(payload, resolved, audit)
	_migrate_sub_heroes(payload, resolved, audit)
	_migrate_position(payload, resolved, snapshot, audit)
	# The stamps are what make the conversion ONE-TIME: without them the rewritten file would still
	# look like a v3 file and the next load would convert the already-converted numbers again.
	payload["version"] = TARGET_VERSION
	payload["balance_version"] = TARGET_VERSION
	payload["migrated_from_balance_version"] = LEGACY_VERSION
	payload["legacy_snapshot"] = snapshot
	payload["migration_audit"] = audit
	return _result(payload, true, snapshot, audit)


## True when this payload was written by a build that predates the v4 balance.
##
## The `version` field is the marker that matters: every save written before this migration declares
## format version 3 or less, and only a converted payload is written at [constant TARGET_VERSION].
## `balance_version` is a SECOND, independent statement of the scale (a future shape-preserving
## balance change would move it alone), so a payload that declares 4 there is already converted even
## if the frame around it carries no format version at all — a fixture, or a partial payload.
static func _needs_migration(payload: Dictionary) -> bool:
	var declared_balance: int = _to_int(payload.get("balance_version"), 0)
	if declared_balance >= TARGET_VERSION:
		return false
	var format_version: int = _to_int(payload.get("version"), 0)
	if format_version > 0:
		return format_version < TARGET_VERSION
	# No format version and no (or an older) balance version: a v1/v2-era or v3-era payload.
	return true


## §9: the audit row set a player-facing migration note is built from. It is written into the save
## so the report survives a restart and can be shown once, then dismissed.
static func build_snapshot(payload: Dictionary, profile: BalanceProfile) -> Dictionary:
	return {
		"level": _to_int(payload.get("level"), 1),
		"experience": _to_int(payload.get("experience"), 0),
		"gold": _to_int(payload.get("gold"), 0),
		"highest_stage_reached": _to_int(payload.get("highest_stage_reached"), 1),
		"current_stage_number": _to_int(payload.get("current_stage_number"), 1),
		"max_character_level": maxi(profile.max_character_level, 1),
		"max_stage": maxi(profile.max_stage, 1),
		"max_item_level": maxi(profile.max_item_level, 1),
	}


## §9, "the character's numbers": the level and the skills are kept inside the supported range, the
## EXP is re-expressed as a FRACTION of its level, and the Gold is converted at the highest cleared
## stage's own ratio so its local purchasing power survives.
##
## `player_progression.gd`'s curve is not used here on purpose: this must keep computing what the
## LEGACY curve would have asked for, and that curve is gone from the live code.
static func _migrate_character(
	payload: Dictionary,
	profile: BalanceProfile,
	snapshot: Dictionary,
	audit: Array[Dictionary]
) -> void:
	var max_level: int = maxi(profile.max_character_level, 1)
	var level: int = clampi(_to_int(payload.get("level"), 1), 1, max_level)
	payload["level"] = level
	if _to_int(snapshot.get("level"), 1) != level:
		audit.append({
			"kind": "level_clamped",
			"from": _to_int(snapshot.get("level"), 1),
			"to": level,
		})

	# §5/§9: `new_exp = min(need_new - 1, floor(f * need_new))` with
	# `f = clamp(old_exp / need_old, 0, 1)`, and a capped level keeps no banked EXP.
	var need_new: int = BalanceFormulas.experience_required(profile, level)
	var new_experience: int = 0
	if level < max_level:
		var old_need: float = LEGACY_EXP_BASE * pow(LEGACY_EXP_RATE, float(level - 1))
		var old_exp: float = float(maxi(_to_int(payload.get("experience"), 0), 0))
		var fraction: float = 0.0
		if is_finite(old_need) and old_need > 0.0 and is_finite(old_exp):
			fraction = clampf(old_exp / old_need, 0.0, 1.0)
		new_experience = _floor_to_int(float(need_new) * fraction)
		new_experience = clampi(new_experience, 0, maxi(need_new - 1, 0))
	payload["experience"] = new_experience
	audit.append({
		"kind": "experience_rescaled",
		"from": _to_int(snapshot.get("experience"), 0),
		"to": new_experience,
		"required": need_new,
	})

	# §6.1/§9: `new_gold = floor(old_gold * G(min(H,1000)) / 1.18^(H-1))`, computed in the LOG
	# domain so no legacy exponential has to be materialized as a number. A legacy gold that does not
	# fit in an int64 at all saturates in `_to_int`, so the comparison stays in the log domain too:
	# the result is clamped by magnitude, never by converting a wrapped integer.
	var highest: int = maxi(_to_int(payload.get("highest_stage_reached"), 1), 1)
	var anchor: int = mini(highest, maxi(profile.max_stage, 1))
	var old_gold: int = maxi(_to_int(payload.get("gold"), 0), 0)
	var new_gold: int = 0
	if old_gold > 0:
		var log_ratio: float = log(BalanceFormulas.g(profile, float(anchor))) \
			- float(anchor - 1) * log(LEGACY_GOLD_RATE)
		var log_value: float = log(float(old_gold)) + log_ratio
		var ceiling: int = _persistent_ceiling(profile)
		if is_nan(log_value) or log_value <= 0.0:
			new_gold = 0
		elif not is_finite(log_value) or log_value >= log(float(ceiling)):
			# The converted value is at or past the persisted ceiling. `exp()` of a very large log is
			# itself an overflow, and an int conversion of it can wrap, so the ceiling is applied in
			# the LOG domain instead of after the fact — that is the whole point of computing the
			# ratio this way.
			new_gold = ceiling
		else:
			new_gold = clampi(floori(exp(log_value)), 0, ceiling)
	new_gold = maxi(new_gold, 0)
	payload["gold"] = new_gold
	audit.append({
		"kind": "gold_rescaled",
		"from": old_gold,
		"to": new_gold,
		"anchor_stage": anchor,
	})


## §9, "items": identity, slot, item level, rarity, affix stat ids, rolls and unique effects are
## kept; every derived value is recomputed with the v4 formula and NOTHING is re-rolled.
static func _migrate_items(payload: Dictionary, profile: BalanceProfile, audit: Array[Dictionary]) -> void:
	var source_containers: Array = [payload.get("inventory", []), payload.get("storage", [])]
	var migrated_count: int = 0
	var authored_count: int = 0
	for container in source_containers:
		if not (container is Array):
			continue
		for entry in (container as Array):
			if not (entry is Dictionary):
				continue
			var item: Dictionary = entry as Dictionary
			var row: Dictionary = _migrate_item(item, profile)
			migrated_count += 1
			authored_count += int(row.get("authored", 0))
	if migrated_count > 0:
		audit.append({
			"kind": "items_recomputed",
			"count": migrated_count,
			"authored_affixes": authored_count,
		})


## One item: the definition's item level is clamped into the release range, the definition's
## AUTHORED base affixes are re-expressed in the v4 scale (they are the only place a hand-authored
## absolute value is visible), and each instance affix is converted from whatever era wrote it.
static func _migrate_item(item: Dictionary, profile: BalanceProfile) -> Dictionary:
	var definition: Variant = item.get("definition", {})
	var item_level: int = 1
	var definition_base_affixes: Array = []
	## The definition's base affix VALUES as they were read, captured before anything is converted:
	## matching an instance affix against them is how an authored value is recognized, and the
	## conversion itself rewrites those values in place.
	var definition_base_values: Array = []
	var rarity: int = EquipmentRarityScript.COMMON
	if definition is Dictionary:
		var definition_row: Dictionary = definition as Dictionary
		item_level = clampi(_to_int(definition_row.get("item_level"), 1), 1, maxi(profile.max_item_level, 1))
		definition_row["item_level"] = item_level
		rarity = clampi(_to_int(definition_row.get("rarity"), 0), 0, EquipmentRarityScript.MYTHIC)
		var raw_base: Variant = definition_row.get("base_affixes", [])
		if raw_base is Array:
			definition_base_affixes = raw_base as Array
		for affix_entry in definition_base_affixes:
			if affix_entry is Dictionary:
				var base_row: Dictionary = affix_entry as Dictionary
				definition_base_values.append({
					"stat_id": StringName(str(base_row.get("stat_id", ""))),
					"value": _to_float(base_row.get("value"), 0.0),
				})
	var authored: int = 0
	# The DEFINITION's own affixes are converted FIRST. In a restored item the two arrays can hold the
	# SAME entry: `EquipmentInstance.to_save_data()` writes the instance's affixes and its definition's
	# base affixes as two copies of the same payload, and a JSON round trip does not preserve object
	# identity, so a conversion pass over both would otherwise overwrite the instance's converted value
	# with the definition's conversion of the same row.
	for affix_entry in definition_base_affixes:
		if affix_entry is Dictionary:
			_convert_affix(affix_entry as Dictionary, item_level, rarity, profile, definition_base_values)
	var raw_affixes: Variant = item.get("affixes", [])
	if raw_affixes is Array:
		for affix_entry in (raw_affixes as Array):
			if not (affix_entry is Dictionary):
				continue
			if bool(_convert_affix(affix_entry as Dictionary, item_level, rarity, profile, definition_base_values).get("authored", false)):
				authored += 1
	return {"authored": authored}


## §9, "equipment": recover this stored affix's roll from the LEGACY formula, convert it to the
## normalized `roll_ratio`, and recompute the plane value with the v4 formula. Returns
## `{authored, matched}` so the caller can report how much of the collection had to be rebuilt from
## an authored value rather than a recovered roll.
static func _convert_affix(
	affix: Dictionary,
	item_level: int,
	rarity: int,
	profile: BalanceProfile,
	definition_base_values: Array
) -> Dictionary:
	var stat_id := StringName(str(affix.get("stat_id", "")))
	if stat_id.is_empty():
		return {"authored": false}
	var stored_value: float = _to_float(affix.get("value"), 0.0)
	var is_core: bool = BalanceFormulas.is_core_stat(stat_id)

	# 1. The item's OWN definition carries this affix verbatim, which is the signature of an
	#    authored value (`EquipmentInstance.create_from_definition` copies the definition's affixes
	#    as they are). An authored value must be recognized BEFORE the roll recovery, because an
	#    authored `+10 attack` can sit inside the legacy roll band and would otherwise be read as a
	#    lucky roll of the generic catalogue base.
	if _match_definition_base(stat_id, stored_value, definition_base_values):
		return _apply_authored_base(affix, stat_id, stored_value, item_level, rarity, profile, NEUTRAL_ROLL_RATIO)

	# 2. An R1-era affix can be recognized by recomputing the v4 formula and matching the stored
	#    value: it is the only era whose value has no item-level term for utility affixes and the
	#    new bases for the core ones.
	var stored_ratio: float = _to_float(affix.get("roll_ratio"), NEUTRAL_ROLL_RATIO)
	if affix.has("roll_ratio") and _matches_v4_value(stat_id, item_level, rarity, stored_ratio, stored_value, profile):
		_write_conversion(
			affix,
			clampf(stored_ratio, 0.0, 1.0),
			_v4_value(stat_id, EquipmentAffix.get_base_value(stat_id, profile), item_level, rarity, _roll_of(stored_ratio, profile), profile)
		)
		return {"authored": false}

	# 3. A generated v3 affix: undo `base * (1 + 0.08*(il-1)) * (1 + 0.35*rarity) * roll`.
	var legacy_roll: float = _recover_legacy_roll(stat_id, stored_value, item_level, rarity)
	if legacy_roll >= 0.0:
		_write_conversion(
			affix,
			_ratio_of(legacy_roll),
			_v4_value(stat_id, EquipmentAffix.get_base_value(stat_id, profile), item_level, rarity, legacy_roll, profile)
		)
		return {"authored": false}

	# 4. Unrecoverable: rebuild a SIGNED base and mark the provenance, so a negative crafted value
	#    or a hand-tuned absolute value is preserved instead of being read as a positive random roll.
	return _apply_authored_base(affix, stat_id, stored_value, item_level, rarity, profile, NEUTRAL_ROLL_RATIO)


## Rebuilds an authored affix from a SIGNED base.
##
## The migrated value is the stored one re-expressed on the v4 item scale:
##
##   core stat      -> `stored_value * item_scale_v4(il) / legacy_level_multiplier(il)`
##   utility affix  -> `stored_value` unchanged (neither era scales a probability with item level)
##
## so a hand-authored `+10 attack` on an il-10 item becomes `10 * G(10)^0.6 / 1.72`, while a
## hand-authored `+5 % dodge` stays exactly `+5 %`. That is what §9 asks for: the authored MAGNITUDE
## survives, re-expressed in the new scale, and a negative value stays negative.
##
## The signed base is then reported alongside it: the number the v4 formula needs as its input for
## that value, so a later recompute (a re-save, a preview, a re-derive) reproduces it instead of
## starting over from the catalogue base.
static func _apply_authored_base(
	affix: Dictionary,
	stat_id: StringName,
	stored_value: float,
	item_level: int,
	rarity: int,
	profile: BalanceProfile,
	roll_ratio: float
) -> Dictionary:
	var is_core: bool = BalanceFormulas.is_core_stat(stat_id)
	var value: float = stored_value
	if is_core:
		value *= item_scale(profile, item_level) / _legacy_level_multiplier(item_level)
	var value_scale: float = maxf(_scale_factor(stat_id, item_level, rarity, profile), VALUE_EPSILON)
	affix["roll_ratio"] = clampf(roll_ratio, 0.0, 1.0)
	affix["signed_base"] = value / value_scale
	affix["source_kind"] = "legacy_authored"
	affix["value"] = value
	return {"authored": true}


## The whole non-base factor the v4 affix formula multiplies a base by, at roll 1.0: the rarity term
## and (for a core stat only) the item scale. Dividing a converted value by it recovers the signed
## base, which is what makes the stored value and the reported base provably consistent.
static func _scale_factor(stat_id: StringName, item_level: int, rarity: int, profile: BalanceProfile) -> float:
	var factor: float = 1.0 + float(maxi(rarity, 0)) * LEGACY_AFFIX_RARITY_STEP
	if BalanceFormulas.is_core_stat(stat_id):
		factor *= item_scale(profile, item_level)
	return factor


## The v3 item-level term, `1 + 0.08 * (il - 1)`. Given an explicit affix base is being re-expressed
## rather than re-rolled, the legacy level term is what the stored number still carries.
static func _legacy_level_multiplier(item_level: int) -> float:
	return maxf(1.0 + float(maxi(item_level, 1) - 1) * LEGACY_AFFIX_LEVEL_STEP, VALUE_EPSILON)


## Writes one converted affix: the new normalized roll, the recomputed plane value and the clearing
## of the authored provenance. One place, so no branch can update the roll without the value.
static func _write_conversion(affix: Dictionary, roll_ratio: float, value: float) -> void:
	affix["roll_ratio"] = roll_ratio
	affix["value"] = value
	affix["source_kind"] = ""
	affix["signed_base"] = 0.0


## §3.1/§3.2's affix formula, with an EXPLICIT base.
##
## [method EquipmentAffix.compute_value] cannot be used here: it is the LIVE generator's entry and
## always takes the base from the current catalogue. A migration is converting a value that came from
## the OLD catalogue (or from an authored definition), so it has to supply its own base — calling the
## generator's entry would quietly re-base every migrated affix onto the v4 catalogue and lose the
## authored magnitude it was supposed to preserve.
static func _v4_value(
	stat_id: StringName,
	affix_base: float,
	item_level: int,
	rarity: int,
	roll: float,
	profile: BalanceProfile
) -> float:
	return BalanceFormulas.affix_value(
		profile,
		affix_base,
		item_level,
		rarity,
		roll,
		BalanceFormulas.is_core_stat(stat_id)
	)


## True when the stored value is what the v4 formula produces for that roll — the marker of an
## R1-era affix, which already carries a v4 value and a normalized ratio.
static func _matches_v4_value(
	stat_id: StringName,
	item_level: int,
	rarity: int,
	roll_ratio: float,
	stored_value: float,
	profile: BalanceProfile
) -> bool:
	if not (roll_ratio >= 0.0 and roll_ratio <= 1.0):
		return false
	var expected: float = _v4_value(
		stat_id,
		EquipmentAffix.get_base_value(stat_id, profile),
		item_level,
		rarity,
		_roll_of(roll_ratio, profile),
		profile
	)
	return absf(expected - stored_value) <= maxf(VALUE_EPSILON, absf(expected) * 0.01)


## Recovered `roll` from a v3 value, or -1.0 when the stored number cannot have come from the
## legacy generated formula (which is how a hand-authored value is told apart from a rolled one).
static func _recover_legacy_roll(stat_id: StringName, stored_value: float, item_level: int, rarity: int) -> float:
	var denominator: float = _legacy_denominator(stat_id, item_level, rarity)
	if denominator <= 0.0:
		return -1.0
	var roll: float = stored_value / denominator
	var minimum: float = LEGACY_ROLL_MIN - LEGACY_ROLL_TOLERANCE
	var maximum: float = LEGACY_ROLL_MAX + LEGACY_ROLL_TOLERANCE
	if roll < minimum or roll > maximum:
		return -1.0
	return clampf(roll, LEGACY_ROLL_MIN, LEGACY_ROLL_MAX)


## The legacy generated formula's non-roll factors: the level term, the rarity term and the base.
static func _legacy_denominator(stat_id: StringName, item_level: int, rarity: int) -> float:
	var base: float = _legacy_base_value(stat_id)
	if base <= 0.0:
		return 0.0
	var level_multiplier: float = 1.0 + float(maxi(item_level, 1) - 1) * LEGACY_AFFIX_LEVEL_STEP
	var rarity_multiplier: float = 1.0 + float(maxi(rarity, 0)) * LEGACY_AFFIX_RARITY_STEP
	return base * level_multiplier * rarity_multiplier


## The v3 catalogue's own affix bases, frozen here because the live catalogue no longer has them.
static func _legacy_base_value(stat_id: StringName) -> float:
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


## True when the item's own definition carries an authored base affix of this stat with this
## value — the signature of an AUTHORED affix (`EquipmentInstance.create_from_definition` copies
## the definition's affixes verbatim, so the two values are equal).
##
## `definition_base_values` is the definition's ORIGINAL stat id / value pairs, captured before the
## conversion rewrote them.
static func _match_definition_base(stat_id: StringName, stored_value: float, definition_base_values: Array) -> bool:
	for entry in definition_base_values:
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry as Dictionary
		if StringName(str(row.get("stat_id", ""))) != stat_id:
			continue
		if absf(_to_float(row.get("value"), 0.0) - stored_value) <= VALUE_EPSILON:
			return true
	return false


## §9, "hand-authored / negative affixes": a signed base that survives the item scale change.
##
## For a CORE stat the base is `value / (rarity term * roll * item_scale(il))` — the value the v4
## formula multiplies back, so the migrated number keeps the authored magnitude scaled by the item
## level. For a UTILITY affix it is `value / (rarity term * roll)`, because a utility value never
## carried `item_scale` in either era, so a utility affix ends up unchanged (which is what §3.2 asks
## for: probabilities must not grow with the item level).
static func _signed_base(
	stat_id: StringName,
	stored_value: float,
	item_level: int,
	rarity: int,
	roll: float,
	profile: BalanceProfile
) -> float:
	var divisor: float = maxf(1.0 + float(maxi(rarity, 0)) * LEGACY_AFFIX_RARITY_STEP, VALUE_EPSILON)
	divisor *= maxf(roll, VALUE_EPSILON)
	if BalanceFormulas.is_core_stat(stat_id):
		divisor *= maxf(item_scale(profile, item_level), VALUE_EPSILON)
	return stored_value / divisor


## The §3.1 item scale, with a guard so a zero exponent or a degenerate profile cannot divide by zero.
static func item_scale(profile: BalanceProfile, item_level: int) -> float:
	return maxf(BalanceFormulas.item_scale(profile, maxi(item_level, 1)), VALUE_EPSILON)


## The `roll` factor a normalized 0..1 ratio stands for, in the v4 band.
static func _roll_of(roll_ratio: float, profile: BalanceProfile) -> float:
	var span: float = profile.affix_roll_max - profile.affix_roll_min
	return profile.affix_roll_min + clampf(roll_ratio, 0.0, 1.0) * span


## The normalized ratio of a legacy 0.8..1.2 roll.
static func _ratio_of(legacy_roll: float) -> float:
	var span: float = LEGACY_ROLL_MAX - LEGACY_ROLL_MIN
	if is_zero_approx(span):
		return NEUTRAL_ROLL_RATIO
	return clampf((legacy_roll - LEGACY_ROLL_MIN) / span, 0.0, 1.0)


## §9, "Sub Heroes": id, level and duplicate count are kept; the investment coordinate and the
## summon price are DERIVED, never stored, so there is nothing to convert beyond validating the
## numbers the price will read.
static func _migrate_sub_heroes(payload: Dictionary, profile: BalanceProfile, audit: Array[Dictionary]) -> void:
	var block: Variant = payload.get("sub_heroes", {})
	if not (block is Dictionary):
		return
	var row: Dictionary = block as Dictionary
	var owned: Variant = row.get("owned_sub_heroes", [])
	if not (owned is Array):
		return
	var levels: Array[int] = []
	var duplicates: Array[int] = []
	for entry in (owned as Array):
		if not (entry is Dictionary):
			continue
		var instance: Dictionary = entry as Dictionary
		var level: int = maxi(_to_int(instance.get("level"), 1), 1)
		var duplicate_count: int = maxi(_to_int(instance.get("duplicate_count"), 0), 0)
		instance["level"] = level
		instance["duplicate_count"] = duplicate_count
		levels.append(level)
		duplicates.append(duplicate_count)
	if levels.is_empty():
		return
	var draws: int = BalanceFormulas.sub_hero_owned_draws(levels, duplicates, 3)
	audit.append({
		"kind": "sub_heroes_rebuilt",
		"count": levels.size(),
		"owned_draws": draws,
		"summon_cost": BalanceFormulas.sub_hero_summon_cost(profile, draws),
	})


## §9, "out of the supported range": the position, the unlock ceiling and the item levels are
## clamped into the release range, and the FULL legacy values stay in the snapshot and the backup
## file. The Sub Hero collection is untouched — it keeps its duplicates, and its combat coordinate
## is capped by the main character's level instead.
static func _migrate_position(
	payload: Dictionary,
	profile: BalanceProfile,
	snapshot: Dictionary,
	audit: Array[Dictionary]
) -> void:
	var max_stage: int = maxi(profile.max_stage, 1)
	var current: int = clampi(_to_int(payload.get("current_stage_number"), 1), 1, max_stage)
	var highest: int = clampi(_to_int(payload.get("highest_stage_reached"), current), current, max_stage)
	payload["current_stage_number"] = current
	payload["highest_stage_reached"] = maxi(highest, current)
	if _to_int(snapshot.get("current_stage_number"), 1) != current \
		or _to_int(snapshot.get("highest_stage_reached"), 1) != highest:
		audit.append({
			"kind": "stage_clamped",
			"from_current": _to_int(snapshot.get("current_stage_number"), 1),
			"to_current": current,
			"from_highest": _to_int(snapshot.get("highest_stage_reached"), 1),
			"to_highest": maxi(highest, current),
		})


static func _persistent_ceiling(profile: BalanceProfile) -> int:
	return int(minf(profile.max_persistent_value, 9223372036854775807.0))


## `floor` for a possibly huge float, saturating instead of wrapping. A migration must never turn a
## large legacy number into a small one through an int conversion.
static func _floor_to_int(value: float) -> int:
	if is_nan(value) or value <= 0.0:
		return 0
	if not is_finite(value) or value >= 9223372036854775807.0:
		return 9223372036854775807
	return floori(value)


static func _to_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		if not is_finite(value):
			return fallback
		return int(value)
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return fallback


static func _to_float(value: Variant, fallback: float) -> float:
	if value is float:
		return value if is_finite(value) else fallback
	if value is int:
		return float(value)
	if value is String and (value as String).is_valid_float():
		return (value as String).to_float()
	return fallback


static func _result(
	payload: Dictionary,
	migrated: bool,
	snapshot: Dictionary,
	audit: Array[Dictionary]
) -> Dictionary:
	return {
		"payload": payload,
		"migrated": migrated,
		"snapshot": snapshot,
		"audit": audit,
	}
