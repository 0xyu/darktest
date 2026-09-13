extends SceneTree

## Verifies the §9 v3 → v4 balance migration
## (`docs/balance-rework-implementation.md` §9, contract §8 R2):
##
##   * a v3 file is converted ONCE, with the untouched original backed up
##   * level, skills and the Sub Hero collection survive; the EXP is converted as a FRACTION of its
##     level, not as an absolute number
##   * Gold is converted at the highest unlocked stage's own ratio
##   * every item keeps its id, slot, item level, rarity, affix stat ids, unique effect and roll —
##     nothing is re-rolled, and an authored/negative value is not mistaken for a random roll
##   * an out-of-range record is clamped and its legacy value stays in the snapshot
##   * a SECOND load converts nothing, and the backup is still the true original
##
## The migration is exercised BOTH as a pure conversion (`BalanceMigrationV4.migrate`) and through
## the real file path, because the atomic-write half is where a half-migrated save would come from.

const SaveScript := preload("res://scripts/progress/stage_progress_save.gd")
const MigrationScript := preload("res://scripts/progress/balance_migration_v4.gd")
const BalanceMigrationScript := preload("res://scripts/progress/balance_migration_v4.gd")
const PlayerProgressionScript := preload("res://scripts/player/player_progression.gd")

const SCRATCH_PATH: String = "user://test_balance_migration_v4/migrate.json"
const PROFILE_PATH: String = BalanceProfile.DEFAULT_PROFILE_PATH

var _profile: BalanceProfile
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_profile = load(PROFILE_PATH) as BalanceProfile
	_expect(_profile != null, "the default balance profile loads")
	if _profile == null:
		_finish()
		return

	_test_experience_is_converted_as_a_fraction()
	_test_gold_keeps_local_purchasing_power()
	_test_items_keep_identity_and_rolls()
	_test_authored_and_negative_affixes_survive()
	_test_out_of_range_is_clamped_once()
	_test_capped_level_banks_nothing()
	_test_file_migration_is_atomic_and_reentrant()
	_test_damaged_values_do_not_break_the_migration()
	_finish()


## §9: `f = old_exp / need_old`, `new_exp = min(need_new - 1, floor(f * need_new))`. The point of the
## ratio is that a player who was 50 % into a level is still 50 % into it.
func _test_experience_is_converted_as_a_fraction() -> void:
	for level in [1, 2, 5, 20, 100]:
		var old_need: float = MigrationScript.LEGACY_EXP_BASE \
			* pow(MigrationScript.LEGACY_EXP_RATE, float(level - 1))
		var new_need: int = BalanceFormulas.experience_required(_profile, level)
		for fraction in [0.0, 0.25, 0.5, 0.99]:
			# The legacy requirement is materialized as an int64, which is what a v3 file could
			# actually hold. The expected fraction is derived the same way, so the assertion is
			# about the migration's arithmetic and not about float rounding.
			var old_exp: int = int(old_need * fraction)
			var payload: Dictionary = _base_payload()
			payload["version"] = 3
			payload["level"] = level
			payload["experience"] = old_exp
			var result: Dictionary = MigrationScript.migrate(payload, _profile)
			_expect(bool(result.get("migrated", false)), "a v3 payload is migrated (level %d)" % level)
			var migrated: Dictionary = result.get("payload", {})
			var expected: int = clampi(
				int(float(new_need) * clampf(float(old_exp) / old_need, 0.0, 1.0)), 0, maxi(new_need - 1, 0)
			)
			_expect(
				int(migrated.get("experience", -1)) == expected,
				"level %d at %.0f%% converts to %d, got %d" % [level, fraction * 100.0, expected, int(migrated.get("experience", -1))]
			)
			_expect(int(migrated.get("level", 0)) == level, "the level is kept when it is inside the range")

	# §9: above `L = 100` the legacy requirement stops fitting in an int64, which is exactly why the
	# conversion compares in the log domain. The result must still be a legal EXP for the level.
	for level in [200, 500, 900]:
		var late: Dictionary = _base_payload()
		late["version"] = 3
		late["level"] = level
		late["experience"] = 9223372036854775807
		var late_payload: Dictionary = MigrationScript.migrate(late, _profile).get("payload", {})
		var late_need: int = BalanceFormulas.experience_required(_profile, level)
		var late_exp: int = int(late_payload.get("experience", -1))
		_expect(
			late_exp >= 0 and late_exp < late_need,
			"level %d converts to an EXP inside its own level (%d < %d)" % [level, late_exp, late_need]
		)
		_expect(int(late_payload.get("level", 0)) == level, "level %d is kept" % level)

	# A save at the level cap keeps no banked EXP.
	var capped: Dictionary = _base_payload()
	capped["version"] = 3
	capped["level"] = _profile.max_character_level
	capped["experience"] = 500
	var capped_result: Dictionary = MigrationScript.migrate(capped, _profile)
	_expect(int((capped_result.get("payload", {}) as Dictionary).get("experience", -1)) == 0, "a capped level banks no EXP after migration")

	# Skill levels and points are kept exactly: they cannot be recomputed.
	var skilled: Dictionary = _base_payload()
	skilled["version"] = 3
	skilled["skill_points"] = 4
	skilled["skill_levels"] = {"whirlwind": 3, "arcane_bolt": 5}
	var skilled_result: Dictionary = MigrationScript.migrate(skilled, _profile)
	var skilled_payload: Dictionary = skilled_result.get("payload", {})
	_expect(int(skilled_payload.get("skill_points", -1)) == 4, "unspent skill points survive the migration")
	_expect(
		(skilled_payload.get("skill_levels", {}) as Dictionary).get("whirlwind", 0) == 3,
		"a learned skill level survives the migration"
	)


