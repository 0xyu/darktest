class_name DamageResult
extends Resource

## Data produced by a damage calculation; it performs no calculation itself.
@export var attacker_id: StringName = &""
@export var target_id: StringName = &""
@export var skill_id: StringName = &""
@export var raw_damage: int = 0
@export var final_damage: int = 0
@export var is_critical: bool = false
@export var is_miss: bool = false
@export var target_defeated: bool = false
