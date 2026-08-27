class_name StageEnemyEntry
extends Resource

## A compact reference to one enemy type used by a stage.
##
## Enemy properties remain in EnemyData. This resource only describes how
## that enemy participates in one stage.
enum SpawnRule {
	RANDOM,
	NEAR_PLAYER,
	FAR_FROM_PLAYER,
}

@export var enemy_definition: EnemyData
@export_range(1, 999, 1) var count: int = 1
@export_range(-999999, 999999, 1) var level_offset: int = 0
@export_enum("Random", "Near Player", "Far From Player") var spawn_rule: int = SpawnRule.RANDOM

## Optional per-stage tuning. A value of 0 means no explicit level override.
@export_range(0, 999999, 1) var level_override: int = 0
@export_range(0.1, 10.0, 0.01) var hp_multiplier: float = 1.0
@export_range(0.1, 10.0, 0.01) var attack_multiplier: float = 1.0
@export_range(0.1, 10.0, 0.01) var defense_multiplier: float = 1.0


func get_level(stage_level: int) -> int:
	if level_override > 0:
		return level_override
	return maxi(stage_level + level_offset, 1)


func copy_entry() -> StageEnemyEntry:
	var copy := StageEnemyEntry.new()
	copy.enemy_definition = enemy_definition
	copy.count = count
	copy.level_offset = level_offset
	copy.spawn_rule = spawn_rule
	copy.level_override = level_override
	copy.hp_multiplier = hp_multiplier
	copy.attack_multiplier = attack_multiplier
	copy.defense_multiplier = defense_multiplier
	return copy