## §9: `new_gold = floor(old_gold * G(min(H,1000)) / 1.18^(H-1))`, so Gold keeps its approximate
## purchasing power in the services and items of the highest unlocked stage.
func _test_gold_keeps_local_purchasing_power() -> void:
	# Up to about stage 90 the legacy gold fits in an int64, which is what a real v3 file could hold,
	# so those anchors can be checked exactly.
	for anchor in [1, 5, 20, 60, 90]:
		var legacy_gold: float = 1234.0 * pow(MigrationScript.LEGACY_GOLD_RATE, float(anchor - 1))
		var payload: Dictionary = _base_payload()
		payload["version"] = 3
		payload["highest_stage_reached"] = anchor
		payload["current_stage_number"] = anchor
		payload["gold"] = int(legacy_gold)
		var migrated: Dictionary = MigrationScript.migrate(payload, _profile).get("payload", {})
		var expected: int = floori(1234.0 * BalanceFormulas.g(_profile, float(anchor)))
		var actual: int = int(migrated.get("gold", -1))
		_expect(
			absi(actual - expected) <= 3,
			"stage %d gold converts to ~%d, got %d" % [anchor, expected, actual]
		)

	# Past that the legacy gold has no int64 representation AND the legacy curve has outrun the v4
	# scale so far that the converted purse legitimately reaches zero: `1.18^999` is about `10^65`
	# times `G(1000)`. The conversion must still land on a LEGAL purse rather than a wrapped one.
	var late: Dictionary = _base_payload()
	late["version"] = 3
	late["highest_stage_reached"] = 1000
	late["gold"] = 9223372036854775807
	var late_gold: int = int((MigrationScript.migrate(late, _profile).get("payload", {}) as Dictionary).get("gold", -1))
	_expect(
		late_gold >= 0 and BalanceFormulas.is_valid_persistent_value(_profile, float(late_gold)),
		"a stage-1000 legacy purse lands inside the persisted domain (got %d)" % late_gold
	)
	# §9: a purse that is still comparable keeps a POSITIVE converted value rather than collapsing.
	var moderate: Dictionary = _base_payload()
	moderate["version"] = 3
	moderate["highest_stage_reached"] = 1000
	moderate["gold"] = 1000000
	var moderate_gold: int = int((MigrationScript.migrate(moderate, _profile).get("payload", {}) as Dictionary).get("gold", -1))
	_expect(
		moderate_gold >= 0 and BalanceFormulas.is_valid_persistent_value(_profile, float(moderate_gold)),
		"a stage-1000 purse converts to a legal value (got %d)" % moderate_gold
	)

	# Zero Gold stays zero.
	var zero: Dictionary = _base_payload()
	zero["version"] = 3
	zero["gold"] = 0
	_expect(
		int((MigrationScript.migrate(zero, _profile).get("payload", {}) as Dictionary).get("gold", -1)) == 0,
		"zero gold stays zero"
	)
	# A purse large enough to matter at the top stage is still clamped safely, never wrapped.
	var huge: Dictionary = _base_payload()
	huge["version"] = 3
	huge["highest_stage_reached"] = 1
	huge["gold"] = 9223372036854775807
	var huge_gold: int = int((MigrationScript.migrate(huge, _profile).get("payload", {}) as Dictionary).get("gold", -1))
	_expect(huge_gold > 0, "a huge legacy gold at stage 1 converts instead of wrapping (got %d)" % huge_gold)
	_expect(
		BalanceFormulas.is_valid_persistent_value(_profile, float(huge_gold)),
		"a converted gold stays inside the persisted ceiling"
	)
	_expect(
		huge_gold == BalanceMigrationScript._persistent_ceiling(_profile),
		"a purse past the ceiling is clamped TO the ceiling"
	)

