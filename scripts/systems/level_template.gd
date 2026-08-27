class_name LevelTemplate
extends Resource

## Reusable recipe used when a level has no LevelConfig.
@export var template_id: StringName = &"default"
@export var enemy_entries: Array[StageEnemyEntry] = []
@export var enemy_pool: Array[EnemyData] = []
@export_range(1, 999, 1) var base_enemy_count: int = 1
@export_range(1, 999, 1) var enemy_count_growth_interval: int = 3
@export_range(1, 999, 1) var max_enemy_count: int = 4
@export_range(0.1, 10.0, 0.01) var difficulty_multiplier: float = 1.0
@export var spawn_rules: Array[StringName] = [&"random"]
@export var special_rules: Dictionary = {}
