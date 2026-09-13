class_name StageProgressSave
extends RefCounted

## The player-side SAVE: the single object that owns the player's durable state
## (map progress, consumed authored content, owned items, Sub Heroes) and the only
## code that writes or reads them on disk.
##
## Phase 8 of the Area / Stage / StageType system (Coding Plan Rev 3.1); the player's
## items and Sub Heroes were added by the persistence work (gameplay-spec §17).
##
## Why ONE object owns them all
## ----------------------------
## PlayerProgress ("where am I / which stages are cleared / how far did I get"),
## AuthoredContentState ("which one-shot content is used up"), the item containers
## ("what does the player own") and the Sub Hero progression ("which Sub Heroes,
## at what level, in which slot") stay separate classes — they answer different
## questions — but they are restored TOGETHER or not at all. A load that restored
## only some of them would hand the player a state they never had: a cleared stage
## whose chest is back, a consumed chest on a stage that was never played, or a bag
## holding an item that was sold. That is why this is the ONE mount point the host
## injects from, instead of each system loading its own half.
##
## What is stored: identifiers and scalars only
## -------------------------------------------
##   version                 format version, so a later change can migrate instead
##                           of guessing
##   current_stage_number    the ONE position (a GLOBAL stage number)
##   highest_stage_reached   the monotonic unlock ceiling
##   completed_stages        canonical stage ids ("forest_006"), never Resource refs
##   consumed_content        "<stage_id>:<content_id>" keys ("forest_006:cache")
##   inventory               the player's OWNED ITEMS: equipped gear and bag alike
##                           (an equipped item stays in the ownership list with
##                           `is_equipped` set), as plain item payloads
##   storage                 the warehouse items, same item payloads
##   sub_heroes              the Sub Hero progression payload (owned instances and
##                           active slot ids — see SubHeroProgressionService)
##   level                   the character's own level
##   experience              the progress inside that level
##   gold                    the purse
##   skill_points            the points level-ups granted and nothing has spent yet
##   skill_levels            the learned skills, as a map of skill id -> level
##
## The player's items and Sub Heroes live in state objects this save OWNS
## (EquipmentInventory, StorageInventory, SubHeroProgressionService) and the host
## injects into the hero, exactly like PlayerProgress is injected into the flow.
## The hero and the save therefore share one collection each, so there is no path
## that changes the player's gear without the save being able to see it.
##
## The character's own numbers are the same arrangement, reached from the other
## side: the hero builds its PlayerProgression when it is constructed and the HUD's
## panels bind to THAT resource while the scene is still coming up, so this save
## ADOPTS the hero's object (adopt_player_progression) instead of creating its own.
## One object is shared by both, so an EXP award, a gold award, a purchase, a
## level-up and a skill upgrade all write through the object this file is written
## from. The hero's derived stats (attack, HP, defense) are deliberately NOT stored
## — they are recomputed from the level and the equipped items, which are: once the
## load has landed the host calls
## PlayerController.recompute_stats_from_level_and_equipment(), so a restored session
## fights with the numbers its level and its gear produce (gameplay-spec §10).
##
## Deliberately NOT stored:
##   * any area field — the area is DERIVED from the position
##     (StageDatabase.area_for_stage). Storing it would put a second copy of "where
##     am I" back into the save, which is the drift the Global Stage Range model
##     removed.
##   * StageDatabase / StageData themselves — static authored data comes from the
##     .tres files. Snapshotting it would mean rewriting every save whenever content
##     is authored, and would tie a save to the content that existed when it was
##     written. An ITEM's definition is different: a generated item builds its
##     definition at runtime and has no `.tres` to point at, so it travels inline
##     with the item (see EquipmentDefinition.to_save_data).
##   * any area-local stage number as a "position": the global number is the only
##     numbering the game has.
##   * session-scoped state (combat state, the special-encounter pity, the buyback
##     book, the potion counter) — see gameplay-spec §17.
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
## The player's own state announces itself the same way: the item containers raise
## their inventory / storage changed signals for every pickup, equip, discard,
## store, withdraw and sale, and the Sub Hero progression announces ownership and
## slot changes. So the same rule holds for gear and Sub Heroes — the gameplay
## paths never call save() and can never forget to.
##
## The character's numbers follow it too: PlayerProgression announces every EXP
## award, gold award, skill point and skill level change, so killing an enemy,
## finishing a stage, buying from a shop or learning a skill persists without the
## combat, economy or UI code knowing a save exists.
##
## Format
## ------
## JSON, written whole. The file is small (a few identifiers and the owned items),
## the triggers are all low-frequency player events, so there is no incremental /
## partial write.
##
## Version 2 added the player's items and Sub Heroes. A version 1 file (progress
## only, from a build that predates them) still loads: the missing keys mean the
## player owned nothing, which is exactly what a version 1 build could have saved.
##
## Version 3 added the character's own numbers (level / EXP / gold / skill points /
## skill levels). A version 1 or 2 file still loads on the same argument: those
## builds reset the character's growth on every launch, so "no recorded growth" —
## a level 1 character with an empty purse and no learned skills — is exactly what
## they could have saved.