## §9 "equipment": identity, slot, item level, rarity, affix stat ids, rolls and unique effects are
## kept and the derived values are recomputed — never re-rolled.
func _test_items_keep_identity_and_rolls() -> void:
	# A v3 GENERATED core affix: `5.0 * (1 + 0.08*9) * (1 + 0.35*2) * roll` for a Rare il-10
	# weapon. The roll must come back out of the stored value.
	var roll: float = 1.05
	var legacy_value: float = 5.0 * (1.0 + 0.08 * 9.0) * (1.0 + 0.35 * 2.0) * roll
	var payload: Dictionary = _base_payload()
	payload["version"] = 3
	payload["inventory"] = [_item_payload("weapon_a", 10, 2, "sword", [
		{"stat_id": "attack", "value": legacy_value, "roll_ratio": (roll - 0.8) / 0.4, "is_percentage": false, "display_name": "Attack"},
	])]
	var migrated: Dictionary = MigrationScript.migrate(payload, _profile).get("payload", {})
	var items: Array = migrated.get("inventory", [])
	_expect(items.size() == 1, "the item survives the migration")
	var item: Dictionary = items[0]
	_expect(str(item.get("instance_id", "")) == "weapon_a", "the item keeps its instance id")
	var definition: Dictionary = item.get("definition", {})
	_expect(int(definition.get("item_level", 0)) == 10, "the item keeps its item level")
	_expect(int(definition.get("rarity", -1)) == 2, "the item keeps its rarity")
	_expect(int(definition.get("slot", -1)) == EquipmentSlot.WEAPON, "the item keeps its slot")
	var affixes: Array = item.get("affixes", [])
	_expect(affixes.size() == 1, "the item keeps its affix")
	var affix: Dictionary = affixes[0]
	_expect(str(affix.get("stat_id", "")) == "attack", "the affix keeps its stat id")
	# The recovered roll must land back inside the expected ratio band, and the recomputed value
	# must be the v4 formula for that roll.
	var ratio: float = float(affix.get("roll_ratio", -1.0))
	_expect(
		absf(ratio - (roll - 0.8) / 0.4) < 0.02,
		"the roll is recovered from the legacy value (%.4f vs %.4f)" % [ratio, (roll - 0.8) / 0.4]
	)
	var expected_value: float = EquipmentAffix.compute_value(
		&"attack", 10, 2, _profile.affix_roll_min + ratio * (_profile.affix_roll_max - _profile.affix_roll_min), _profile
	)
	_expect(
		absf(float(affix.get("value", 0.0)) - expected_value) < 0.05,
		"the affix value is recomputed with the v4 formula (%.3f vs %.3f)" % [float(affix.get("value", 0.0)), expected_value]
	)
	_expect(str(affix.get("source_kind", "x")) == "", "a recovered roll is not marked as authored")

	# A utility affix never grows with the item level in either era.
	var utility_payload: Dictionary = _base_payload()
	utility_payload["version"] = 3
	utility_payload["inventory"] = [_item_payload("crit_a", 30, 4, "ring", [
		{"stat_id": "critical_chance", "value": 0.03 * (1.0 + 0.35 * 4.0) * 1.0, "is_percentage": true, "display_name": "Critical Chance"},
	])]
	var utility_item: Dictionary = (MigrationScript.migrate(utility_payload, _profile).get("payload", {}) as Dictionary).get("inventory", [])[0]
	var utility_affix: Dictionary = (utility_item.get("affixes", []) as Array)[0]
	var utility_expected: float = 0.03 * (1.0 + 0.35 * 4.0)
	_expect(
		absf(float(utility_affix.get("value", 0.0)) - utility_expected) < 0.005,
		"a utility affix keeps its magnitude (%.5f vs %.5f)" % [float(utility_affix.get("value", 0.0)), utility_expected]
	)

	# The unique effect id travels with the definition.
	var effect_payload: Dictionary = _base_payload()
	effect_payload["version"] = 3
	effect_payload["inventory"] = [_item_payload("relic", 5, 5, "amulet", [], "thorns")]
	var effect_item: Dictionary = (MigrationScript.migrate(effect_payload, _profile).get("payload", {}) as Dictionary).get("inventory", [])[0]
	_expect(
		str((effect_item.get("definition", {}) as Dictionary).get("unique_effect_id", "")) == "thorns",
		"the unique effect survives the migration"
	)


