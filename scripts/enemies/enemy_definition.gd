class_name EnemyDefinition
extends Resource

## Configurable content definition used to create enemy runtime state.
@export var definition_id: StringName = &"enemy"
@export var display_name: String = "Enemy"
@export_enum("Normal", "Elite", "Special", "Mini Boss", "Treasure", "Gold", "Cursed") var enemy_type: int = EnemyType.NORMAL
@export var base_stats: EnemyStats = EnemyStats.new()
@export_multiline var description: String = ""