const PlayerProgressScript := preload("res://scripts/progress/player_progress.gd")
const AuthoredContentStateScript := preload("res://scripts/progress/authored_content_state.gd")
const EquipmentInventoryScript := preload("res://scripts/items/equipment_inventory.gd")
const StorageInventoryScript := preload("res://scripts/items/storage_inventory.gd")
const EquipmentInstanceScript := preload("res://scripts/items/equipment_instance.gd")
const SubHeroProgressionServiceScript := preload("res://scripts/sub_hero/sub_hero_progression_service.gd")
const PlayerProgressionScript := preload("res://scripts/player/player_progression.gd")

## Bumped only when the stored shape changes in a way that needs migration.
const FORMAT_VERSION := 3
const SAVE_DIR := "user://save/"
const SAVE_FILE_NAME := "stage_progress.json"
const DEFAULT_SAVE_PATH := SAVE_DIR + SAVE_FILE_NAME
## The declared domain of a stage number, matching PlayerProgress's own export
## range. A saved number outside it is damage, not progress.
const MIN_STAGE_NUMBER := 1
const MAX_STAGE_NUMBER := 999999
## The declared domain of the character's level and skill points, matching
## PlayerProgression's own export ranges. A saved value outside it is damage, not
## growth.
const MIN_CHARACTER_LEVEL := 1
const MAX_CHARACTER_LEVEL := 999999

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
## The player's owned items: equipped gear and bag contents in one list, each item
## carrying its own `is_equipped` flag. The hero is given THIS object, so the bag
## the HUD shows and the bag that is saved are the same bag.
##
## The container is created with the class defaults (bag 10 slots, warehouse
## effectively unbounded), which is exactly what the hero used to create for
## itself — capacity is configuration, not player state, so it is not stored.
var inventory: EquipmentInventory
## The player's warehouse (never equips; separate from the bag's capacity).
var storage: StorageInventory
## The player's Sub Heroes: owned instances, their levels, duplicates and active
## slot assignment.
var sub_heroes: SubHeroProgressionService
## The CHARACTER's own numbers: level, experience, gold, skill points and the
## learned skill levels. Shared with the hero — see adopt_player_progression.
var player_progression: PlayerProgression
## Where this save is read from / written to.
var path: String = ""

static var _default_path_override: String = ""
var _bound_flow: StageFlow = null


## Builds a save around the player-state objects. Passing existing objects injects
## them (the host builds the flow, the content controller and the hero from this
## object's instances, so nothing can end up with a second copy of the player's
## state).
func _init(
	source_progress: PlayerProgress = null,
	source_content_state: AuthoredContentState = null,
	save_path: String = "",
	source_inventory: EquipmentInventory = null,
	source_storage: StorageInventory = null,
	source_sub_heroes: SubHeroProgressionService = null
) -> void:
	progress = source_progress if source_progress != null else PlayerProgressScript.new()
	content_state = source_content_state if source_content_state != null else AuthoredContentStateScript.new()
	inventory = source_inventory if source_inventory != null else EquipmentInventoryScript.new()
	storage = source_storage if source_storage != null else StorageInventoryScript.new()
	sub_heroes = source_sub_heroes if source_sub_heroes != null else SubHeroProgressionServiceScript.new()
	player_progression = PlayerProgressionScript.new()
	path = save_path if not save_path.is_empty() else default_path()


