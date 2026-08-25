class_name PlayerProgression
extends Resource

## Persistent progression values independent from the player's derived stats.
@export_range(1, 999999, 1) var level: int = 1
@export var experience: int = 0
@export var gold: int = 0
@export_range(1, 999999, 1) var current_stage: int = 1


func experience_to_next_level() -> int:
	var safe_level: int = maxi(level, 1)
	return maxi(1, roundi(100.0 * pow(1.15, float(safe_level - 1))))