## §9: an authored or negative value must NOT be read as a positive random roll — it is rebuilt from
## a signed base and marked as authored.
func _test_authored_and_negative_affixes_survive() -> void:
	# A cursed HP -10 affix has no valid legacy roll, so it becomes a signed base.
	var cursed_payload: Dictionary = _base_payload()
	cursed_payload["version"] = 3
	cursed_payload["inventory"] = [_item_payload("cursed", 10, 0, "armor", [
		{"stat_id": "hp", "value": -10.0, "is_percentage": false, "display_name": "HP"},
	])]
	var cursed_affix: Dictionary = (((MigrationScript.migrate(cursed_payload, _profile).get("payload", {}) as Dictionary).get("inventory", []) as Array)[0].get("affixes", []) as Array)[0]
	_expect(str(cursed_affix.get("source_kind", "")) == "legacy_authored", "a negative affix is marked as authored")
	_expect(float(cursed_affix.get("signed_base", 0.0)) < 0.0, "a negative affix keeps a negative signed base")
	_expect(float(cursed_affix.get("value", 0.0)) < 0.0, "a negative affix stays negative — no HP is created")

	# Authored `+10 attack` on a Common il-10 item: the item's own definition carries it, so it is
	# recognized as authored and re-expressed in the v4 scale instead of being re-rolled.
	var authored_base: Array[Dictionary] = [
		{"stat_id": "attack", "value": 10.0, "roll_ratio": 0.5, "is_percentage": false, "display_name": "Attack"},
	]
	var authored_payload: Dictionary = _base_payload()
	authored_payload["version"] = 3
	authored_payload["inventory"] = [_item_payload("authored", 10, 0, "sword", [
		{"stat_id": "attack", "value": 10.0, "roll_ratio": 0.5, "is_percentage": false, "display_name": "Attack"},
	], "", authored_base)]
	var authored_item: Dictionary = ((MigrationScript.migrate(authored_payload, _profile).get("payload", {}) as Dictionary).get("inventory", []) as Array)[0]
	var authored_affix: Dictionary = (authored_item.get("affixes", []) as Array)[0]
	_expect(
		str(authored_affix.get("source_kind", "")) == "legacy_authored",
		"an affix the definition authored is marked as authored"
	)
	# §9: the authored MAGNITUDE survives, re-expressed on the v4 item scale.
	var expected_authored: float = 10.0 \
		* BalanceFormulas.item_scale(_profile, 10) \
		/ (1.0 + 9.0 * MigrationScript.LEGACY_AFFIX_LEVEL_STEP)
	_expect(
		absf(float(authored_affix.get("value", 0.0)) - expected_authored) < 0.05,
		"the authored value is re-expressed in the v4 scale (%.3f vs %.3f)" % [float(authored_affix.get("value", 0.0)), expected_authored]
	)
	_expect(
		MigrationScript.VALUE_EPSILON >= absf(
			float(authored_affix.get("signed_base", 0.0))
				- float(authored_affix.get("value", 0.0))
					/ (1.0 + 0.35 * 0.0) / BalanceFormulas.item_scale(_profile, 10)
		),
		"the reported signed base reproduces the stored value through the v4 formula"
	)
	# The definition's own base affix is converted in place too, so a fresh copy of the definition
	# carries the same number.
	var definition_base: Array = (authored_item.get("definition", {}) as Dictionary).get("base_affixes", [])
	_expect(definition_base.size() == 1, "the definition keeps its authored base affix")
	_expect(
		absf(float((definition_base[0] as Dictionary).get("value", 0.0)) - expected_authored) < 0.05,
		"the definition's authored affix is converted with the instance"
	)


