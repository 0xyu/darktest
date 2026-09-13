extends SceneTree

## Phase 8 smoke test: the player-side progress save (StageProgressSave).
## Run headless: godot --headless --path . -s res://tests/stage_progress_save_smoke_test.gd
##
## Covers the whole save contract without mounting the game scene:
##   * the payload shape — identifiers and scalars only, no area field, no Resource
##   * validation — format version, the stage-number domain, and the rule that a
##     short unlock ceiling is repaired by RAISING the ceiling, never by lowering
##     the player's position
##   * the disk round trip (write → read → same state), and a damaged file being
##     refused instead of half-read
##   * the autosave triggers: the save writes itself when the flow moves the player,
##     when the flow records a clear, and when one-shot content is consumed
##   * the player's OWNED ITEMS (equipped, bagged and stored) and SUB HEROES
##     round-tripping, their autosave triggers, and the repair rules a damaged
##     item / Sub Hero payload is held to
##   * the CHARACTER's own numbers (level, EXP, gold, skill points, skill levels)
##     round-tripping, their autosave triggers, the domains a damaged value is
##     clamped into, and the version 1 / 2 file that has none of them
##
## The scratch file lives in the project's generated .godot/ folder, so a test run
## never reads or writes a player's real save in user:// and leaves nothing behind.

const SaveScript = preload("res://scripts/progress/stage_progress_save.gd")
const StageFlowScript = preload("res://scripts/systems/stage_flow.gd")
const EquipmentInstanceScript = preload("res://scripts/items/equipment_instance.gd")
const EquipmentDefinitionScript = preload("res://scripts/items/equipment_definition.gd")
const EquipmentAffixScript = preload("res://scripts/items/equipment_affix.gd")
const SubHeroInstanceScript = preload("res://scripts/sub_hero/sub_hero_instance.gd")

