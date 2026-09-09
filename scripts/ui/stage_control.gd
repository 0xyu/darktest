class_name StageControl
extends Control

## Drives the combat stage-control bar.
##
## The bar shows the surrounding stage numbers on a row of slot buttons and
## highlights the stage the player is currently fighting. The widget pulls from
## StageManager itself (stage_state + stage_started) instead of having the HUD
## forward the stage number every frame, matching the "one source of truth"
## pattern used by HeaderRow.
##
## Slot layout:
##   - Slot 1 is fixed to Stage 1 (reserved for a future "Town Stage").
##   - The remaining five slots form a window centered on the current stage,
##     shifted so it never collides with the fixed Stage 1 slot.

const SLOT_COUNT := 6
const TRAILING_SLOT_COUNT := SLOT_COUNT - 1
const TOWN_STAGE := 1

## Text color of the slot showing the current stage.
@export var current_stage_color := Color("f2c15e")
## Text color of every other (unreached / locked) slot.
@export var locked_stage_color := Color("8d877c")

var _stage_manager: Node
var _current_stage: int = TOWN_STAGE
var _slot_labels: Array[Label] = []


func _ready() -> void:
	_collect_slot_labels()
	var manager := _find_stage_manager()
	if manager != null:
		set_stage_manager(manager)
	else:
		_apply_display()


## Binds the stage source of truth and keeps the bar in sync from its signal.
## Safe to call later than _ready (e.g. a scene that spawns its StageManager
## after the UI).
func set_stage_manager(manager: Node) -> void:
	if _stage_manager == manager:
		return
	if _stage_manager != null and is_instance_valid(_stage_manager) and _stage_manager.has_signal("stage_started"):
		_stage_manager.stage_started.disconnect(_on_stage_started)
	_stage_manager = manager
	if _stage_manager != null and is_instance_valid(_stage_manager) and _stage_manager.has_signal("stage_started"):
		_stage_manager.stage_started.connect(_on_stage_started)
	_refresh_from_manager()


func _on_stage_started(stage_state: StageState, _enemies: Array[Node]) -> void:
	if stage_state == null:
		return
	_current_stage = maxi(stage_state.stage_number, TOWN_STAGE)
	_apply_display()


func _refresh_from_manager() -> void:
	if _stage_manager == null or not is_instance_valid(_stage_manager):
		return
	var stage_state := _stage_manager.get("stage_state") as StageState
	if stage_state == null:
		return
	_current_stage = maxi(stage_state.stage_number, TOWN_STAGE)
	_apply_display()


## Fills the slot labels from the current stage and recolors them.
func _apply_display() -> void:
	var values := _slot_values_for(_current_stage)
	var count := mini(values.size(), _slot_labels.size())
	for index in range(count):
		var stage_number: int = values[index]
		var label: Label = _slot_labels[index]
		label.text = str(stage_number)
		var is_current := stage_number == _current_stage
		label.add_theme_color_override("font_color", current_stage_color if is_current else locked_stage_color)


## The stage number shown on each slot, left to right.
##
## The first slot is always Stage 1. The other five show a consecutive window
## `[start, start + 4]` where `start = max(2, current - 2)`, so the current
## stage sits in the middle slot once it is high enough and never duplicates
## the fixed Stage 1 slot:
##   current 1 -> 1 2 3 4 5 6   (current on slot 1)
##   current 2 -> 1 2 3 4 5 6   (current on slot 2)
##   current 6 -> 1 4 5 6 7 8   (current centered on slot 4)
func _slot_values_for(current_stage: int) -> Array[int]:
	var values: Array[int] = [TOWN_STAGE]
	var window_start := maxi(2, current_stage - 2)
	for index in range(TRAILING_SLOT_COUNT):
		values.append(window_start + index)
	return values


## Resolves the StageManager by walking up to the ancestor that has it as a
## direct child (the combat scene root). The bar lives deep inside the HUD, so
## it cannot address StageManager with a fixed relative NodePath.
func _find_stage_manager() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		var manager := cursor.get_node_or_null("StageManager")
		if manager != null:
			return manager
		cursor = cursor.get_parent()
	return null


func _collect_slot_labels() -> void:
	var container := get_node_or_null("HBoxContainer/StageButtons/Control/HBoxContainer") as HBoxContainer
	if container == null:
		return
	for child in container.get_children():
		if not (child is TextureButton):
			continue
		var label := child.get_node_or_null("Label") as Label
		if label == null:
			continue
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_slot_labels.append(label)
