extends SceneTree

## Phase 2 smoke test: StageDatabase + Forest data + stage lookup.
## Run headless: godot --headless --path . -s res://tests/stage_database_smoke_test.gd
##
## Verifies the Coding Plan Rev 2 architecture claim: 10 (or 10,000) stages are
## expressed by ONE compact authored StageDatabase resource — never by one
## .tres per stage.
##
## Phase 7.6 adds the RANGE model: an area is `first_stage .. get_last_stage()` on
## one global, never-resetting stage counter, so stage 11 is looked up as the
## second area's stage 11 rather than as "stage 1 of area 2".

const StageDatabaseScript = preload("res://scripts/data/stage_database.gd")
const StageTypeScript = preload("res://scripts/data/stage_type.gd")
const StageDataScript = preload("res://scripts/data/stage_data.gd")
const FOREST_PATH := "res://resources/stage_databases/forest.tres"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_forest_database()
	_test_lookup_apis()
	_test_unknown_lookups_return_null()
	_test_stage_ranges()
	_test_range_conflicts()
	_test_synthetic_large_stage_count()
	_test_validation()

	if _failures.is_empty():
		print("StageDatabase / Forest data smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_forest_database() -> void:
	var db: Resource = load(FOREST_PATH)
	_expect(db != null, "forest StageDatabase resource should load from a single .tres")
	if db == null:
		return

	_expect(String(db.get("area_id")) == "forest", "Forest area_id should be 'forest'")
	_expect(db.get("first_stage") == 1, "Forest should start at global stage 1")
	_expect(db.get("stage_count") == 10, "Forest should have 10 stages")
	_expect(db.call("get_last_stage") == 10, "Forest's range should end at global stage 10")
	_expect(db.get("default_stage_type") == StageTypeScript.COMBAT, "Forest default stage type should be COMBAT")
	_expect(bool(db.call("is_valid")), "Forest StageDatabase should be valid")

	var special_count: int = db.get("special_stages").size()
	_expect(special_count == 3, "Forest should author only the 3 non-default special stages (not 10 files)")

	# Every stage 1..10 exists (including the ones produced by the default rule).
	for number in range(1, 11):
		_expect(db.call("get_stage", number) != null, "Forest stage %d should exist" % number)


func _test_lookup_apis() -> void:
	var db: Resource = load(FOREST_PATH)
	_expect(db != null, "forest StageDatabase should be loadable for lookup tests")
	if db == null:
		return

	# Required acceptance mapping (by stage_number).
	var expected := {
		1: StageTypeScript.COMBAT,
		2: StageTypeScript.COMBAT,
		3: StageTypeScript.COMBAT,
		4: StageTypeScript.COMBAT,
		5: StageTypeScript.COMBAT,
		6: StageTypeScript.COMBAT,
		7: StageTypeScript.COMBAT,
		8: StageTypeScript.TOWN,
		9: StageTypeScript.COMBAT,
		10: StageTypeScript.BOSS,
	}
	for number in expected:
		var stage: Resource = db.call("get_stage", number)
		_expect(stage != null, "get_stage(%d) should return a stage" % number)
		if stage == null:
			continue
		_expect(stage.get("stage_type") == expected[number], "Forest stage %d type should be %s" % [number, StageTypeScript.get_display_name(expected[number])])

	# Id-based lookup: canonical ids use zero-padded stage numbers.
	_expect_type_of(db.call("get_stage_by_id", "forest_001"), StageTypeScript.COMBAT, "get_stage_by_id('forest_001') should be COMBAT")
	_expect_type_of(db.call("get_stage_by_id", "forest_006"), StageTypeScript.COMBAT, "get_stage_by_id('forest_006') should be COMBAT")
	_expect_type_of(db.call("get_stage_by_id", "forest_008"), StageTypeScript.TOWN, "get_stage_by_id('forest_008') should be TOWN")
	_expect_type_of(db.call("get_stage_by_id", "forest_010"), StageTypeScript.BOSS, "get_stage_by_id('forest_010') should be BOSS")

	# Zero-padding is tolerated by id lookups.
	_expect_type_of(db.call("get_stage_by_id", "forest_6"), StageTypeScript.COMBAT, "get_stage_by_id('forest_6') should still be COMBAT")
	_expect_type_of(db.call("get_stage_by_id", "forest_1"), StageTypeScript.COMBAT, "get_stage_by_id('forest_1') should still be COMBAT")

	# Static cross-area convenience lookups (global stage numbers).
	_expect_type_of(StageDatabaseScript.lookup(6), StageTypeScript.COMBAT, "StageDatabase.lookup(6) should be COMBAT")
	_expect_type_of(StageDatabaseScript.lookup_stage("forest_006"), StageTypeScript.COMBAT, "StageDatabase.lookup_stage('forest_006') should be COMBAT")
	_expect_type_of(StageDatabaseScript.lookup_stage("forest_008"), StageTypeScript.TOWN, "StageDatabase.lookup_stage('forest_008') should be TOWN")
	_expect_type_of(StageDatabaseScript.lookup_stage("forest_010"), StageTypeScript.BOSS, "StageDatabase.lookup_stage('forest_010') should be BOSS")

	# Canonical id of the materialized stage 6 is forest_006.
	var stage_6: Resource = db.call("get_stage", 6)
	_expect(stage_6 != null and String(stage_6.get("id")) == "forest_006", "stage 6 canonical id should be forest_006")


func _test_unknown_lookups_return_null() -> void:
	var db: Resource = load(FOREST_PATH)
	_expect(db != null, "forest StageDatabase should be loadable for unknown-id tests")
	if db == null:
		return

	_expect(db.call("get_stage", 0) == null, "get_stage(0) should return null")
	_expect(db.call("get_stage", 11) == null, "get_stage(11) should return null (past Forest's 10)")
	_expect(db.call("get_stage", -3) == null, "get_stage(-3) should return null")
	_expect(db.call("get_stage_by_id", "forest_999999") == null, "get_stage_by_id('forest_999999') should return null")
	_expect(db.call("get_stage_by_id", "forest_") == null, "get_stage_by_id('forest_') should return null")
	_expect(db.call("get_stage_by_id", "swamp_001") == null, "id from another area should return null on the forest db")
	_expect(StageDatabaseScript.lookup_stage("forest_999999") == null, "lookup_stage('forest_999999') should return null")
	_expect(StageDatabaseScript.lookup_stage("swamp_001") == null, "lookup_stage('swamp_001') should return null (area not authored yet)")
	_expect(StageDatabaseScript.lookup(999) == null, "lookup(999) should return null (no area covers it)")
	_expect(StageDatabaseScript.load_area(&"swamp") == null, "load_area('swamp') should return null before a Swamp db exists")


func _test_stage_ranges() -> void:
	# An area is a RANGE on the one global stage counter. Stage 11 belongs to the
	# area that authors the range starting at 11 — it is never "stage 1" again.
	var forest: StageDatabase = StageDatabaseScript.database_for_stage(6)
	_expect(forest != null, "global stage 6 should resolve to an authored area")
	if forest == null:
		return
	_expect(String(forest.area_id) == "forest", "global stage 6 should resolve to the forest area")
	_expect(String(StageDatabaseScript.area_for_stage(1)) == "forest", "the first forest stage resolves to forest")
	_expect(String(StageDatabaseScript.area_for_stage(10)) == "forest", "the last forest stage still resolves to forest")
	_expect(StageDatabaseScript.database_for_stage(11) == null, "stage 11 is covered by no area yet")
	_expect(String(StageDatabaseScript.area_for_stage(11)) == "", "so its derived area is empty")
	_expect(StageDatabaseScript.lookup(6) != null, "global lookup(6) finds an authored stage")
	_expect(StageDatabaseScript.lookup(11) == null, "global lookup(11) finds nothing while no area covers it")

	# A second area is expressed by its RANGE alone: same code path, same lazy
	# materialization, same id format, no second numbering space.
	var second := StageDatabaseScript.new() as StageDatabase
	second.area_id = &"forest2"
	second.display_name = "Forest 2"
	second.first_stage = 11
	second.stage_count = 10
	_expect(second.get_last_stage() == 20, "the range 11 + 10 stages ends at global stage 20")
	_expect(bool(second.is_valid()), "a well-formed range passes validation")
	_expect(not second.covers(10), "stage 10 is before the range")
	_expect(second.covers(11) and second.covers(20), "stages 11 and 20 are inside the range")
	_expect(not second.covers(21), "stage 21 is past the range")
	_expect(second.get_stage(10) == null, "a number before the range has no stage here")
	_expect(second.get_stage(21) == null, "a number after the range has no stage here")

	var stage_11: StageData = second.get_stage(11)
	_expect(stage_11 != null, "stage 11 should exist inside the range")
	if stage_11 != null:
		_expect(String(stage_11.id) == "forest2_011", "ids carry the GLOBAL stage number (got %s)" % stage_11.id)
		_expect(stage_11.stage_number == 11, "the materialized stage keeps its global number")
	var stage_20: StageData = second.get_stage(20)
	_expect(stage_20 != null and String(stage_20.id) == "forest2_020", "the range's last stage ids as forest2_020")
	_expect(second.get_stage_by_id("forest2_013") != null, "id lookup works for a number inside the range")
	_expect(second.get_stage_by_id("forest2_003") == null, "an id for a number before the range resolves to nothing")


func _test_range_conflicts() -> void:
	# Two areas must never claim the same global stage number: a number has to
	# resolve to exactly one area. Overlap is a cross-area property, so it is
	# checked against the whole authored set, not one resource at a time.
	var forest := StageDatabaseScript.new() as StageDatabase
	forest.area_id = &"forest"
	forest.first_stage = 1
	forest.stage_count = 10
	var overlapping := StageDatabaseScript.new() as StageDatabase
	overlapping.area_id = &"overlap"
	overlapping.first_stage = 5
	overlapping.stage_count = 10
	var disjoint := StageDatabaseScript.new() as StageDatabase
	disjoint.area_id = &"later"
	disjoint.first_stage = 21
	disjoint.stage_count = 10

	var authored: Array[StageDatabase] = [forest, overlapping]
	var conflicts: PackedStringArray = StageDatabaseScript.collect_range_conflicts(authored)
	_expect(conflicts.size() == 1, "one overlapping pair should report exactly one conflict (got %d)" % conflicts.size())
	_expect(_contains(conflicts, "overlap"), "the conflict should be reported as an overlap")

	authored.append(disjoint)
	_expect(StageDatabaseScript.collect_range_conflicts(authored).size() == 1, "a disjoint third area adds no conflict")
	var single: Array[StageDatabase] = [forest]
	_expect(StageDatabaseScript.collect_range_conflicts(single).is_empty(), "a single area cannot conflict with itself")
	_expect(StageDatabaseScript.get_authored_range_conflicts().is_empty(), "the shipped areas must have disjoint ranges")


func _test_synthetic_large_stage_count() -> void:
	# Scalability: the SAME lookup architecture must describe 10_000 stages
	# without creating 10_000 files. Build it in code; nothing is enumerated.
	var db: Resource = StageDatabaseScript.new()
	db.set("area_id", &"synthetic")
	db.set("stage_count", 10000)
	db.set("default_stage_type", StageTypeScript.COMBAT)
	_expect(bool(db.call("is_valid")), "synthetic 10_000-stage db should be valid with no files")

	var stage_10000: Resource = db.call("get_stage", 10000)
	_expect(stage_10000 != null, "get_stage(10000) should exist")
	_expect(stage_10000.get("stage_type") == StageTypeScript.COMBAT, "synthetic stage 10000 should default to COMBAT")
	_expect(db.call("get_stage", 10001) == null, "synthetic get_stage(10001) should return null")

	# A sparse override still wins at scale.
	var boss: Resource = StageDataScript.new()
	boss.set("stage_number", 5000)
	boss.set("stage_type", StageTypeScript.BOSS)
	boss.set("display_name", "Synthetic Boss")
	db.get("special_stages").append(boss)
	_expect(bool(db.call("is_valid")), "synthetic db with one override should stay valid")
	var stage_5000: Resource = db.call("get_stage", 5000)
	_expect(stage_5000 != null, "get_stage(5000) should exist")
	_expect(stage_5000.get("stage_type") == StageTypeScript.BOSS, "synthetic stage 5000 override should be BOSS")
	_expect(String(stage_5000.get("id")) == "synthetic_05000", "synthetic stage 5000 id should be synthetic_05000 (pad width 5)")


func _test_validation() -> void:
	var db: Resource = StageDatabaseScript.new()
	db.set("area_id", &"broken")
	db.set("stage_count", 10)
	db.set("default_stage_type", 999)
	_expect(not bool(db.call("is_valid")), "invalid default_stage_type should fail validation")
	var errors: PackedStringArray = db.call("get_validation_errors")
	_expect(_contains(errors, "invalid default_stage_type"), "validation should report the bad default_stage_type")

	var dup_db: Resource = StageDatabaseScript.new()
	dup_db.set("area_id", &"broken_dup")
	dup_db.set("stage_count", 10)
	var a: Resource = StageDataScript.new()
	a.set("stage_number", 6)
	a.set("stage_type", StageTypeScript.COMBAT)
	var b: Resource = StageDataScript.new()
	b.set("stage_number", 6)
	b.set("stage_type", StageTypeScript.TOWN)
	dup_db.get("special_stages").append(a)
	dup_db.get("special_stages").append(b)
	var dup_errors: PackedStringArray = dup_db.call("get_validation_errors")
	_expect(_contains(dup_errors, "duplicate special stage number"), "duplicate special stage numbers should be reported")

	var out_of_range: Resource = StageDataScript.new()
	out_of_range.set("stage_number", 42)
	out_of_range.set("stage_type", StageTypeScript.BOSS)
	var oor_db: Resource = StageDatabaseScript.new()
	oor_db.set("area_id", &"broken_range")
	oor_db.set("stage_count", 10)
	oor_db.get("special_stages").append(out_of_range)
	var oor_errors: PackedStringArray = oor_db.call("get_validation_errors")
	_expect(_contains(oor_errors, "out of range"), "special stage outside [first_stage, last_stage] should be reported")

	# A range cannot start before stage 1.
	var bad_first: Resource = StageDatabaseScript.new()
	bad_first.set("area_id", &"broken_first")
	bad_first.set("first_stage", 0)
	var bad_first_errors: PackedStringArray = bad_first.call("get_validation_errors")
	_expect(_contains(bad_first_errors, "first_stage"), "a first_stage below 1 should be reported")

	# An override written with a range-local number is the classic authoring
	# mistake this model removes: it must be rejected, not silently ignored.
	var local_numbering: Resource = StageDatabaseScript.new()
	local_numbering.set("area_id", &"local_numbering")
	local_numbering.set("first_stage", 11)
	local_numbering.set("stage_count", 10)
	var local_boss: Resource = StageDataScript.new()
	local_boss.set("stage_number", 10)
	local_boss.set("stage_type", StageTypeScript.BOSS)
	local_numbering.get("special_stages").append(local_boss)
	_expect(not bool(local_numbering.call("is_valid")), "an override using an area-local number should be invalid")


func _expect_type_of(stage: Resource, wanted_type: int, description: String) -> void:
	if stage == null:
		_expect(false, "%s (returned null)" % description)
		return
	_expect(stage.get("stage_type") == wanted_type, description)


func _contains(messages: PackedStringArray, needle: String) -> bool:
	for message in messages:
		if String(message).find(needle) != -1:
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