const SCRATCH_PATH := "res://.godot/ui_harness/stage_progress_smoke.json"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fresh_save_payload()
	_test_payload_holds_no_area_and_no_resources()
	_test_round_trip_through_save_data()
	_test_round_trip_through_json()
	_test_position_domain_is_repaired_not_trusted()
	_test_ceiling_is_raised_never_the_position_lowered()
	_test_damaged_saves_are_rejected()
	_test_unusable_fields_are_tolerated()
	_test_disk_round_trip()
	_test_autosave_follows_the_flow()
	_test_autosave_follows_consumed_content()
	_test_player_items_and_sub_heroes_round_trip()
	_test_damaged_item_and_sub_hero_payloads_are_repaired()
	_test_autosave_follows_player_items()
	_test_character_progression_round_trips()
	_test_damaged_character_numbers_are_repaired()
	_test_autosave_follows_character_progression()
	SaveScript.delete_save_at(SCRATCH_PATH)

	if _failures.is_empty():
		print("StageProgressSave smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_fresh_save_payload() -> void:
	var save = SaveScript.new()
	var data: Dictionary = save.to_save_data()
	_expect(int(data.get("version", 0)) == SaveScript.FORMAT_VERSION, "a fresh save carries the current format version")
	_expect(int(data.get("current_stage_number", -1)) == 1, "a new game starts on stage 1")
	_expect(int(data.get("highest_stage_reached", -1)) == 1, "a new game's unlock ceiling starts at 1")
	_expect((data.get("completed_stages") as Array).is_empty(), "a new game has no completions")
	_expect((data.get("consumed_content") as Array).is_empty(), "a new game has no consumed content")
	_expect(int(data.get("level", -1)) == 1, "a new game's character is level 1")
	_expect(int(data.get("experience", -1)) == 0, "a new game's character has no EXP")
	_expect(int(data.get("gold", -1)) == 0, "a new game's character has an empty purse")
	_expect(int(data.get("skill_points", -1)) == 0, "a new game's character has no skill points")
	_expect((data.get("skill_levels") as Dictionary).is_empty(), "a new game's character has learned no skill")
	_expect(save.get_resume_stage_number() == 1, "a new game resumes on stage 1")


func _test_payload_holds_no_area_and_no_resources() -> void:
	var save = SaveScript.new()
	save.progress.current_stage_number = 6
	save.progress.mark_reached(9)
	save.progress.complete_stage(1)
	save.content_state.consume("forest_006", &"cache")
	var data: Dictionary = save.to_save_data()
	# Guard the model this phase must not undo: the area is DERIVED from the
	# position, so an area field in the save would be a second stored copy of
	# "where am I" — exactly the drift the global stage range removed.
	for key in data:
		_expect(not String(key).contains("area"), "the save must not store an area field (found '%s')" % key)
	_expect(data.get("completed_stages") is Array, "completions are stored as a list of ids")
	_expect(data.get("consumed_content") is Array, "consumed content is stored as a list of ids")
	for stage_id in data.get("completed_stages"):
		_expect(stage_id is String, "completion keys must be Strings, not Resources")
	for key in data.get("consumed_content"):
		_expect(key is String, "consumed keys must be Strings, not Resources")


func _test_round_trip_through_save_data() -> void:
	var source = SaveScript.new()
	source.progress.current_stage_number = 6
	source.progress.mark_reached(9)
	source.progress.complete_stage(3)
	source.progress.complete_stage(4)
	source.content_state.consume("forest_006", &"cache")

	var restored = SaveScript.new()
	_expect(restored.load_save_data(source.to_save_data()), "a save payload loads")
	_expect(restored.progress.current_stage_number == 6, "the position round-trips")
	_expect(restored.progress.highest_stage_reached == 9, "the unlock ceiling round-trips separately from the position")
	_expect(restored.progress.is_stage_completed(3), "recorded completions round-trip")
	_expect(restored.progress.is_stage_completed(4), "every recorded completion round-trips")
	_expect(not restored.progress.is_stage_completed(5), "a stage that was never cleared is not restored as cleared")
	_expect(restored.progress.is_stage_unlocked(9), "the restored ceiling keeps the map unlocked")
	_expect(restored.content_state.is_consumed("forest_006", &"cache"), "consumed content round-trips")
	_expect(restored.content_state.get_consumed_count() == 1, "exactly the consumed entries are restored")
	_expect(restored.progress != source.progress, "a load restores into its own state objects")


func _test_round_trip_through_json() -> void:
	var source = SaveScript.new()
	source.progress.current_stage_number = 6
	source.progress.mark_reached(9)
	source.progress.complete_stage(2)
	source.content_state.consume("forest_006", &"cache")

	var parsed: Variant = JSON.parse_string(JSON.stringify(source.to_save_data(), "\t"))
	_expect(parsed is Dictionary, "the payload survives JSON (the on-disk format)")
	var restored = SaveScript.new()
	_expect(restored.load_save_data(parsed as Dictionary), "the JSON form loads")
	_expect(restored.progress.current_stage_number == 6, "the position survives JSON")
	_expect(restored.progress.highest_stage_reached == 9, "the ceiling survives JSON")
	_expect(restored.progress.is_stage_completed(2), "completions survive JSON")
	_expect(restored.content_state.is_consumed("forest_006", &"cache"), "consumed content survives JSON")


func _test_position_domain_is_repaired_not_trusted() -> void:
	var below = SaveScript.new()
	_expect(below.load_save_data({"version": 1, "current_stage_number": 0, "highest_stage_reached": 0}), "a payload below the stage domain still loads")
	_expect(below.progress.current_stage_number == 1, "a position below stage 1 is clamped up to stage 1")

	# A position PAST every authored area is the normal state after the authored
	# content runs out: it is legal, and it must not be pulled back into a range.
	var far = SaveScript.new()
	_expect(far.load_save_data({"version": 1, "current_stage_number": 57, "highest_stage_reached": 57}), "a position past every authored area loads")
	_expect(far.progress.current_stage_number == 57, "a position past the authored path is kept as it is")
	_expect(String(far.progress.get_current_area_id()) == "", "that position derives no area (the endless tail)")
	_expect(far.progress.is_stage_unlocked(57), "the restored ceiling keeps the endless tail enterable")

	var above = SaveScript.new()
	_expect(above.load_save_data({"version": 1, "current_stage_number": 4000000, "highest_stage_reached": 4000000}), "a position above the stage domain still loads")
	_expect(above.progress.current_stage_number == SaveScript.MAX_STAGE_NUMBER, "a damaged position above the domain is clamped to its declared edge")


func _test_ceiling_is_raised_never_the_position_lowered() -> void:
	var repaired = SaveScript.new()
	_expect(repaired.load_save_data({"version": 1, "current_stage_number": 9, "highest_stage_reached": 4}), "a save whose ceiling fell behind its position loads")
	_expect(repaired.progress.current_stage_number == 9, "a short unlock ceiling must NOT lower the position")
	_expect(repaired.progress.highest_stage_reached >= 9, "the ceiling is raised to the position instead")
	_expect(repaired.progress.is_stage_unlocked(9), "the repaired ceiling keeps the position enterable")

	var missing = SaveScript.new()
	_expect(missing.load_save_data({"version": 1, "current_stage_number": 5}), "a save with no ceiling field loads")
	_expect(missing.progress.highest_stage_reached >= 5, "a missing ceiling defaults to the position")


func _test_damaged_saves_are_rejected() -> void:
	var reasons: Array = []
	var save = SaveScript.new()
	save.load_rejected.connect(func(reason: String) -> void: reasons.append(reason))
	_expect(not save.load_save_data({}), "an empty payload is refused")
	_expect(not save.load_save_data({"current_stage_number": 6}), "a payload with no format version is refused")
	_expect(
		not save.load_save_data({"version": SaveScript.FORMAT_VERSION + 1, "current_stage_number": 6}),
		"a save from a NEWER format is refused rather than half-read"
	)
	_expect(reasons.size() == 3, "every refusal reports a reason (got %d)" % reasons.size())
	_expect(save.progress.current_stage_number == 1, "a refused payload changes nothing")
	_expect(save.progress.get("completed_stages").is_empty(), "a refused payload records no completions")


func _test_unusable_fields_are_tolerated() -> void:
	# A field of the wrong type, or an entry that is not a usable identifier, is
	# dropped instead of aborting the load: the save is carried on what it can use.
	var mixed = SaveScript.new()
	_expect(
		mixed.load_save_data({
			"version": 1,
			"current_stage_number": 6,
			"highest_stage_reached": 6,
			"completed_stages": "forest_006",
			"consumed_content": [7, null, "", "forest_006:cache"],
		}),
		"a payload with unusable fields still loads"
	)
	_expect(mixed.progress.current_stage_number == 6, "the usable fields are restored")
	_expect(mixed.progress.get("completed_stages").is_empty(), "a non-list completion field is ignored, not crashed on")
	_expect(mixed.content_state.get_consumed_count() == 1, "only usable identifier strings are restored from a mixed list")

	# A save written by a build with MORE fields still loads: unknown keys are not
	# an error, they are simply not this build's business.
	var extended = SaveScript.new()
	_expect(
		extended.load_save_data({"version": 1, "current_stage_number": 6, "highest_stage_reached": 6, "future_field": {"a": 1}}),
		"unknown keys are ignored"
	)
	_expect(extended.progress.current_stage_number == 6, "the known fields of an extended save still load")

	# Ids that no authored area resolves any more are STALE, not corrupt: after a
	# re-authored stage range they are kept quietly, never used, and never thrown
	# away — a player's completions are not the save system's to delete.
	var stale = SaveScript.new()
	_expect(
		stale.load_save_data({"version": 1, "current_stage_number": 2, "highest_stage_reached": 2, "completed_stages": ["dungeon_031"]}),
		"a save with a stale stage id loads"
	)
	_expect(stale.progress.get("completed_stages").has("dungeon_031"), "a stale id is kept instead of being dropped")
	_expect(not stale.progress.is_stage_completed(2), "a stale id does not mark any current stage completed")


func _test_disk_round_trip() -> void:
	SaveScript.delete_save_at(SCRATCH_PATH)
	var save = SaveScript.new(null, null, SCRATCH_PATH)
	_expect(not save.has_save(), "no save file exists before the first write")
	_expect(not save.load(), "loading with no file reports false without failing")
	_expect(save.progress.current_stage_number == 1, "a missing file leaves the fresh state alone")

	save.progress.current_stage_number = 6
	save.progress.mark_reached(9)
	save.progress.complete_stage(1)
	save.content_state.consume("forest_006", &"cache")
	_expect(save.save(), "the save writes to disk")
	_expect(SaveScript.save_exists_at(SCRATCH_PATH), "the save file exists after writing")

	var reloaded = SaveScript.new(null, null, SCRATCH_PATH)
	_expect(reloaded.load(), "the written file loads back")
	_expect(reloaded.progress.current_stage_number == 6, "the position round-trips through disk")
	_expect(reloaded.progress.highest_stage_reached == 9, "the ceiling round-trips through disk")
	_expect(reloaded.progress.is_stage_completed(1), "completions round-trip through disk")
	_expect(reloaded.content_state.is_consumed("forest_006", &"cache"), "consumed content round-trips through disk")

	var damaged_file := FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	_expect(damaged_file != null, "the scratch file can be overwritten for the damage case")
	if damaged_file != null:
		damaged_file.store_string("{ this is not json")
		damaged_file.close()
	var damaged = SaveScript.new(null, null, SCRATCH_PATH)
	_expect(not damaged.load(), "a damaged file is refused")
	_expect(damaged.progress.current_stage_number == 1, "a damaged file leaves the fresh state alone")

	var empty_file := FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	if empty_file != null:
		empty_file.store_string("")
		empty_file.close()
	var empty = SaveScript.new(null, null, SCRATCH_PATH)
	_expect(not empty.load(), "an empty file is refused")
	_expect(empty.progress.current_stage_number == 1, "an empty file leaves the fresh state alone")

	SaveScript.delete_save_at(SCRATCH_PATH)
	_expect(not SaveScript.save_exists_at(SCRATCH_PATH), "the scratch file is cleaned up")
	SaveScript.delete_save_at(SCRATCH_PATH)
	_expect(true, "deleting a save that is not there is not an error")


func _test_autosave_follows_the_flow() -> void:
	# The autosave trigger: the save subscribes to the flow's single progress
	# writer, so nothing in the game has to remember to save.
	SaveScript.delete_save_at(SCRATCH_PATH)
	var save = SaveScript.new(null, null, SCRATCH_PATH)
	var writes: Array = []
	save.saved.connect(func(_save_path: String) -> void: writes.append(1))
	var flow = StageFlowScript.new(save.progress)
	save.bind(flow)
	_expect(not save.has_save(), "binding alone writes nothing")
	_expect(writes.is_empty(), "binding alone announces nothing")

	flow.on_stage_started(6)
	_expect(writes.size() == 1, "moving to another stage writes the save once (got %d)" % writes.size())
	_expect(int(_read_scratch().get("current_stage_number", -1)) == 6, "the saved position follows the flow")

	# FARMING re-spawns the stage the player is already on: nothing changed, so the
	# file must not be rewritten for the whole grinding session.
	flow.on_stage_started(6)
	_expect(writes.size() == 1, "a re-spawn of the same stage writes nothing (got %d)" % writes.size())

	flow.on_battle_cleared(6)
	_expect(writes.size() == 2, "recording a clear writes the save once (got %d)" % writes.size())
	_expect(_scratch_list("completed_stages").has("forest_006"), "the completion is on disk under its canonical id")

	flow.on_battle_cleared(6)
	_expect(writes.size() == 2, "clearing the same stage again writes nothing new (got %d)" % writes.size())

	flow.on_stage_started(7)
	_expect(writes.size() == 3, "the next stage writes again (got %d)" % writes.size())
	_expect(int(_read_scratch().get("highest_stage_reached", -1)) == 7, "the unlock ceiling on disk keeps up with the position")
	SaveScript.delete_save_at(SCRATCH_PATH)


func _test_autosave_follows_consumed_content() -> void:
	SaveScript.delete_save_at(SCRATCH_PATH)
	var save = SaveScript.new(null, null, SCRATCH_PATH)
	var flow = StageFlowScript.new(save.progress)
	save.bind(flow)
	flow.on_stage_started(6)
	_expect(save.has_save(), "the stage start already wrote a save")
	_expect(_scratch_list("consumed_content").is_empty(), "nothing is recorded as consumed yet")

	save.content_state.consume("forest_006", &"cache")
	_expect(_scratch_list("consumed_content").has("forest_006:cache"), "consuming one-shot content writes it to disk")

	var writes: Array = []
	save.saved.connect(func(_save_path: String) -> void: writes.append(1))
	save.content_state.consume("forest_006", &"cache")
	_expect(writes.is_empty(), "re-consuming the same entry changes nothing and writes nothing")
	_expect(save.content_state.get_consumed_count() == 1, "a repeated consume still records exactly one entry")
	SaveScript.delete_save_at(SCRATCH_PATH)


## The player's belongings are part of the SAME save as the map progress: an
## equipped item, a bagged item, a stored item and a Sub Hero all have to come
## back as they were — including the rolled numbers, which exist nowhere else.
func _test_player_items_and_sub_heroes_round_trip() -> void:
	var source = SaveScript.new()
	var weapon := _create_item("smoke_weapon", EquipmentSlot.WEAPON, EquipmentRarity.RARE, 12, &"every_3rd_attack")
	_expect(source.inventory.add_item(weapon), "the fixture weapon enters the bag")
	_expect(source.inventory.equip_item(weapon), "the fixture weapon is equipped")
	var ring := _create_item("smoke_ring", EquipmentSlot.RING, EquipmentRarity.EPIC, 22, &"")
	_expect(source.inventory.add_item(ring), "the fixture ring stays in the bag")
	var boots := _create_item("smoke_boots", EquipmentSlot.BOOTS, EquipmentRarity.COMMON, 4, &"")
	_expect(source.storage.add_item(boots), "the fixture boots go to the warehouse")
	var potion := _create_potion("smoke_potion", 3)
	_expect(source.inventory.add_item(potion), "the fixture potion enters the bag")
	var hero := SubHeroInstanceScript.new(&"skeleton_archer", 3)
	hero.duplicate_count = 2
	_expect(bool(source.sub_heroes.add_instance(hero).get("is_new", false)), "the fixture Sub Hero is owned")
	_expect(source.sub_heroes.assign_active_slot(1, &"skeleton_archer"), "the fixture Sub Hero is assigned")

	var parsed: Variant = JSON.parse_string(JSON.stringify(source.to_save_data(), "\t"))
	_expect(parsed is Dictionary, "the payload with items survives JSON (the on-disk format)")
	var restored = SaveScript.new()
	_expect(restored.load_save_data(parsed as Dictionary), "the payload with items loads")

	_expect(restored.inventory.items.size() == 3, "every owned item is restored (got %d)" % restored.inventory.items.size())
	var restored_weapon = restored.inventory.get_equipped_item(EquipmentSlot.WEAPON)
	_expect(restored_weapon != null, "an equipped item comes back EQUIPPED, not dumped into the bag")
	if restored_weapon != null:
		_expect(restored_weapon.instance_id == &"smoke_weapon", "the item keeps its instance id")
		_expect(restored_weapon.definition.definition_id == &"def_smoke_weapon", "the item keeps its definition id")
		_expect(restored_weapon.get_item_level() == 12, "the item keeps its item level")
		_expect(restored_weapon.get_rarity() == EquipmentRarity.RARE, "the item keeps its rarity")
		_expect(restored_weapon.definition.unique_effect_id == &"every_3rd_attack", "the item keeps its unique effect")
		_expect(restored_weapon.affixes.size() == 1, "the rolled affixes are restored")
		_expect(is_equal_approx(restored_weapon.get_affix_value(&"attack"), 7.0), "the rolled affix VALUE is restored")
		_expect(is_equal_approx(restored_weapon.affixes[0].roll_ratio, 0.75), "the roll ratio is restored (it cannot be recomputed)")
	_expect(restored.inventory.get_bag_items().size() == 2, "bagged items come back in the bag (the equipped one does not count)")
	_expect(restored.inventory.get_item_count() == 2, "the restored bag occupies two slots")
	_expect(_has_instance(restored.inventory.items, &"smoke_ring"), "the bagged ring is restored")
	_expect(_find_item(restored.inventory.items, &"smoke_ring").get_rarity() == EquipmentRarity.EPIC, "the ring keeps its rarity")
	var restored_potion = _find_item(restored.inventory.items, &"smoke_potion")
	_expect(restored_potion != null and restored_potion.is_consumable(), "a consumable is restored as a consumable")
	_expect(restored_potion != null and is_equal_approx(restored_potion.get_heal_ratio(), 0.35), "the consumable keeps its heal ratio")
	_expect(_has_instance(restored.storage.items, &"smoke_boots"), "the warehouse contents are restored")
	_expect(restored.storage.get_item_count() == 1, "exactly the stored item is restored")

	var restored_hero = restored.sub_heroes.get_owned_instance(&"skeleton_archer")
	_expect(restored_hero != null, "the owned Sub Hero is restored")
	if restored_hero != null:
		_expect(restored_hero.level == 3, "the Sub Hero keeps its level")
		_expect(restored_hero.duplicate_count == 2, "the Sub Hero keeps its duplicate progress")
	_expect(restored.sub_heroes.active_slot_ids[1] == &"skeleton_archer", "the Sub Hero keeps its active slot")
	_expect(restored.inventory != source.inventory, "a load restores into its own containers")


## A damaged payload is repaired, never trusted: the load carries on with what it
## can use, and the collections it produces obey their own rules (one item per
## equipped slot, no two items sharing an id).
func _test_damaged_item_and_sub_hero_payloads_are_repaired() -> void:
	var equipped_weapon: Dictionary = _create_item("payload_weapon_a", EquipmentSlot.WEAPON, EquipmentRarity.RARE, 5, &"").to_save_data()
	equipped_weapon["is_equipped"] = true
	var second_weapon: Dictionary = _create_item("payload_weapon_b", EquipmentSlot.WEAPON, EquipmentRarity.RARE, 5, &"").to_save_data()
	second_weapon["is_equipped"] = true
	var duplicate_id: Dictionary = _create_item("payload_weapon_a", EquipmentSlot.RING, EquipmentRarity.COMMON, 5, &"").to_save_data()
	var equipped_potion: Dictionary = _create_potion("payload_potion", 5).to_save_data()
	equipped_potion["is_equipped"] = true

	var restored = SaveScript.new()
	_expect(
		restored.load_save_data({
			"version": SaveScript.FORMAT_VERSION,
			"current_stage_number": 6,
			"highest_stage_reached": 6,
			"inventory": [42, {"instance_id": "no_definition"}, equipped_weapon, second_weapon, duplicate_id, equipped_potion],
			"storage": "not a list",
			"sub_heroes": {
				"owned_sub_heroes": [{"hero_id": "not_a_hero"}, {"hero_id": "skeleton_archer", "level": 2}],
				"active_slot_ids": ["not_a_hero"],
			},
		}),
		"a payload with unusable item and Sub Hero entries still loads"
	)
	_expect(restored.inventory.items.size() == 3, "usable entries are restored and the rest are dropped (got %d)" % restored.inventory.items.size())
	_expect(restored.inventory.get_equipped_items().size() == 1, "only ONE item may come back equipped")
	_expect(restored.inventory.get_equipped_item(EquipmentSlot.WEAPON).instance_id == &"payload_weapon_a", "the first equipped item of a slot wins")
	_expect(restored.inventory.get_bag_items().size() == 2, "the displaced and slot-less items are back in the bag")
	_expect(not _find_item(restored.inventory.items, &"payload_potion").is_equipped, "a consumable can never come back equipped")
	_expect(restored.storage.get_item_count() == 0, "a non-list storage field restores nothing instead of crashing")
	_expect(restored.sub_heroes.get_owned_instance(&"not_a_hero") == null, "a Sub Hero this build does not know is not restored")
	_expect(restored.sub_heroes.get_owned_hero_ids().size() == 1, "the known Sub Hero is restored and the unknown one dropped")
	_expect(String(restored.sub_heroes.active_slot_ids[0]) == "", "a slot pointing at an unowned Sub Hero is cleared")


## The same autosave rule the map progress follows: the save subscribes to the
## containers, so a pickup, an equip and a summon persist with no gameplay path
## asking for a save.
func _test_autosave_follows_player_items() -> void:
	SaveScript.delete_save_at(SCRATCH_PATH)
	var save = SaveScript.new(null, null, SCRATCH_PATH)
	var flow = StageFlowScript.new(save.progress)
	save.bind(flow)
	_expect(not save.has_save(), "binding alone writes nothing")

	var weapon := _create_item("autosave_weapon", EquipmentSlot.WEAPON, EquipmentRarity.RARE, 12, &"")
	_expect(save.inventory.add_item(weapon), "the picked-up weapon enters the bag")
	_expect(save.has_save(), "acquiring an item wrote the save (the pickup path never asked)")
	_expect(_scratch_list("inventory").size() == 1, "the acquired item is on disk")
	_expect(String((_scratch_list("inventory")[0] as Dictionary).get("instance_id", "")) == "autosave_weapon", "the item on disk is the one that was picked up")

	save.storage.add_item(_create_item("autosave_boots", EquipmentSlot.BOOTS, EquipmentRarity.COMMON, 4, &""))
	_expect(_scratch_list("storage").size() == 1, "storing an item wrote the warehouse to disk")

	save.sub_heroes.add_instance(SubHeroInstanceScript.new(&"skeleton_archer", 1))
	var sub_hero_payload: Dictionary = _read_scratch().get("sub_heroes", {}) as Dictionary
	_expect((sub_hero_payload.get("owned_sub_heroes", []) as Array).size() == 1, "summoning a Sub Hero wrote it to disk")
	_expect(save.sub_heroes.assign_active_slot(2, &"skeleton_archer"), "the Sub Hero is assigned a slot")
	_expect((_read_scratch().get("sub_heroes", {}) as Dictionary).get("active_slot_ids", [])[2] == "skeleton_archer", "the slot assignment is on disk")

	var writes: Array = []
	save.saved.connect(func(_save_path: String) -> void: writes.append(1))
	_expect(save.inventory.equip_item(weapon), "the weapon is equipped")
	_expect(writes.size() == 1, "equipping writes the save once (got %d)" % writes.size())

	var reloaded = SaveScript.new(null, null, SCRATCH_PATH)
	_expect(reloaded.load(), "the autosaved file loads")
	_expect(reloaded.inventory.get_equipped_item(EquipmentSlot.WEAPON) != null, "the equipped state is on disk")
	_expect(reloaded.sub_heroes.get_owned_instance(&"skeleton_archer") != null, "the owned Sub Hero is on disk")
	SaveScript.delete_save_at(SCRATCH_PATH)


## The character's own numbers belong in the SAME save as the map progress and the
## belongings: quit and come back, and the level, the EXP inside it, the purse, the
## unspent points and the learned skills are what they were. The skill map is the
## part that exists nowhere else — a learned level cannot be recomputed.
func _test_character_progression_round_trips() -> void:
	var source = SaveScript.new()
	source.player_progression.level = 12
	source.player_progression.experience = 40
	source.player_progression.gold = 3450
	source.player_progression.skill_points = 3
	source.player_progression.skill_levels = {
		SkillCatalog.WHIRLWIND: 4,
		SkillCatalog.ARCANE_BOLT: 1,
	}

	var parsed: Variant = JSON.parse_string(JSON.stringify(source.to_save_data(), "\t"))
	_expect(parsed is Dictionary, "the payload with character growth survives JSON (the on-disk format)")
	var restored = SaveScript.new()
	_expect(restored.load_save_data(parsed as Dictionary), "the payload with character growth loads")
	_expect(restored.player_progression.level == 12, "the level round-trips")
	_expect(restored.player_progression.experience == 40, "the EXP inside the level round-trips")
	_expect(restored.player_progression.gold == 3450, "the purse round-trips")
	_expect(restored.player_progression.skill_points == 3, "the unspent skill points round-trip")
	_expect(restored.player_progression.get_skill_level(SkillCatalog.WHIRLWIND) == 4, "a learned skill keeps its level")
	_expect(restored.player_progression.get_skill_level(SkillCatalog.ARCANE_BOLT) == 1, "every learned skill is restored")
	_expect(restored.player_progression.get_skill_level(SkillCatalog.EXECUTION_STRIKE) == 0, "a skill that was never learned stays unlearned")
	_expect(
		restored.player_progression.experience_to_next_level() == source.player_progression.experience_to_next_level(),
		"the restored level carries the same EXP requirement"
	)
	_expect(restored.player_progression != source.player_progression, "a load restores into its own progression object")

	var adopted = SaveScript.new()
	var hero_progression = adopted.player_progression
	adopted.adopt_player_progression(restored.player_progression)
	_expect(adopted.player_progression == restored.player_progression, "a save can adopt the hero's own progression object")
	adopted.adopt_player_progression(null)
	_expect(adopted.player_progression == restored.player_progression, "adopting null leaves the current object alone")
	_expect(hero_progression != adopted.player_progression, "the object a save created is the one the adopter replaces")


## Damaged character numbers are clamped into their declared domains, never
## trusted — and the level field stays authoritative over the EXP that claims it.
func _test_damaged_character_numbers_are_repaired() -> void:
	var repaired = SaveScript.new()
	_expect(
		repaired.load_save_data({
			"version": SaveScript.FORMAT_VERSION,
			"level": 0,
			"experience": "not a number",
			"gold": -500,
			"skill_points": -3,
			"skill_levels": {"whirlwind": 99, "not_a_skill": 2, "": 3, "arcane_bolt": 0, 7: 4},
		}),
		"a payload with damaged character numbers still loads"
	)
	_expect(repaired.player_progression.level == 1, "a level below 1 is raised to 1")
	_expect(repaired.player_progression.experience == 0, "unusable EXP restores nothing")
	_expect(repaired.player_progression.gold == 0, "negative gold is repaired to zero")
	_expect(repaired.player_progression.skill_points == 0, "negative skill points are repaired to zero")
	_expect(
		repaired.player_progression.get_skill_level(SkillCatalog.WHIRLWIND) == SkillDefinition.MAX_LEVEL,
		"a skill level past the definition's cap is clamped"
	)
	_expect(repaired.player_progression.get_skill_level(&"not_a_skill") == 2, "an id this build cannot name is kept (stale, not corrupt)")
	_expect(not repaired.player_progression.skill_levels.has(&""), "an empty skill id is dropped")
	_expect(not repaired.player_progression.skill_levels.has(SkillCatalog.ARCANE_BOLT), "a level-0 entry is not stored")
	_expect(repaired.player_progression.skill_levels.size() == 2, "exactly the usable skill entries are restored")

	# EXP lives inside one level: add_experience() always leaves it below the
	# requirement, so an amount at or past it is damage. The level the file declares
	# is kept and the excess is capped, rather than turned into free levels (and free
	# skill points) the player never earned.
	var overflowing = SaveScript.new()
	_expect(
		overflowing.load_save_data({"version": SaveScript.FORMAT_VERSION, "level": 1, "experience": 999999}),
		"a payload with overflowing EXP loads"
	)
	_expect(overflowing.player_progression.level == 1, "the declared level is kept when the EXP claims more")
	_expect(
		overflowing.player_progression.experience < overflowing.player_progression.experience_to_next_level(),
		"EXP past the level's requirement is capped instead of granting free levels"
	)
	_expect(overflowing.player_progression.skill_points == 0, "no free skill point is granted by the repair")

	# A file written before character numbers were stored (version 1 / 2) still
	# loads: those builds reset the growth on every launch, so "no recorded growth"
	# is exactly what they could have saved.
	var legacy = SaveScript.new()
	legacy.player_progression.level = 7
	legacy.player_progression.gold = 500
	legacy.player_progression.skill_points = 2
	_expect(
		legacy.load_save_data({"version": 2, "current_stage_number": 6, "highest_stage_reached": 6}),
		"a save from before character persistence still loads"
	)
	_expect(legacy.player_progression.level == 1, "it restores a fresh level rather than keeping the live one")
	_expect(legacy.player_progression.gold == 0, "it restores an empty purse")
	_expect(legacy.player_progression.skill_points == 0, "it restores no skill points")


## The same autosave rule the progress, the items and the Sub Heroes follow: the
## save subscribes to the character's own announcements, so an EXP award, a
## level-up, a purchase and a skill upgrade persist with no gameplay path (and no UI
## panel) asking for a save.
func _test_autosave_follows_character_progression() -> void:
	SaveScript.delete_save_at(SCRATCH_PATH)
	var save = SaveScript.new(null, null, SCRATCH_PATH)
	var flow = StageFlowScript.new(save.progress)
	save.bind(flow)
	_expect(not save.has_save(), "binding alone writes nothing")

	save.player_progression.add_gold(120)
	_expect(save.has_save(), "an awarded coin wrote the save (no gameplay path asked)")
	_expect(int(_read_scratch().get("gold", -1)) == 120, "the purse on disk is the one that was awarded")

	save.player_progression.add_experience(150)
	_expect(int(_read_scratch().get("level", -1)) == 2, "the level-up is on disk")
	_expect(int(_read_scratch().get("experience", -1)) == 50, "the EXP left inside the new level is on disk")
	_expect(int(_read_scratch().get("skill_points", -1)) == 1, "the skill point the level-up granted is on disk")

	_expect(save.player_progression.upgrade_skill(SkillCatalog.WHIRLWIND), "the skill point learns a skill")
	var skills: Dictionary = _read_scratch().get("skill_levels", {}) as Dictionary
	_expect(int(skills.get("whirlwind", 0)) == 1, "the learned skill is on disk")
	_expect(int(_read_scratch().get("skill_points", -1)) == 0, "the spent skill point is on disk")

	_expect(save.player_progression.spend_gold(20), "a purchase spends gold")
	_expect(int(_read_scratch().get("gold", -1)) == 100, "a purchase writes the purse to disk")

	var reloaded = SaveScript.new(null, null, SCRATCH_PATH)
	_expect(reloaded.load(), "the autosaved file loads")
	_expect(reloaded.player_progression.level == 2, "the restored session keeps the level")
	_expect(reloaded.player_progression.gold == 100, "the restored session keeps the purse")
	_expect(
		reloaded.player_progression.get_skill_level(SkillCatalog.WHIRLWIND) == 1,
		"the restored session keeps the learned skill"
	)

	var writes: Array = []
	save.saved.connect(func(_save_path: String) -> void: writes.append(1))
	save.player_progression.add_gold(0)
	_expect(writes.is_empty(), "an award of nothing changes nothing and writes nothing")
	save.player_progression.spend_gold(0)
	_expect(writes.is_empty(), "spending nothing changes nothing and writes nothing")
	SaveScript.delete_save_at(SCRATCH_PATH)


## A fixture item built from the production model: identity, a rolled affix and a
## definition, so the round trip is exercised on real data rather than on scalars.
func _create_item(instance_id: String, slot: int, rarity: int, item_level: int, unique_effect_id: StringName) -> EquipmentInstance:
	var definition := EquipmentDefinitionScript.new()
	definition.definition_id = StringName("def_%s" % instance_id)
	definition.display_name = "Smoke %s" % instance_id
	definition.slot = slot
	definition.rarity = rarity
	definition.item_level = item_level
	definition.unique_effect_id = unique_effect_id
	definition.description = "Save smoke test fixture."
	var item := EquipmentInstanceScript.new()
	item.instance_id = StringName(instance_id)
	item.definition = definition
	var affix := EquipmentAffixScript.new()
	affix.stat_id = &"attack"
	affix.value = 7.0
	affix.roll_ratio = 0.75
	affix.display_name = "Attack"
	item.affixes.append(affix)
	return item


## A slot-less consumable, the other item shape the bag can hold.
func _create_potion(instance_id: String, item_level: int) -> EquipmentInstance:
	var item := _create_item(instance_id, -1, EquipmentRarity.COMMON, item_level, &"")
	item.definition.is_consumable = true
	item.definition.heal_ratio = 0.35
	item.affixes.clear()
	return item


func _find_item(items: Array[EquipmentInstance], instance_id: StringName) -> EquipmentInstance:
	for item in items:
		if item != null and item.instance_id == instance_id:
			return item
	return null


func _has_instance(items: Array[EquipmentInstance], instance_id: StringName) -> bool:
	return _find_item(items, instance_id) != null


## The payload currently on disk (empty when the file is missing or damaged).
func _read_scratch() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCRATCH_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


## One id list of the payload currently on disk.
func _scratch_list(key: String) -> Array:
	var value: Variant = _read_scratch().get(key, [])
	return value as Array if value is Array else []


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
