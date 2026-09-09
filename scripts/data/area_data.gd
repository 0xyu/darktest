class_name AreaData
extends Resource

## Static, author-authored definition of one playable Area: a named, ordered
## path of StageData nodes (e.g. Forest with its 01-10 stages).
##
## Phase 1 data model. Data only — completion / unlock / player position are
## PlayerProgress concerns and must never be written back into this resource.

## Stable unique id, e.g. &"forest".
@export var id: StringName = &""
@export var display_name: String = ""
## Ordered path of stage nodes (by stage_number convention). Duplicate ids and
## duplicate numbers are rejected by get_validation_errors().
@export var stages: Array[StageData] = []
## Optional background art for a World Map / area presentation view.
@export var background: Texture2D


## Human-readable validation messages; empty means the area is valid.
## Validates the area itself and every stage, plus cross-stage rules:
##   * every stage id / stage_number must be unique within the area
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("Area id must not be empty.")
	var seen_ids := {}
	var seen_numbers := {}
	for index in range(stages.size()):
		var stage := stages[index]
		if stage == null:
			errors.append("Area '%s' stages[%d] is null." % [id, index])
			continue
		for stage_error in stage.get_validation_errors():
			errors.append(stage_error)
		var stage_id := String(stage.id)
		if not stage_id.is_empty():
			if seen_ids.has(stage_id):
				errors.append("Area '%s' has duplicate stage id '%s'." % [id, stage_id])
			seen_ids[stage_id] = true
		if seen_numbers.has(stage.stage_number):
			errors.append("Area '%s' has duplicate stage number %d." % [id, stage.stage_number])
		seen_numbers[stage.stage_number] = true
	return errors


func is_valid() -> bool:
	return get_validation_errors().is_empty()
