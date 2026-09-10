class_name StageDatabase
extends Resource

## Static, author-authored, per-Area stage catalogue.
##
## Phase 2 of the Area / Stage / StageType system (Coding Plan Rev 2), extended by
## Phase 7.6 (Global Stage Range model, Rev 3).
##
## A StageDatabase is the compact authored description of EVERY stage in one
## Area WITHOUT one `.tres` per stage. It stores the shared base rule
## (the RANGE the area covers + default_stage_type) plus a sparse set of authored
## overrides for nodes that differ from the default (TOWN / BOSS / ...). Stages
## are materialized lazily on lookup, so a single resource can describe 10 stages
## or 10,000 stages through the same code path.
##
## Stage numbers are GLOBAL
## ------------------------
## There is exactly ONE stage counter in this game and it never resets: stage 11
## follows stage 10 whether or not an area boundary falls between them. An Area is
## therefore a RANGE on that counter (`first_stage .. get_last_stage()`), not a
## second numbering space that restarts at 1. Ranges must not overlap: one stage
## number resolves to at most one area.
##
##   forest    1–10    (first_stage 1,  stage_count 10)
##   forest2   11–20   (first_stage 11, stage_count 10)
##   dungeon   21–50   (first_stage 21, stage_count 30)
##   51+               no area: plain endless stages, derived area is &""
##
## Static data only: completion / unlock / player position are PlayerProgress
## concerns and must never be written back into this resource (or into the
## StageData instances it returns).

const StageTypeScript := preload("res://scripts/data/stage_type.gd")
const StageDataScript := preload("res://scripts/data/stage_data.gd")

## Conventional location for per-area databases: resources/stage_databases/<area_id>.tres
const DATABASE_DIR := "res://resources/stage_databases/"
## Minimum zero-pad width of the numeric part of a stage id. Grows to fit the
## magnitude of the range's last stage so ids stay lexically sortable at any scale.
const MIN_ID_PAD := 3

## Stable Area id this catalogue belongs to, e.g. &"forest".
@export var area_id: StringName = &""
@export var display_name: String = ""
## First GLOBAL stage number this area covers. Areas at the start of the game
## keep the default 1; a later area starts at one past the previous area's end.
@export var first_stage: int = 1
## Length of the range in stages (first_stage .. first_stage + stage_count - 1).
## May be very large; no per-stage file is required for stage_count to grow.
@export_range(1, 999999, 1) var stage_count: int = 1
## Gameplay type shared by every stage unless it is explicitly overridden.
@export var default_stage_type: int = StageTypeScript.COMBAT
## Sparse authored exceptions. Only stages that differ from default_stage_type
## (or carry authored content such as combat data or a content layer) appear
## here; they are identified by their GLOBAL stage_number.
@export var special_stages: Array[StageData] = []

## stage_number -> materialized StageData (built lazily on first lookup).
var _materialized: Dictionary = {}

## Area range table cache. Discovery is a directory scan, so it runs once per
## process instead of once per stage query; see database_for_stage().
static var _area_cache: Array[StageDatabase] = []
static var _area_cache_ready: bool = false
## Explicit area table that replaces discovery while it is active (test seam).
static var _area_override: Array[StageDatabase] = []
static var _area_override_active: bool = false


## Last GLOBAL stage number this area covers.
func get_last_stage() -> int:
	return first_stage + stage_count - 1


## True when `stage_number` (a global number) falls inside this area's range.
func covers(stage_number: int) -> bool:
	return stage_number >= first_stage and stage_number <= get_last_stage()


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
	return maxi(MIN_ID_PAD, str(get_last_stage()).length())


## Canonical, deterministic stage id for a global number, e.g. forest_006 for
## stage 6 and forest2_013 for a stage 13 authored in area forest2.
func _canonical_stage_id(stage_number: int) -> String:
	return "%s_%s" % [String(area_id), str(stage_number).pad_zeros(_id_width())]


## Resolves a stage id / number text to a stage number, or -1 if the text does
## not belong to this area. Zero-padding is tolerated so both forest_006 and
## forest_6 resolve to stage 6.
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


## Returns the runtime StageData for a GLOBAL `stage_number`, or null when the
## number falls outside this area's range. Materialized lazily and cached;
## authored overrides are duplicated so the authored resource is never mutated by
## callers.
func get_stage(stage_number: int) -> StageData:
	if not covers(stage_number):
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
##   * area_id non-empty, first_stage >= 1, stage_count >= 1, default type valid
##   * each special stage has a valid type and a GLOBAL number inside
##     [first_stage, last_stage]
##   * special stage numbers are unique
##
## Cross-area overlap cannot be judged from one resource; use the static
## collect_range_conflicts() / get_authored_range_conflicts() for that.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(area_id).is_empty():
		errors.append("StageDatabase area id must not be empty.")
	if first_stage < 1:
		errors.append("StageDatabase '%s' first_stage must be >= 1 (got %d)." % [area_id, first_stage])
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
		if not covers(stage.stage_number):
			errors.append("StageDatabase '%s' special stage number %d is out of range [%d, %d]." % [area_id, stage.stage_number, first_stage, get_last_stage()])
		if seen_numbers.has(stage.stage_number):
			errors.append("StageDatabase '%s' has duplicate special stage number %d." % [area_id, stage.stage_number])
		seen_numbers[stage.stage_number] = true
	return errors


