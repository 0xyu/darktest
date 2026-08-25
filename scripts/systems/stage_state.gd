class_name StageState
extends Resource

## Runtime progress for an active stage.
@export_range(1, 999999, 1) var stage_number: int = 1
@export var is_mini_boss_stage: bool = false
@export var spawned_enemy_count: int = 0
@export var defeated_enemy_count: int = 0
@export var is_complete: bool = false
@export var encounter_id: StringName = &""
@export var is_special_encounter: bool = false
@export var special_encounter_type: int = SpecialEncounterType.NONE
@export_range(1, 999999, 1) var special_mini_boss_level: int = 1


func reset_for_stage(new_stage_number: int, mini_boss_stage: bool = false) -> void:
	stage_number = maxi(new_stage_number, 1)
	is_mini_boss_stage = mini_boss_stage
	spawned_enemy_count = 0
	defeated_enemy_count = 0
	is_complete = false
	encounter_id = &""
	is_special_encounter = false
	special_encounter_type = SpecialEncounterType.NONE
	special_mini_boss_level = 1
