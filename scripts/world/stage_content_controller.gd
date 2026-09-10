class_name StageContentController
extends Node2D

## Runtime for the authored stage CONTENT LAYER: it decides when authored content
## appears on a stage, what stepping onto it does, and when it is used up.
##
## The authored-stage model it implements
## -------------------------------------
##   * a stage is a normal stage first — its battle always runs as usual
##   * only a stage the designer authored carries content, and the content is
##     layered on top of the normal gameplay
##   * content appears whenever the stage starts, no matter HOW it was reached:
##     clicked on the world map, walked into from the previous stage, or ground
##     into by the endless loop. There is no separate "authored stage session"
##   * content is triggered by the hero stepping onto its cell, and that is the
##     ONLY trigger, so an AUTO walker triggers content exactly like a manual
##     press does. Automation never changes what content yields
##   * one-shot content is recorded in AuthoredContentState and never appears
##     again; repeatable content is recreated on every stage start (and resolves
##     at most once per visit, so stepping off and back on cannot farm it)
##
## Where content may appear
## -----------------------
## Only on plain walkable cells that are free of enemies and off the hero's
## arrival lane (the stage starting point and the exit). Content can therefore
## never be triggered merely by entering a stage.

const StageContentScript := preload("res://scripts/data/stage_content.gd")
const AuthoredContentStateScript := preload("res://scripts/progress/authored_content_state.gd")
const StageDatabaseScript := preload("res://scripts/data/stage_database.gd")
const LootGeneratorScript := preload("res://scripts/systems/loot_generator.gd")
const StageContentObjectScript := preload("res://scripts/world/stage_content_object.gd")

## Manhattan distance from the hero's arrival cell within which content is never
## placed, so entering a stage cannot trigger it.
const MIN_DISTANCE_FROM_START := 3

## Raised after a content entry resolved, so the host can report it.
signal content_resolved(description: String)

var _grid: GridMap2D
var _player: PlayerController
var _stage_manager: StageManager
var _flow: StageFlow
var _gold_system: Node
var _state: AuthoredContentState
var _loot_generator

## Placed objects, plus a cell -> object index for O(1) step resolution.
var _objects: Array[StageContentObject] = []
var _cells: Dictionary = {}
## Content already resolved during the CURRENT stage visit (repeatable entries
## resolve once per visit; one-shot entries are additionally persisted).
var _resolved_this_stage: Dictionary = {}
var _active_stage_id: String = ""


## Wires the controller to the scene systems it reads. Safe to call once, from the
## host's _ready().
func configure(
	grid: GridMap2D,
	player: PlayerController,
	stage_manager: StageManager,
	flow: StageFlow,
	gold_system: Node,
	state: AuthoredContentState
) -> void:
	_grid = grid
	_player = player
	_stage_manager = stage_manager
	_flow = flow
	_gold_system = gold_system
	_state = state if state != null else AuthoredContentStateScript.new()
	_loot_generator = LootGeneratorScript.new()
	if _player != null and _player.has_signal("moved") and not _player.moved.is_connected(_on_player_moved):
		_player.moved.connect(_on_player_moved)


func get_state() -> AuthoredContentState:
	return _state


func get_content_count() -> int:
	return _objects.size()


## Cells currently holding content, so callers (and tests) can find them without
## hard-coding positions.
func get_content_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for object in _objects:
		if is_instance_valid(object):
			cells.append(object.cell)
	return cells


func get_content_id_at(cell: Vector2i) -> StringName:
	var object: StageContentObject = _cells.get(cell)
	return object.get_content_id() if object != null else &""


func has_content_at(cell: Vector2i) -> bool:
	return _cells.has(cell)


## Removes every placed object. Called when a stage ends or a new one starts.
func clear_content() -> void:
	for object in _objects:
		if is_instance_valid(object):
			object.queue_free()
	_objects.clear()
	_cells.clear()
	_resolved_this_stage.clear()
	_active_stage_id = ""


## Spawns the authored content for `stage_number` of the area the player is
## currently on, and returns how many entries were placed.
##
## Returns 0 for anything that is not an authored stage: no area entered yet (the
## endless boot loop), an area that does not author this stage number, or a stage
## whose content has all been consumed. Those stages are plain normal stages and
## this method leaves them completely alone.
func spawn_for_stage(stage_number: int) -> int:
	clear_content()
	if _grid == null or _flow == null or _state == null:
		return 0
	var area_id: StringName = _flow.get_current_area_id()
	if area_id.is_empty():
		return 0
	var stage := StageDatabaseScript.lookup(area_id, stage_number)
	if stage == null:
		return 0
	_active_stage_id = String(stage.id)
	var entries: Array[StageContent] = _collect_spawnable_entries(stage)
	if entries.is_empty():
		return 0
	var cells: Array[Vector2i] = _find_placement_cells(entries.size())
	for index in range(mini(cells.size(), entries.size())):
		_place(entries[index], cells[index])
	return _objects.size()