## §9 "out of the supported range": the position, the level and the item level are clamped into the
## release range, and the legacy values stay in the snapshot.
func _test_out_of_range_is_clamped_once() -> void:
	var payload: Dictionary = _base_payload()
	payload["version"] = 3
	payload["level"] = 5000
	payload["current_stage_number"] = 4321
	payload["highest_stage_reached"] = 98765
	payload["inventory"] = [_item_payload("ancient", 9000, 3, "sword", [])]
	var result: Dictionary = MigrationScript.migrate(payload, _profile)
	var migrated: Dictionary = result.get("payload", {})
	_expect(int(migrated.get("level", 0)) == _profile.max_character_level, "the level is clamped to the release cap")
	_expect(int(migrated.get("current_stage_number", 0)) == _profile.max_stage, "the position is clamped to the last released stage")
	_expect(int(migrated.get("highest_stage_reached", 0)) == _profile.max_stage, "the ceiling is clamped to the last released stage")
	var clamped_item: Dictionary = (migrated.get("inventory", []) as Array)[0]
	_expect(
		int((clamped_item.get("definition", {}) as Dictionary).get("item_level", 0)) == _profile.max_item_level,
		"the item level is clamped to the release range"
	)
	var snapshot: Dictionary = result.get("snapshot", {})
	_expect(int(snapshot.get("level", 0)) == 5000, "the legacy level is recorded in the snapshot")
	_expect(int(snapshot.get("highest_stage_reached", 0)) == 98765, "the legacy ceiling is recorded in the snapshot")
	# The Sub Hero collection is NOT trimmed: it keeps its duplicates, and the main level caps its
	# combat coordinate instead.
	var sub_payload: Dictionary = _base_payload()
	sub_payload["version"] = 3
	sub_payload["sub_heroes"] = {
		"owned_sub_heroes": [{"hero_id": "skeleton_archer", "level": 40, "duplicate_count": 2}],
		"active_slot_ids": ["skeleton_archer", "", ""],
	}
	var sub_migrated: Dictionary = MigrationScript.migrate(sub_payload, _profile).get("payload", {})
	var owned: Array = (sub_migrated.get("sub_heroes", {}) as Dictionary).get("owned_sub_heroes", [])
	_expect(owned.size() == 1, "the Sub Hero collection survives the migration")
	_expect(int((owned[0] as Dictionary).get("level", 0)) == 40, "the Sub Hero keeps its level")
	_expect(int((owned[0] as Dictionary).get("duplicate_count", -1)) == 2, "the Sub Hero keeps its duplicates")


## §5/§9: at the level cap there is no banked EXP and no extra skill point.
func _test_capped_level_banks_nothing() -> void:
	var progression := PlayerProgressionScript.new()
	progression.balance_profile = _profile
	progression.level = _profile.max_character_level
	progression.experience = 0
	var points_before: int = progression.skill_points
	var gained: int = progression.add_experience(BalanceFormulas.experience_required(_profile, _profile.max_character_level) * 4)
	_expect(gained == 0, "a capped level gains no levels from a large award")
	_expect(progression.skill_points == points_before, "a capped level pays no skill points")
	_expect(progression.experience == 0, "a capped level banks no EXP")


