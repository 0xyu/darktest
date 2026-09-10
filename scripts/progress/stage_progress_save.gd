class_name StageProgressSave
extends RefCounted

## The player-side PROGRESS SAVE: the single object that owns the two player-state
## objects and the only code that writes or reads them on disk.
##
## Phase 8 of the Area / Stage / StageType system (Coding Plan Rev 3.1).
##
## Why ONE object owns both
## -----------------------
## PlayerProgress ("where am I / which stages are cleared / how far did I get") and
## AuthoredContentState ("which one-shot content is used up") stay separate classes
## — they answer different questions — but they are restored TOGETHER or not at
## all. A load that restored only one of them would hand the player a state they
## never had: a cleared stage whose chest is back, or a consumed chest on a stage
## that was never played. That is why this is the ONE mount point the host injects
## from, instead of each system loading its own half.
##
## What is stored: identifiers and scalars only
## -------------------------------------------
##   version                 format version, so a later change can migrate instead
##                           of guessing
##   current_stage_number    the ONE position (a GLOBAL stage number)
##   highest_stage_reached   the monotonic unlock ceiling
##   completed_stages        canonical stage ids ("forest_006"), never Resource refs
##   consumed_content        "<stage_id>:<content_id>" keys ("forest_006:cache")
##
## Deliberately NOT stored:
##   * any area field — the area is DERIVED from the position
##     (StageDatabase.area_for_stage). Storing it would put a second copy of "where
##     am I" back into the save, which is the drift the Global Stage Range model
##     removed.
##   * StageDatabase / StageData themselves — static authored data comes from the
##     .tres files. Snapshotting it would mean rewriting every save whenever content
##     is authored, and would tie a save to the content that existed when it was
##     written.
##   * any area-local stage number as a "position": the global number is the only
##     numbering the game has.
##
## A position past every authored area (the endless tail, e.g. 51+) is a LEGAL
## save and is never pulled back into a range — that is the normal state after the
## authored content runs out. Only the field's own declared domain is enforced
## (see _sanitize_position), so a hand-damaged file cannot move the game somewhere
## no stage number can describe.
##
## Autosave
## --------
## bind() subscribes to the objects that announce their own changes: StageFlow owns
## the ONLY writer of PlayerProgress, and AuthoredContentState announces
## consumption. Every path that moves the player or records progress therefore
## persists — boot, a map / DEV entry, an advance, a defeat rollback, a FARMING
## re-spawn, a town visit and a consumed chest — without a save call in any of
## those paths (a caller that forgot one would silently lose progress).
##
## Format
## ------
## JSON, written whole. The file is tiny (a handful of identifiers), the triggers
## are all low-frequency player events, so there is no incremental / partial write.

const PlayerProgressScript := preload("res://scripts/progress/player_progress.gd")
const AuthoredContentStateScript := preload("res://scripts/progress/authored_content_state.gd")

## Bumped only when the stored shape changes in a way that needs migration.
const FORMAT_VERSION := 1
const SAVE_DIR := "user://save/"
const SAVE_FILE_NAME := "stage_progress.json"
const DEFAULT_SAVE_PATH := SAVE_DIR + SAVE_FILE_NAME
## The declared domain of a stage number, matching PlayerProgress's own export
## range. A saved number outside it is damage, not progress.
const MIN_STAGE_NUMBER := 1
const MAX_STAGE_NUMBER := 999999

## Raised after the file was written, so a caller (or a test) can observe a save
## without reaching into the filesystem.
signal saved(save_path: String)
## Raised when an existing file could not be used. The player keeps the fresh
## state instead of a half-restored one, and the reason is reported rather than
## silently swallowing a damaged save.
signal load_rejected(reason: String)

## Player map / stage progress (position, unlock ceiling, completions).
var progress: PlayerProgress
## Which one-shot authored content has been consumed.
var content_state: AuthoredContentState
## Where this save is read from / written to.
var path: String = ""

static var _default_path_override: String = ""
var _bound_flow: StageFlow = null


## Builds a save around the two state objects. Passing existing objects injects
## them (the host builds the flow and the content controller from this object's
## instances, so nothing can end up with a second copy of the player's state).
func _init(
	source_progress: PlayerProgress = null,
	source_content_state: AuthoredContentState = null,
	save_path: String = ""
) -> void:
	progress = source_progress if source_progress != null else PlayerProgressScript.new()
	content_state = source_content_state if source_content_state != null else AuthoredContentStateScript.new()
	path = save_path if not save_path.is_empty() else default_path()


## Where the game persists progress: the shipped default, or the scratch path a
## test harness has redirected it to.
static func default_path() -> String:
	return _default_path_override if not _default_path_override.is_empty() else DEFAULT_SAVE_PATH


## Redirects the default save path for the rest of the process (runtime only —
## nothing is written into project.godot). Used by the headless UI harness, which
## mounts the REAL game scene and must therefore neither read nor write the
## player's own save.
static func set_default_path(save_path: String) -> void:
	_default_path_override = save_path


## The GLOBAL stage number this save left the player on. The host resumes here.
func get_resume_stage_number() -> int:
	return clampi(progress.current_stage_number, MIN_STAGE_NUMBER, MAX_STAGE_NUMBER)


## Connects the autosave triggers to the object that writes progress and the one
## that records consumed content. Safe to call once, from the host's _ready().
func bind(flow: StageFlow) -> void:
	unbind()
	if flow == null:
		return
	_bound_flow = flow
	if not flow.progress_changed.is_connected(_on_progress_changed):
		flow.progress_changed.connect(_on_progress_changed)
	if not content_state.content_consumed.is_connected(_on_content_consumed):
		content_state.content_consumed.connect(_on_content_consumed)


