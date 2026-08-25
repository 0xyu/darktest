class_name StageDefinition
extends Resource

## Configurable definition for one sequential stage.
@export_range(1, 999999, 1) var stage_number: int = 1
@export var display_name: String = "Stage 1"
@export_range(1, 999, 1) var enemy_count: int = 1
@export var enemy_definitions: Array[EnemyDefinition] = []
@export var is_mini_boss_stage: bool = false
@export var mini_boss_definition: EnemyDefinition
@export var is_special_encounter: bool = false
@export var special_encounter_type: int = SpecialEncounterType.NONE
@export var special_enemy_definition: EnemyDefinition
@export_range(1, 999999, 1) var special_mini_boss_level: int = 1
