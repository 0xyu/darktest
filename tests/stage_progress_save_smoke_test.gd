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
##
## The scratch file lives in the project's generated .godot/ folder, so a test run
## never reads or writes a player's real save in user:// and leaves nothing behind.

const SaveScript = preload("res://scripts/progress/stage_progress_save.gd")
const StageFlowScript = preload("res://scripts/systems/stage_flow.gd")

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
