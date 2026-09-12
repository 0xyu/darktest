class_name LevelConfig
extends Resource

## Author-authored fixed level configuration.
@export_range(1, 999999, 1) var level_id: int = 1
@export var template_id: StringName = &"default"
@export_range(0.1, 10.0, 0.01) var difficulty_multiplier: float = 1.0
@export var enemy_entries: Array[StageEnemyEntry] = []
@export var spawn_rules: Array[StringName] = [&"random"]
@export var boss: EnemyData
## Fixed items this level's boss is guaranteed to drop ONCE PER SAVE, on top of the
## boss loot table. Authored here (not in code) so a stage's one-of-a-kind reward is
## content, and so the endless generated tail simply has none.
@export var guaranteed_loot: Array[EquipmentDefinition] = []
@export var special_rules: Dictionary = {}


func to_stage_definition() -> StageDefinition:
	var definition := StageDefinition.new()
	definition.stage_number = maxi(level_id, 1)
	definition.level_id = definition.stage_number
	definition.template_id = template_id
	definition.display_name = "Stage %d" % definition.stage_number
	definition.difficulty_multiplier = maxf(difficulty_multiplier, 0.1)
	definition.spawn_rules = spawn_rules.duplicate()
	definition.special_rules = special_rules.duplicate(true)
	definition.boss = boss
	definition.guaranteed_loot.assign(guaranteed_loot)
	definition.is_mini_boss_stage = boss != null
	for entry in enemy_entries:
		if entry != null:
			definition.enemy_entries.append(entry.copy_entry())
	return definition