## Authored entries that should exist right now: everything except one-shot
## content that has already been consumed.
func _collect_spawnable_entries(stage: StageData) -> Array[StageContent]:
	var entries: Array[StageContent] = []
	for entry in stage.content:
		if entry == null:
			continue
		if entry.one_shot and _state.is_consumed(_active_stage_id, entry.id):
			continue
		entries.append(entry)
	return entries


## Walkable, unoccupied cells off the arrival lane, spread out with a stride so
## several entries do not all land next to each other.
func _find_placement_cells(count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if _grid == null or count <= 0:
		return result
	var reserved: Array[Vector2i] = []
	if _stage_manager != null and _stage_manager.has_method("get_stage_start_cell"):
		reserved.append(_stage_manager.get_stage_start_cell())
		reserved.append(_stage_manager.get_stage_exit_cell())
	var start_cell: Vector2i = reserved[0] if not reserved.is_empty() else Vector2i.ZERO
	var candidates: Array[Vector2i] = []
	for y in range(_grid.grid_size.y):
		for x in range(_grid.grid_size.x):
			var cell := Vector2i(x, y)
			if not _grid.is_walkable(cell) or _grid.is_occupied(cell):
				continue
			if reserved.has(cell):
				continue
			if absi(cell.x - start_cell.x) + absi(cell.y - start_cell.y) <= MIN_DISTANCE_FROM_START:
				continue
			candidates.append(cell)
	if candidates.is_empty():
		return result
	var stride: int = maxi(candidates.size() / maxi(count, 1), 1)
	for index in range(count):
		var cell: Vector2i = candidates[mini(index * stride, candidates.size() - 1)]
		if not result.has(cell):
			result.append(cell)
	return result


func _place(entry: StageContent, cell: Vector2i) -> void:
	var object := StageContentObjectScript.new() as StageContentObject
	object.content = entry
	object.name = "StageContent_%s" % entry.id
	_grid.add_child(object)
	object.place_on_cell(cell, _grid.cell_size)
	_objects.append(object)
	_cells[cell] = object


func _remove_object(object: StageContentObject) -> void:
	_objects.erase(object)
	_cells.erase(object.cell)
	if is_instance_valid(object):
		object.queue_free()


## Content resolves on arrival only — the same hook for a manual move and an AUTO
## move, so automation cannot change the outcome.
func _on_player_moved(_from_cell: Vector2i, to_cell: Vector2i, _movement_points_remaining: int) -> void:
	resolve_at(to_cell)


## Resolves the content on `cell`, if any. Returns the description of what
## happened, or "" when there was nothing to resolve.
func resolve_at(cell: Vector2i) -> String:
	if not _cells.has(cell):
		return ""
	var object: StageContentObject = _cells[cell]
	var entry: StageContent = object.content
	if entry == null:
		return ""
	var key := AuthoredContentStateScript.make_key(_active_stage_id, entry.id)
	if _resolved_this_stage.has(key):
		# Repeatable content resolves at most once per visit, so stepping off and
		# back on cannot be used to farm it.
		return ""
	_resolved_this_stage[key] = true
	var description: String = _apply_effect(entry)
	if entry.one_shot:
		_state.consume(_active_stage_id, entry.id)
		_remove_object(object)
	content_resolved.emit(description)
	return description


func _apply_effect(entry: StageContent) -> String:
	match entry.kind:
		StageContentScript.Kind.CHEST:
			return _open_chest(entry)
		StageContentScript.Kind.HEALING_POOL:
			return _use_healing_pool(entry)
	return _label(entry)


func _open_chest(entry: StageContent) -> String:
	var parts: Array[String] = []
	if entry.gold > 0 and _gold_system != null and _gold_system.has_method("grant_gold"):
		# Paid through GoldSystem so chest gold takes the same path as every
		# other gold award (HUD log, multiplier bookkeeping, signals).
		var granted: int = int(_gold_system.grant_gold(entry.gold, "chest"))
		parts.append("%d GOLD" % granted)
	if entry.loot_table != null and _player != null:
		var item_level: int = entry.item_level if entry.item_level > 0 else _current_stage_number()
		for item in _loot_generator.generate_from_table(entry.loot_table, item_level):
			if _player.add_equipment(item):
				parts.append(String(item.get_display_name()))
	if parts.is_empty():
		return "%s — EMPTY" % _label(entry)
	return "%s — %s" % [_label(entry), " + ".join(parts)]


func _use_healing_pool(entry: StageContent) -> String:
	if _player == null or _player.player_stats == null:
		return _label(entry)
	var restored: int = _player.heal(entry.get_heal_amount(_player.player_stats.max_hp))
	if restored <= 0:
		return "%s — ALREADY AT FULL HEALTH" % _label(entry)
	return "%s — RESTORED %d HP" % [_label(entry), restored]


func _label(entry: StageContent) -> String:
	if not entry.display_name.is_empty():
		return entry.display_name.to_upper()
	return StageContentScript.get_kind_display_name(entry.kind).to_upper()


func _current_stage_number() -> int:
	if _stage_manager == null or _stage_manager.stage_state == null:
		return 1
	return maxi(_stage_manager.stage_state.stage_number, 1)