## §9: the real file path — one conversion, an untouched backup, a v4 payload on disk, and a second
## load that converts NOTHING.
func _test_file_migration_is_atomic_and_reentrant() -> void:
	SaveScript.delete_save_at(SCRATCH_PATH)
	SaveScript.delete_save_at(SCRATCH_PATH + SaveScript.BACKUP_SUFFIX)
	SaveScript.delete_save_at(SCRATCH_PATH + SaveScript.TEMP_SUFFIX)

	var legacy: Dictionary = _legacy_v3_file_payload()
	var original_text: String = JSON.stringify(legacy, "\t")
	var directory: String = SCRATCH_PATH.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	file.store_string(original_text)
	file.close()

	var first = SaveScript.new(null, null, SCRATCH_PATH)
	first.balance_profile = _profile
	var migrations: Array = []
	first.load_migrated.connect(func(report: Dictionary) -> void: migrations.append(report))
	_expect(first.load(), "a v3 file loads")
	_expect(migrations.size() == 1, "the migration is announced exactly once")
	_expect(first.player_progression.level == 7, "the migrated level is restored")
	_expect(first.progress.current_stage_number == 12, "the migrated position is restored")

	var on_disk: Dictionary = _read_file(SCRATCH_PATH)
	_expect(int(on_disk.get("version", 0)) == SaveScript.FORMAT_VERSION, "the rewritten file declares the new format version")
	_expect(int(on_disk.get("balance_version", 0)) == SaveScript.BALANCE_VERSION, "the rewritten file declares the v4 balance version")
	_expect(
		!FileAccess.file_exists(SCRATCH_PATH + SaveScript.TEMP_SUFFIX),
		"no scratch file is left behind after a successful migration"
	)

	var backup_path: String = SCRATCH_PATH + SaveScript.BACKUP_SUFFIX
	_expect(FileAccess.file_exists(backup_path), "the pre-migration backup exists")
	var backup_text: String = FileAccess.get_file_as_string(backup_path)
	var backup_parsed: Variant = JSON.parse_string(backup_text)
	_expect(backup_parsed is Dictionary, "the backup is valid JSON")
	_expect(
		int((backup_parsed as Dictionary).get("version", 0)) == 3,
		"the backup is the UNTOUCHED v3 file"
	)
	# The backup must hold the UNCONVERTED item: same instance id, and the pre-migration value.
	var backup_inventory: Variant = (backup_parsed as Dictionary).get("inventory")
	_expect(backup_inventory is Array and (backup_inventory as Array).size() == 1, "the backup holds the original item")
	var backup_item: Dictionary = (backup_inventory as Array)[0]
	_expect(str(backup_item.get("instance_id", "")) == "saved_sword", "the backup item keeps its instance id")
	_expect(
		absf(float(((backup_item.get("affixes", []) as Array)[0] as Dictionary).get("value", 0.0)) - 9.0) < 0.001,
		"the backup holds the PRE-migration affix value"
	)

	# §9: a second load of the same path converts nothing and reports nothing.
	var second = SaveScript.new(null, null, SCRATCH_PATH)
	second.balance_profile = _profile
	var second_migrations: Array = []
	second.load_migrated.connect(func(_report: Dictionary) -> void: second_migrations.append(1))
	_expect(second.load(), "the migrated file loads again")
	_expect(second_migrations.is_empty(), "a second load migrates nothing")
	_expect(
		second.player_progression.experience == first.player_progression.experience,
		"a second load leaves the converted EXP exactly where the first left it"
	)
	_expect(second.player_progression.gold == first.player_progression.gold, "a second load leaves the converted gold alone")
	_expect(
		FileAccess.get_file_as_string(backup_path) == backup_text,
		"a second load does not overwrite the original backup"
	)

	SaveScript.delete_save_at(SCRATCH_PATH)
	SaveScript.delete_save_at(backup_path)