## Adopts the hero's OWN PlayerProgression instead of carrying the one this save
## created. The hero builds its progression when it is constructed, and the HUD's
## panels bind to that resource while the scene is still coming up (a child is ready
## before its host), so swapping in a second object would leave the skill panel
## listening to an orphan: the player's live skill points would stop reaching the UI.
## One object is shared instead, which also means load() restores the saved numbers
## into the resource the rest of the game already reads.
##
## Called BEFORE load(); passing null is ignored (the created object stays).
func adopt_player_progression(progression: PlayerProgression) -> void:
	if progression == null:
		return
	player_progression = progression


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


## Connects the autosave triggers to the object that writes progress, the one that
## records consumed content, and this save's own player-state containers. Safe to
## call once, from the host's _ready().
func bind(flow: StageFlow) -> void:
	unbind()
	if flow == null:
		return
	_bound_flow = flow
	if not flow.progress_changed.is_connected(_on_progress_changed):
		flow.progress_changed.connect(_on_progress_changed)
	if not content_state.content_consumed.is_connected(_on_content_consumed):
		content_state.content_consumed.connect(_on_content_consumed)
	# Items and Sub Heroes announce themselves: every pickup, equip, discard,
	# store, withdraw, sale, summon and slot change.
	if not inventory.inventory_changed.is_connected(_on_player_state_changed):
		inventory.inventory_changed.connect(_on_player_state_changed)
	if not storage.storage_changed.is_connected(_on_player_state_changed):
		storage.storage_changed.connect(_on_player_state_changed)
	if not sub_heroes.collection_changed.is_connected(_on_player_state_changed):
		sub_heroes.collection_changed.connect(_on_player_state_changed)
	if not sub_heroes.active_slots_changed.is_connected(_on_player_state_changed):
		sub_heroes.active_slots_changed.connect(_on_player_state_changed)
	# The character's numbers announce themselves too: an EXP award and the
	# level-up it may carry, a gold award, a purchase or sale, and a skill upgrade.
	# `level_up` needs no subscription of its own — every level-up is announced by
	# the skill-points signal it grants a point through and by the experience signal
	# that consumed the EXP, which are the two stored fields it changes.
	if not player_progression.experience_changed.is_connected(_on_experience_changed):
		player_progression.experience_changed.connect(_on_experience_changed)
	if not player_progression.gold_changed.is_connected(_on_gold_changed):
		player_progression.gold_changed.connect(_on_gold_changed)
	if not player_progression.skill_points_changed.is_connected(_on_skill_points_changed):
		player_progression.skill_points_changed.connect(_on_skill_points_changed)
	if not player_progression.skill_level_changed.is_connected(_on_skill_level_changed):
		player_progression.skill_level_changed.connect(_on_skill_level_changed)


