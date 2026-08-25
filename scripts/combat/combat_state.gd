class_name CombatState
extends Resource

enum {
	IN_PROGRESS,
	VICTORY,
	DEFEAT,
}

@export_range(1, 999999, 1) var stage_number: int = 1
@export var result: int = IN_PROGRESS
@export var turn_state: TurnState
@export var player_stats: PlayerStats
@export var player_progression: PlayerProgression
@export var enemies: Array[EnemyStats] = []
@export var defeated_enemy_ids: Array[StringName] = []


func _init() -> void:
	turn_state = TurnState.new()
	player_stats = PlayerStats.new()
	player_progression = PlayerProgression.new()


func reset_for_stage(new_stage_number: int) -> void:
	stage_number = maxi(new_stage_number, 1)
	result = IN_PROGRESS
	turn_state = TurnState.new()
	player_stats.reset_current_hp()
	enemies.clear()
	defeated_enemy_ids.clear()
