class_name EnemyData
extends Resource

## Shared, immutable content configuration for an enemy type.
##
## EnemyData may be referenced by many EnemyController instances. Runtime
## values such as HP, buffs, and status effects must live in EnemyRuntime.
@export var id: StringName = &"enemy"
@export var name: String = "Enemy"
@export_enum("Normal", "Elite", "Special", "Mini Boss", "Treasure", "Gold", "Cursed") var enemy_type: int = EnemyType.NORMAL
@export var base_stats: EnemyStats = EnemyStats.new()
@export var portrait: Texture2D
@export var battle_sprite: Texture2D
@export var skills: Array[Resource] = []
@export var loot_table: LootTable
@export_multiline var description: String = ""

## Backwards-compatible name used by the pre-refactor stage code.
var definition_id: StringName:
	get:
		return id
	set(value):
		id = value

## Backwards-compatible display name used by existing UI and smoke tests.
var display_name: String:
	get:
		return name
	set(value):
		name = value
