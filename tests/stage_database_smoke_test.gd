extends SceneTree

## Phase 2 smoke test: StageDatabase + Forest data + stage lookup.
## Run headless: godot --headless --path . -s res://tests/stage_database_smoke_test.gd
##
## Verifies the Coding Plan Rev 2 architecture claim: 10 (or 10,000) stages are
## expressed by ONE compact authored StageDatabase resource — never by one
## .tres per stage.

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
	_expect(db.get("stage_count") == 10, "Forest should have 10 stages")
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
		6: StageTypeScript.EVENT,
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
	_expect_type_of(db.call("get_stage_by_id", "forest_006"), StageTypeScript.EVENT, "get_stage_by_id('forest_006') should be EVENT")
	_expect_type_of(db.call("get_stage_by_id", "forest_008"), StageTypeScript.TOWN, "get_stage_by_id('forest_008') should be TOWN")
	_expect_type_of(db.call("get_stage_by_id", "forest_010"), StageTypeScript.BOSS, "get_stage_by_id('forest_010') should be BOSS")

	# Zero-padding is tolerated by id lookups.
	_expect_type_of(db.call("get_stage_by_id", "forest_6"), StageTypeScript.EVENT, "get_stage_by_id('forest_6') should still be EVENT")
	_expect_type_of(db.call("get_stage_by_id", "forest_1"), StageTypeScript.COMBAT, "get_stage_by_id('forest_1') should still be COMBAT")

	# Static cross-area convenience lookups.
	_expect_type_of(StageDatabaseScript.lookup("forest", 6), StageTypeScript.EVENT, "StageDatabase.lookup('forest', 6) should be EVENT")
	_expect_type_of(StageDatabaseScript.lookup_stage("forest_006"), StageTypeScript.EVENT, "StageDatabase.lookup_stage('forest_006') should be EVENT")
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
	_expect(StageDatabaseScript.lookup("forest", 999) == null, "lookup('forest', 999) should return null")
	_expect(StageDatabaseScript.load_area(&"swamp") == null, "load_area('swamp') should return null before a Swamp db exists")


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
	a.set("stage_type", StageTypeScript.EVENT)
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
	_expect(_contains(oor_errors, "out of range"), "special stage outside [1, stage_count] should be reported")


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