func is_valid() -> bool:
	return get_validation_errors().is_empty()


# ---------------------------------------------------------------------------
# Area range table (global stage number -> area)
# ---------------------------------------------------------------------------

## Loads the authored StageDatabase for an area from the conventional path
## res://resources/stage_databases/<area_id>.tres. Returns null when absent
## (e.g. before an area is authored), without emitting a load error.
static func load_area(area_id: StringName) -> StageDatabase:
	var path := DATABASE_DIR + "%s.tres" % area_id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StageDatabase


## Every authored database under DATABASE_DIR (valid ones only), sorted by range
## start and then area id, so walking the list walks the progression.
##
## Cached for the process: the range lookup runs on every stage query, and a
## directory scan per query would be wasteful. Call invalidate_cache() after
## authoring a new area while the game is running (an editor session).
static func discovered_databases() -> Array[StageDatabase]:
	if _area_override_active:
		return _area_override.duplicate()
	if not _area_cache_ready:
		_area_cache = _scan_databases()
		_area_cache_ready = true
	return _area_cache.duplicate()


## Drops the cached area range table so the next query re-scans the directory.
static func invalidate_cache() -> void:
	_area_cache.clear()
	_area_cache_ready = false


## Replaces the area table with an explicit set, so a caller can model areas that
## are not authored on disk (the stage-range tests build a second area, 11-20,
## without shipping one). clear_area_table_override() restores discovery.
static func set_area_table_override(databases: Array[StageDatabase]) -> void:
	_area_override = databases.duplicate()
	_area_override_active = true


## Restores the area table to the databases authored on disk.
static func clear_area_table_override() -> void:
	_area_override.clear()
	_area_override_active = false


static func _scan_databases() -> Array[StageDatabase]:
	var databases: Array[StageDatabase] = []
	var dir := DirAccess.open(DATABASE_DIR)
	if dir == null:
		return databases
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var database := load(DATABASE_DIR + file_name) as StageDatabase
			if database != null and database.is_valid():
				databases.append(database)
		file_name = dir.get_next()
	dir.list_dir_end()
	databases.sort_custom(func(a: StageDatabase, b: StageDatabase) -> bool:
		if a.first_stage == b.first_stage:
			return String(a.area_id) < String(b.area_id)
		return a.first_stage < b.first_stage
	)
	return databases


## The authored area whose range covers this GLOBAL stage number, or null when
## no area authors it (the endless tail past the last area).
static func database_for_stage(stage_number: int) -> StageDatabase:
	for database in discovered_databases():
		if database.covers(stage_number):
			return database
	return null


## Area id a GLOBAL stage number belongs to, or &"" when no area covers it.
## Area is always DERIVED from the position, never stored a second time.
static func area_for_stage(stage_number: int) -> StringName:
	var database := database_for_stage(stage_number)
	return database.area_id if database != null else &""


## Global stage lookup: resolves the area whose range covers `stage_number` and
## returns its StageData, or null when no area authors that number.
static func lookup(stage_number: int) -> StageData:
	var database := database_for_stage(stage_number)
	return database.get_stage(stage_number) if database != null else null


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


## Two areas must never claim the same GLOBAL stage number, because a number has
## to resolve to exactly one area. Returns one message per overlapping pair.
static func collect_range_conflicts(databases: Array[StageDatabase]) -> PackedStringArray:
	var conflicts := PackedStringArray()
	for index in range(databases.size()):
		var first: StageDatabase = databases[index]
		if first == null:
			continue
		for other_index in range(index + 1, databases.size()):
			var second: StageDatabase = databases[other_index]
			if second == null:
				continue
			if first.first_stage > second.get_last_stage() or second.first_stage > first.get_last_stage():
				continue
			conflicts.append(
				"Areas '%s' [%d, %d] and '%s' [%d, %d] overlap: a stage number must belong to exactly one area." % [
					first.area_id, first.first_stage, first.get_last_stage(),
					second.area_id, second.first_stage, second.get_last_stage(),
				]
			)
	return conflicts


## Range conflicts among the authored databases on disk (empty when the area
## ranges are disjoint, which is the required authoring invariant).
static func get_authored_range_conflicts() -> PackedStringArray:
	return collect_range_conflicts(discovered_databases())


## Area portion of a full stage id: text before the last "_" (convention: area
## ids must not contain "_").
static func _area_from_stage_id(stage_id: String) -> String:
	var last_sep := stage_id.rfind("_")
	if last_sep < 0:
		return ""
	return stage_id.substr(0, last_sep)
