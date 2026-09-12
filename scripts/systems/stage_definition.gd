class_name StageDefinition
extends Resource

## Final, provider-independent definition consumed by StageManager.
@export_range(1, 999999, 1) var stage_number: int = 1
@export var level_id: int = 1
@export var template_id: StringName = &"default"
@export var display_name: String = "Stage 1"
@export_range(0.1, 10.0, 0.01) var difficulty_multiplier: float = 1.0
@export var enemy_entries: Array[StageEnemyEntry] = []
@export var spawn_rules: Array[StringName] = [&"random"]
@export var boss: EnemyData
## Fixed items the boss of this stage grants once per save, in addition to its loot
## table. The grant is recorded in the one-shot content store, so replaying the
## stage (FARMING, a map re-entry) cannot hand the same item out twice.
@export var guaranteed_loot: Array[EquipmentDefinition] = []
@export var special_rules: Dictionary = {}
@export var is_mini_boss_stage: bool = false
@export var is_special_encounter: bool = false
@export var special_encounter_type: int = SpecialEncounterType.NONE
@export var special_enemy_definition: EnemyData
@export_range(1, 999999, 1) var special_mini_boss_level: int = 1


func get_total_enemy_count() -> int:
	var total: int = 0
	for entry in enemy_entries:
		if entry != null and entry.enemy_definition != null:
			total += maxi(entry.count, 0)
	return total
