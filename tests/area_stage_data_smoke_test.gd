extends SceneTree

## Phase 1 smoke test: AreaData / StageData / StageType data model + validation.
## Run headless: godot --headless --path . -s res://tests/area_stage_data_smoke_test.gd

const StageTypeScript = preload("res://scripts/data/stage_type.gd")
const StageDataScript = preload("res://scripts/data/stage_data.gd")
const AreaDataScript = preload("res://scripts/data/area_data.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _make_stage(id: StringName, number: int, type_id: int) -> Resource:
	var stage: Resource = StageDataScript.new()
	stage.set("id", id)
	stage.set("stage_number", number)
	stage.set("display_name", "Stage %s" % id)
	stage.set("stage_type", type_id)
	return stage


func _run() -> void:
	# --- StageType catalogue ---
	_expect(StageTypeScript.COMBAT == 0, "StageType.COMBAT should be 0")
	_expect(StageTypeScript.BOSS == 3, "StageType.BOSS should be 3 (COMBAT, EVENT, TOWN, BOSS)")
	for type_id in [StageTypeScript.COMBAT, StageTypeScript.EVENT, StageTypeScript.TOWN, StageTypeScript.BOSS]:
		_expect(StageTypeScript.is_valid(type_id), "StageType %d should be valid" % type_id)
	_expect(not StageTypeScript.is_valid(999), "unlisted type 999 should be invalid")
	_expect(not StageTypeScript.get_display_name(StageTypeScript.EVENT).is_empty(), "EVENT should have a display name")

	# --- StageData validation ---
	var valid_stage := _make_stage(&"forest_01", 1, StageTypeScript.COMBAT)
	_expect(bool(valid_stage.call("is_valid")), "well-formed stage should be valid")

	var empty_id := _make_stage(&"", 1, StageTypeScript.COMBAT)
	_expect(not bool(empty_id.call("is_valid")), "stage with empty id should be invalid")

	var bad_number := _make_stage(&"forest_01", 0, StageTypeScript.COMBAT)
	_expect(not bool(bad_number.call("is_valid")), "stage with stage_number 0 should be invalid")

	var bad_type := _make_stage(&"forest_01", 1, 999)
	_expect(not bool(bad_type.call("is_valid")), "stage with unknown stage_type should be invalid")

	# --- AreaData: valid area ---
	var area: Resource = AreaDataScript.new()
	area.set("id", &"forest")
	area.set("display_name", "Forest")
	area.get("stages").append(valid_stage)
	area.get("stages").append(_make_stage(&"forest_02", 2, StageTypeScript.COMBAT))
	area.get("stages").append(_make_stage(&"forest_06", 6, StageTypeScript.EVENT))
	area.get("stages").append(_make_stage(&"forest_08", 8, StageTypeScript.TOWN))
	area.get("stages").append(_make_stage(&"forest_10", 10, StageTypeScript.BOSS))
	_expect(bool(area.call("is_valid")), "well-formed area should be valid")

	# --- AreaData: empty area id ---
	var no_area_id: Resource = AreaDataScript.new()
	_expect(not bool(no_area_id.call("is_valid")), "area with empty id should be invalid")

	# --- AreaData: duplicate stage id ---
	var dup_id: Resource = AreaDataScript.new()
	dup_id.set("id", &"forest")
	dup_id.get("stages").append(_make_stage(&"forest_01", 1, StageTypeScript.COMBAT))
	dup_id.get("stages").append(_make_stage(&"forest_01", 2, StageTypeScript.COMBAT))
	_expect(not bool(dup_id.call("is_valid")), "area with duplicate stage id should be invalid")
	var dup_id_errors: PackedStringArray = dup_id.call("get_validation_errors")
	_expect(_contains(dup_id_errors, "duplicate stage id"), "duplicate-id area should report a duplicate-id message")

	# --- AreaData: duplicate stage number ---
	var dup_number: Resource = AreaDataScript.new()
	dup_number.set("id", &"forest")
	dup_number.get("stages").append(_make_stage(&"forest_01", 1, StageTypeScript.COMBAT))
	dup_number.get("stages").append(_make_stage(&"forest_02", 1, StageTypeScript.COMBAT))
	_expect(not bool(dup_number.call("is_valid")), "area with duplicate stage number should be invalid")

	if _failures.is_empty():
		print("Area / Stage data smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _contains(messages: PackedStringArray, needle: String) -> bool:
	for message in messages:
		if String(message).find(needle) != -1:
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
