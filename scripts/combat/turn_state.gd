class_name TurnState
extends Resource

enum {
	PLAYER_TURN,
	ENEMY_TURN,
	VICTORY,
	DEFEAT,
}

@export_enum("Player Turn", "Enemy Turn", "Victory", "Defeat") var phase: int = PLAYER_TURN
@export_range(1, 999999, 1) var turn_number: int = 1
@export var movement_points_remaining: int = 3
@export var action_available: bool = true
@export var active_actor_id: StringName = &"player"


func begin_player_turn(movement_points: int = 3) -> void:
	phase = PLAYER_TURN
	movement_points_remaining = maxi(movement_points, 0)
	action_available = true
	active_actor_id = &"player"


func begin_enemy_turn(enemy_id: StringName) -> void:
	phase = ENEMY_TURN
	movement_points_remaining = 0
	action_available = true
	active_actor_id = enemy_id