## Drops the autosave subscriptions (a host tearing down, or a rebind).
func unbind() -> void:
	if _bound_flow != null and is_instance_valid(_bound_flow) \
		and _bound_flow.progress_changed.is_connected(_on_progress_changed):
		_bound_flow.progress_changed.disconnect(_on_progress_changed)
	_bound_flow = null
	if content_state != null and content_state.content_consumed.is_connected(_on_content_consumed):
		content_state.content_consumed.disconnect(_on_content_consumed)


## The exact payload written to disk, as a plain Dictionary.
func to_save_data() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"current_stage_number": clampi(progress.current_stage_number, MIN_STAGE_NUMBER, MAX_STAGE_NUMBER),
		"highest_stage_reached": clampi(progress.highest_stage_reached, MIN_STAGE_NUMBER, MAX_STAGE_NUMBER),
		"completed_stages": _sorted_string_keys(progress.completed_stages),
		"consumed_content": _sorted_string_keys(content_state.consumed),
	}


## Restores the two state objects from a payload and returns true. Returns false
## (changing nothing) when the payload is not a save this build can use.
##
## Validation, in the order it exists:
##   * a format version must be present and must not be NEWER than this build —
##     a file from a later version is refused rather than half-read
##   * the position must be inside the stage-number domain (a damaged value is
##     clamped, the rest of the save is kept)
##   * the unlock ceiling must be at least the position: it is RAISED when it is
##     short (mark_reached), never satisfied by lowering the position
##   * the two id sets accept Strings only; anything else is dropped
## Ids that no authored area resolves any more are KEPT: after a re-authored
## stage range they are stale, not corrupt, and silently discarding a player's
## completions would be worse than carrying an id nothing asks about.
func load_save_data(data: Dictionary) -> bool:
	if data.is_empty():
		return _reject("save data is empty")
	var version: int = _to_int(data.get("version"), 0)
	if version < 1:
		return _reject("save data has no format version")
	if version > FORMAT_VERSION:
		return _reject("save format version %d is newer than this build's %d" % [version, FORMAT_VERSION])
	var position: int = _sanitize_position(_to_int(data.get("current_stage_number"), MIN_STAGE_NUMBER))
	var ceiling: int = _sanitize_position(_to_int(data.get("highest_stage_reached"), position))
	progress.current_stage_number = position
	progress.highest_stage_reached = ceiling
	if progress.highest_stage_reached < progress.current_stage_number:
		# A save whose ceiling fell behind its position is repaired by raising the
		# ceiling: the player has demonstrably been where they stand.
		progress.mark_reached(progress.current_stage_number)
	progress.completed_stages.clear()
	for stage_id in _string_list(data.get("completed_stages", [])):
		progress.completed_stages[stage_id] = true
	content_state.consumed.clear()
	for key in _string_list(data.get("consumed_content", [])):
		content_state.consumed[key] = true
	return true


## Writes this save to disk. Returns true on success.
func save() -> bool:
	if path.is_empty():
		push_warning("StageProgressSave has no path to write to.")
		return false
	var directory := path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(directory)
		if directory_error != OK:
			push_warning("StageProgressSave could not create '%s' (error %d)." % [directory, directory_error])
			return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("StageProgressSave could not write '%s' (error %d)." % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(to_save_data(), "\t"))
	file.close()
	saved.emit(path)
	return true


## Reads the save from disk into this object. Returns false (leaving the fresh
## state alone) when there is no file, or when the file cannot be used; the reason
## is reported through load_rejected.
func load() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return _reject("save file '%s' is empty" % path)
	# A JSON instance (rather than JSON.parse_string) so a damaged file reports
	# through load_rejected instead of spilling a parse error into the log.
	var json := JSON.new()
	if json.parse(text) != OK:
		return _reject("save file '%s' is not valid JSON (%s)" % [path, json.get_error_message()])
	if not (json.data is Dictionary):
		return _reject("save file '%s' is not a JSON object" % path)
	return load_save_data(json.data as Dictionary)


func has_save() -> bool:
	return FileAccess.file_exists(path)


func delete_save() -> void:
	delete_save_at(path)


## True when a save file exists at `save_path`.
static func save_exists_at(save_path: String) -> bool:
	return FileAccess.file_exists(save_path)


## Removes a save file (a new game, or a test starting from a clean slate).
## Deleting a file that is not there is not an error.
static func delete_save_at(save_path: String) -> void:
	if not FileAccess.file_exists(save_path):
		return
	var remove_error := DirAccess.remove_absolute(save_path)
	if remove_error != OK:
		push_warning("StageProgressSave could not delete '%s' (error %d)." % [save_path, remove_error])


func _on_progress_changed() -> void:
	save()


func _on_content_consumed(_key: String) -> void:
	save()


## A stage number is accepted anywhere inside the field's declared domain; only a
## value outside it (damage, or a hand-edited file) is pulled to the nearest edge.
func _sanitize_position(stage_number: int) -> int:
	return clampi(stage_number, MIN_STAGE_NUMBER, MAX_STAGE_NUMBER)


func _reject(reason: String) -> bool:
	load_rejected.emit(reason)
	return false


## Sorted String keys of an id -> true dictionary, so the written file is stable
## (and its diffs readable) no matter what order ids were recorded in.
func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in source:
		if key is String and not (key as String).is_empty():
			keys.append(key)
	keys.sort()
	return keys


func _string_list(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array):
		return result
	for entry in (value as Array):
		if entry is String and not (entry as String).is_empty():
			result.append(entry)
	return result


func _to_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return fallback