## Drops the autosave subscriptions (a host tearing down, or a rebind).
func unbind() -> void:
	if _bound_flow != null and is_instance_valid(_bound_flow) \
		and _bound_flow.progress_changed.is_connected(_on_progress_changed):
		_bound_flow.progress_changed.disconnect(_on_progress_changed)
	_bound_flow = null
	if content_state != null and content_state.content_consumed.is_connected(_on_content_consumed):
		content_state.content_consumed.disconnect(_on_content_consumed)
	if inventory != null and inventory.inventory_changed.is_connected(_on_player_state_changed):
		inventory.inventory_changed.disconnect(_on_player_state_changed)
	if storage != null and storage.storage_changed.is_connected(_on_player_state_changed):
		storage.storage_changed.disconnect(_on_player_state_changed)
	if sub_heroes != null:
		if sub_heroes.collection_changed.is_connected(_on_player_state_changed):
			sub_heroes.collection_changed.disconnect(_on_player_state_changed)
		if sub_heroes.active_slots_changed.is_connected(_on_player_state_changed):
			sub_heroes.active_slots_changed.disconnect(_on_player_state_changed)
	if player_progression != null:
		if player_progression.experience_changed.is_connected(_on_experience_changed):
			player_progression.experience_changed.disconnect(_on_experience_changed)
		if player_progression.gold_changed.is_connected(_on_gold_changed):
			player_progression.gold_changed.disconnect(_on_gold_changed)
		if player_progression.skill_points_changed.is_connected(_on_skill_points_changed):
			player_progression.skill_points_changed.disconnect(_on_skill_points_changed)
		if player_progression.skill_level_changed.is_connected(_on_skill_level_changed):
			player_progression.skill_level_changed.disconnect(_on_skill_level_changed)


## The exact payload written to disk, as a plain Dictionary.
func to_save_data() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"current_stage_number": clampi(progress.current_stage_number, MIN_STAGE_NUMBER, MAX_STAGE_NUMBER),
		"highest_stage_reached": clampi(progress.highest_stage_reached, MIN_STAGE_NUMBER, MAX_STAGE_NUMBER),
		"completed_stages": _sorted_string_keys(progress.completed_stages),
		"consumed_content": _sorted_string_keys(content_state.consumed),
		"inventory": _items_to_save_data(inventory.items),
		"storage": _items_to_save_data(storage.items),
		"sub_heroes": sub_heroes.to_save_data(),
		"level": clampi(player_progression.level, MIN_CHARACTER_LEVEL, MAX_CHARACTER_LEVEL),
		"experience": maxi(player_progression.experience, 0),
		"gold": maxi(player_progression.gold, 0),
		"skill_points": clampi(player_progression.skill_points, 0, MAX_CHARACTER_LEVEL),
		"skill_levels": _skill_levels_to_save_data(player_progression.skill_levels),
	}


## Restores the player-state objects from a payload and returns true. Returns false
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
##   * an item entry with no usable definition, or one whose instance id is
##     already restored in the same list, is dropped — an item that cannot be
##     named cannot be displayed, equipped, priced or scored, and two items
##     sharing one id would alias in every lookup the game does
##   * a Sub Hero entry with an unknown hero id, or a duplicate of one already
##     restored, is dropped by SubHeroProgressionService.load_save_data
##   * the character's numbers are clamped into their own declared domains: a level
##     below 1 is raised to 1, EXP at or past the level's requirement is capped,
##     gold and skill points are never negative, a skill level past
##     SkillDefinition.MAX_LEVEL is clamped to it, and a skill entry with no id or a
##     level of 0 (unlearned) is dropped
## Ids that no authored area resolves any more are KEPT: after a re-authored
## stage range they are stale, not corrupt, and silently discarding a player's
## completions would be worse than carrying an id nothing asks about. A learned
## skill id this build cannot name is kept for the same reason.
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
	# The character's own numbers. The level is restored FIRST: the EXP domain
	# depends on it (see below).
	player_progression.level = clampi(
		_to_int(data.get("level"), MIN_CHARACTER_LEVEL), MIN_CHARACTER_LEVEL, MAX_CHARACTER_LEVEL
	)
	# EXP lives INSIDE one level: add_experience() always leaves it below the
	# threshold, so an amount at or past the requirement is damage. The level field
	# is the authoritative one, so the excess is capped rather than converted into
	# levels (and skill points) the player never earned.
	player_progression.experience = clampi(
		_to_int(data.get("experience"), 0), 0, player_progression.experience_to_next_level() - 1
	)
	player_progression.gold = maxi(_to_int(data.get("gold"), 0), 0)
	player_progression.skill_points = clampi(_to_int(data.get("skill_points"), 0), 0, MAX_CHARACTER_LEVEL)
	player_progression.skill_levels = _skill_levels_from_save_data(data.get("skill_levels", {}))
	inventory.restore_items(_items_from_save_data(data.get("inventory", [])))
	storage.restore_items(_items_from_save_data(data.get("storage", [])))
	sub_heroes.load_save_data(_dictionary_field(data.get("sub_heroes", {})))
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


