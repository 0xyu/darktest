class_name EnemyStats
extends Resource

## Runtime stats for one spawned enemy.
@export_range(1, 999999, 1) var level: int = 1
@export var max_hp: int = 50
@export var current_hp: int = 50
@export var attack: int = 8
@export var defense: int = 2
@export var movement_points: int = 3
@export var attack_range: int = 1
@export var experience_reward: int = 25
@export var gold_reward: int = 10


func reset_current_hp() -> void:
	current_hp = max_hp


func clamp_current_hp() -> void:
	current_hp = clampi(current_hp, 0, maxi(max_hp, 0))
