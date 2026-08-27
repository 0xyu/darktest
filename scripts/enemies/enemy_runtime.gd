class_name EnemyRuntime
extends RefCounted

## Per-instance mutable state for one spawned enemy.
##
## The current stat block is intentionally copied from EnemyData.base_stats.
## The EnemyData resource itself is never duplicated for runtime state.
var _current_hp: int = 0
var current_hp: int:
	get:
		return _current_hp
	set(value):
		_current_hp = value
		if current_stats != null:
			current_stats.current_hp = value

var current_stats: EnemyStats = EnemyStats.new()
var status_effects: Array[StringName] = []
var buffs: Dictionary = {}
var combat_state: Dictionary = {}


func _init(source_data: EnemyData = null, level_override: int = -1) -> void:
	if source_data != null:
		initialize_from_stats(source_data.base_stats, level_override)
	else:
		current_hp = current_stats.max_hp


func initialize_from_stats(source_stats: EnemyStats, level_override: int = -1) -> void:
	if source_stats == null:
		current_stats = EnemyStats.new()
	else:
		current_stats = source_stats.duplicate(true) as EnemyStats
	if level_override >= 1:
		current_stats.level = level_override
	current_stats.current_hp = current_stats.max_hp
	current_hp = current_stats.max_hp
	status_effects.clear()
	buffs.clear()
	combat_state.clear()


func set_hp(value: int) -> void:
	current_hp = value


func clamp_current_hp() -> void:
	current_hp = clampi(current_hp, 0, maxi(current_stats.max_hp, 0))