## One handler for all four player-state signals: each of them announces "the
## player's belongings changed", and every one of them means the same thing here —
## write the whole payload again.
func _on_player_state_changed() -> void:
	save()


## The character's growth changed (EXP, gold, skill points or a skill level). Each
## signal carries its own numbers and every one of them means the same thing here —
## write the whole payload again. The payload is written whole, so an event that
## announces two of them (a level-up grants a point AND re-bases the EXP bar) writes
## the same file twice in one beat instead of needing a transaction.
func _on_experience_changed(_current_experience: int, _required_experience: int) -> void:
	save()


func _on_gold_changed(_current_gold: int, _amount: int) -> void:
	save()


func _on_skill_points_changed(_current_skill_points: int) -> void:
	save()


func _on_skill_level_changed(_skill_id: StringName, _new_level: int) -> void:
	save()


## The item list as plain payloads, in the order the player owns them (that order
## is also what decides which item is "first" when a damaged save is repaired).
func _items_to_save_data(source: Array[EquipmentInstance]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in source:
		if item != null:
			result.append(item.to_save_data())
	return result


## Rebuilds an item list from a payload, skipping entries that are not usable
## items and entries whose instance id is already in the list (a damaged payload
## must not produce two items that every lookup would confuse for one).
func _items_from_save_data(value: Variant) -> Array[EquipmentInstance]:
	var result: Array[EquipmentInstance] = []
	if not (value is Array):
		return result
	var seen_ids: Dictionary = {}
	for entry in (value as Array):
		if not (entry is Dictionary):
			continue
		var item := EquipmentInstanceScript.from_save_data(entry as Dictionary)
		if item == null or seen_ids.has(item.instance_id):
			continue
		seen_ids[item.instance_id] = true
		result.append(item)
	return result


## A payload field that must be a Dictionary (an absent or damaged one restores
## nothing instead of aborting the load).
func _dictionary_field(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


## The learned skills as a plain id -> level payload, sorted by id so the written
## file is stable (and its diffs readable). An entry with no usable id, or a level
## outside 1..SkillDefinition.MAX_LEVEL, is dropped: level 0 is "unlearned", which
## is the absence of the entry rather than a value, and a level past the cap is
## damage rather than growth.
func _skill_levels_to_save_data(source: Dictionary) -> Dictionary:
	var validated: Dictionary = {}
	for key in source:
		if not (key is String or key is StringName):
			continue
		var skill_id := String(key)
		var skill_level: int = clampi(_to_int(source[key], 0), 0, SkillDefinition.MAX_LEVEL)
		if skill_id.is_empty() or skill_level <= 0:
			continue
		validated[skill_id] = skill_level
	var sorted_ids: Array = validated.keys()
	sorted_ids.sort()
	var result: Dictionary = {}
	for skill_id in sorted_ids:
		result[skill_id] = validated[skill_id]
	return result


## Rebuilds the learned skills from a payload, with the keys normalized to the
## StringName the live object and every lookup use, and the levels clamped to the
## definition's range.
##
## An id this build's catalog cannot name is KEPT, exactly like a stale stage id in
## completed_stages: it costs nothing, it is never read without a catalog entry to
## ask for it, and a build that learns the skill again would otherwise find the
## player's investment silently deleted. (A Sub Hero id is different: ownership
## drives spawning, so SubHeroProgressionService drops an id it cannot resolve.)
func _skill_levels_from_save_data(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		return result
	var source: Dictionary = value as Dictionary
	for key in source:
		if not (key is String or key is StringName):
			continue
		var skill_id := String(key)
		var skill_level: int = clampi(_to_int(source[key], 0), 0, SkillDefinition.MAX_LEVEL)
		if skill_id.is_empty() or skill_level <= 0:
			continue
		result[StringName(skill_id)] = skill_level
	return result


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
