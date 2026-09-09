class_name StageDatabase
extends Resource

## Static, author-authored, per-Area stage catalogue.
##
## Phase 2 of the Area / Stage / StageType system (Coding Plan Rev 2).
##
## A StageDatabase is the compact authored description of EVERY stage in one
## Area WITHOUT one `.tres` per stage. It stores the shared base rule
## (stage_count + default_stage_type) plus a sparse set of authored overrides
## for nodes that differ from the default (EVENT / TOWN / BOSS / ...). Stages
## are materialized lazily on lookup, so a single resource can describe 10
## stages or 10,000 stages through the same code path.
##
## Static data only: completion / unlock / player position are PlayerProgress
## concerns and must never be written back into this resource (or into the
## StageData instances it returns).

const StageTypeScript := preload("res://scripts/data/stage_type.gd")
const StageDataScript := preload("res://scripts/data/stage_data.gd")

## Conventional location for per-area databases: resources/stage_databases/<area_id>.tres
const DATABASE_DIR := "res://resources/stage_databases/"
## Minimum zero-pad width of the numeric part of a stage id. Grows to fit the
## magnitude of stage_count so ids stay lexically sortable at any scale.
const MIN_ID_PAD := 3

## Stable Area id this catalogue belongs to, e.g. &"forest".
@export var area_id: StringName = &""
@export var display_name: String = ""
## Total number of stages on the path (1..stage_count). May be very large; no
## per-stage file is required for stage_count to grow.
@export_range(1, 999999, 1) var stage_count: int = 1
## Gameplay type shared by every stage unless it is explicitly overridden.
@export var default_stage_type: int = StageTypeScript.COMBAT
## Sparse authored exceptions. Only stages that differ from default_stage_type
## (or carry authored content such as combat/event data) appear here; they are
## identified by their stage_number.
@export var special_stages: Array[StageData] = []

## stage_number -> materialized StageData (built lazily on first lookup).
var _materialized: Dictionary = {}


## Finds an authored override for `stage_number`, or null. `special_stages` is
## intentionally kept tiny (only nodes that differ from the default rule), so a
## linear scan on a cache miss is negligible and always reflects the current
## authored list.
func _find_override(stage_number: int) -> StageData:
	for stage in special_stages:
		if stage != null and stage.stage_number == stage_number:
			return stage
	return null


func _id_width() -> int:
	return maxi(MIN_ID_PAD, str(stage_count).length())


## Canonical, deterministic stage id for a number, e.g. forest_006 for stage 6.
func _canonical_stage_id(stage_number: int) -> String:
	return "%s_%s" % [String(area_id), str(stage_number).pad_zeros(_id_width())]


## Resolves a stage id / number text to a 1-based stage_number, or -1 if the
## text does not belong to this area. Zero-padding is tolerated so both
## forest_006 and forest_6 resolve to stage 6.
func _parse_stage_number(stage_id: String) -> int:
	var id_text := stage_id
	var area_text := String(area_id)
	if not area_text.is_empty() and id_text.begins_with(area_text + "_"):
		var number_text := id_text.substr(area_text.length() + 1)
		if number_text.is_valid_int():
			return number_text.to_int()
		return -1
	if id_text.is_valid_int():
		return id_text.to_int()
	return -1


## Returns the runtime StageData for `stage_number`, or null when out of range.
## Materialized lazily and cached; authored overrides are duplicated so the
## authored resource is never mutated by callers.
func get_stage(stage_number: int) -> StageData:
	if stage_number < 1 or stage_number > stage_count:
		return null
	if _materialized.has(stage_number):
		return _materialized[stage_number]
	var override := _find_override(stage_number)
	var stage: StageData
	if override != null:
		stage = override.duplicate(false) as StageData
		stage.id = StringName(_canonical_stage_id(stage_number))
		stage.stage_number = stage_number
	else:
		stage = StageDataScript.new()
		stage.id = StringName(_canonical_stage_id(stage_number))
		stage.stage_number = stage_number
		stage.stage_type = default_stage_type
		stage.display_name = "Stage %d" % stage_number
	_materialized[stage_number] = stage
	return stage


## Looks a stage up by its (canonical or zero-padded) id, e.g. "forest_006".
## Returns null when the id does not belong to this area or is out of range.
func get_stage_by_id(stage_id: String) -> StageData:
	var number := _parse_stage_number(stage_id)
	if number < 1:
		return null
	return get_stage(number)


## Human-readable validation messages; empty means this database is valid.
## Validates the database itself and every sparse special override:
##   * area_id non-empty, stage_count >= 1, default_stage_type valid
##   * each special stage has a valid type and a number in [1, stage_count]
##   * special stage numbers are unique
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(area_id).is_empty():
		errors.append("StageDatabase area id must not be empty.")
	if stage_count < 1:
		errors.append("StageDatabase '%s' stage_count must be >= 1." % area_id)
	if not StageTypeScript.is_valid(default_stage_type):
		errors.append("StageDatabase '%s' has invalid default_stage_type %d." % [area_id, default_stage_type])
	var seen_numbers := {}
	for stage in special_stages:
		if stage == null:
			errors.append("StageDatabase '%s' special_stages contains a null entry." % area_id)
			continue
		if not StageTypeScript.is_valid(stage.stage_type):
			errors.append("StageDatabase '%s' special stage %d has invalid stage_type %d." % [area_id, stage.stage_number, stage.stage_type])
		if stage.stage_number < 1 or stage.stage_number > stage_count:
			errors.append("StageDatabase '%s' special stage number %d is out of range [1, %d]." % [area_id, stage.stage_number, stage_count])
		if seen_numbers.has(stage.stage_number):
			errors.append("StageDatabase '%s' has duplicate special stage number %d." % [area_id, stage.stage_number])
		seen_numbers[stage.stage_number] = true
	return errors


func is_valid() -> bool:
	return get_validation_errors().is_empty()


## Loads the authored StageDatabase for an area from the conventional path
## res://resources/stage_databases/<area_id>.tres. Returns null when absent
## (e.g. before an area is authored), without emitting a load error.
static func load_area(area_id: StringName) -> StageDatabase:
	var path := DATABASE_DIR + "%s.tres" % area_id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StageDatabase


## Area + stage_number lookup. Returns null when the area or stage is unknown.
static func lookup(area_id: StringName, stage_number: int) -> StageData:
	var database := load_area(area_id)
	if database == null:
		return null
	return database.get_stage(stage_number)


## Full-id lookup across areas, e.g. lookup_stage("forest_006"). Returns null
## when the area is unknown, the id is malformed, or the stage is out of range.
static func lookup_stage(stage_id: String) -> StageData:
	var area_text := _area_from_stage_id(stage_id)
	if area_text.is_empty():
		return null
	var database := load_area(StringName(area_text))
	if database == null:
		return null
	return database.get_stage_by_id(stage_id)


## Area portion of a full stage id: text before the last "_" (convention: area
## ids must not contain "_").
static func _area_from_stage_id(stage_id: String) -> String:
	var last_sep := stage_id.rfind("_")
	if last_sep < 0:
		return ""
	return stage_id.substr(0, last_sep)