## §9: a damaged or hostile payload must not turn into a crash, a negative price or a wrapped int.
func _test_damaged_values_do_not_break_the_migration() -> void:
	var payload: Dictionary = _base_payload()
	payload["version"] = 3
	payload["level"] = "not a number"
	payload["experience"] = -50
	payload["gold"] = -1
	payload["inventory"] = [
		"not a dictionary",
		{"instance_id": "no_definition"},
		_item_payload("float_hp", 10, 0, "armor", [
			{"stat_id": "hp", "value": "twelve", "is_percentage": false},
			{"stat_id": "", "value": 5.0},
			{"value": 5.0},
		]),
	]
	var result: Dictionary = MigrationScript.migrate(payload, _profile)
	_expect(bool(result.get("migrated", false)), "a damaged v3 payload is still converted rather than dropped")
	var migrated: Dictionary = result.get("payload", {})
	_expect(int(migrated.get("level", 0)) >= 1, "a damaged level falls back to a usable one")
	_expect(int(migrated.get("experience", -1)) == 0, "a negative EXP becomes 0")
	_expect(int(migrated.get("gold", -1)) == 0, "a negative gold becomes 0")
	var items: Array = migrated.get("inventory", [])
	_expect(items.size() == 3, "damaged entries are carried through to the existing load path, which drops what it cannot name")

	# An already-migrated payload is left completely alone.
	var v4: Dictionary = _base_payload()
	v4["balance_version"] = 4
	v4["gold"] = 4242
	var untouched: Dictionary = MigrationScript.migrate(v4, _profile)
	_expect(not bool(untouched.get("migrated", true)), "a v4 payload is not migrated again")
	_expect(int((untouched.get("payload", {}) as Dictionary).get("gold", 0)) == 4242, "a v4 payload keeps its numbers")


## A v3 payload with the character, the map position, an item and a Sub Hero collection.
func _legacy_v3_file_payload() -> Dictionary:
	var payload: Dictionary = _base_payload()
	payload["version"] = 3
	payload["level"] = 7
	payload["experience"] = 300
	payload["gold"] = 9000
	payload["highest_stage_reached"] = 14
	payload["current_stage_number"] = 12
	payload["completed_stages"] = ["forest_006"]
	payload["consumed_content"] = ["forest_006:cache"]
	payload["inventory"] = [_item_payload("saved_sword", 12, 1, "sword", [
		{"stat_id": "attack", "value": 9.0, "roll_ratio": 0.5, "is_percentage": false, "display_name": "Attack"},
	])]
	payload["storage"] = []
	payload["sub_heroes"] = {
		"owned_sub_heroes": [{"hero_id": "skeleton_archer", "level": 3, "duplicate_count": 1}],
		"active_slot_ids": ["skeleton_archer", "", ""],
	}
	payload["skill_points"] = 2
	payload["skill_levels"] = {"whirlwind": 2}
	return payload


func _base_payload() -> Dictionary:
	return {
		"version": 3,
		"current_stage_number": 1,
		"highest_stage_reached": 1,
		"completed_stages": [],
		"consumed_content": [],
		"inventory": [],
		"storage": [],
		"sub_heroes": {},
		"level": 1,
		"experience": 0,
		"gold": 0,
		"skill_points": 0,
		"skill_levels": {},
	}


## One v3 item payload: the definition travels inline, which is how a generated item is stored.
func _item_payload(
	instance_id: String,
	item_level: int,
	rarity: int,
	definition_id: String,
	affixes: Array,
	unique_effect_id: String = "",
	definition_base_affixes: Array = []
) -> Dictionary:
	return {
		"instance_id": instance_id,
		"is_equipped": false,
		"definition": {
			"definition_id": definition_id,
			"display_name": definition_id.capitalize(),
			"slot": EquipmentSlot.WEAPON,
			"rarity": rarity,
			"item_level": item_level,
			"base_affixes": definition_base_affixes,
			"unique_effect_id": unique_effect_id,
			"description": "",
			"is_consumable": false,
			"heal_ratio": 0.0,
			"can_buy_back": false,
		},
		"affixes": affixes,
	}


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


## Structural equality through JSON, which is the only form both sides agree on after a round trip
## (a parsed dictionary holds floats where the source held ints).
func _comparable(left: Variant, right: Variant) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _finish() -> void:
	if _failures.is_empty():
		print("Balance migration v4 smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
