class_name StageData
extends Resource

## Static, author-authored definition of one stage node on an area path.
##
## Phase 1 data model. This file describes WHAT a stage is (id, order, name,
## gameplay type). It is data only: completion / unlock / player position are
## PlayerProgress concerns and must never be written back into this resource.

const StageTypes = preload("res://scripts/data/stage_type.gd")

## Stable unique id within its Area, e.g. &"forest_01".
@export var id: StringName = &""
## Position on the area path, 1-based. Numbers must be unique within an Area.
@export_range(1, 9999, 1) var stage_number: int = 1
@export var display_name: String = ""
## See StageType. Determines which gameplay the StageManager routes to.
@export var stage_type: int = StageTypes.COMBAT

## Optional data entry points wired in by later phases (combat / event / town /
## boss / rewards / requirements). Kept as plain Resources on purpose so each
## owning phase attaches its own typed resource here without this definition
## having to know those classes — no speculative data classes are created yet.
@export var combat_data: Resource
@export var event_data: Resource
@export var town_data: Resource
@export var boss_data: Resource
@export var reward_data: Resource
@export var requirement_data: Resource


## Human-readable validation messages; empty means this stage is valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("Stage id must not be empty.")
	if stage_number < 1:
		errors.append("Stage '%s' stage_number must be >= 1." % id)
	if not StageTypes.is_valid(stage_type):
		errors.append("Stage '%s' has invalid stage_type %d." % [id, stage_type])
	return errors


func is_valid() -> bool:
	return get_validation_errors().is_empty()
