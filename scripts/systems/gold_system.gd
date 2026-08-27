class_name GoldSystem
extends Node

const EnemyScalingSystem = preload("res://scripts/systems/enemy_scaling.gd")

## Awards Gold from defeated enemies and completed stages.
signal gold_awarded(amount: int, current_gold: int, source_name: String)

@export_range(0, 999999, 1) var base_stage_gold: int = 50
@export_range(0.1, 10.0, 0.01) var gold_growth_rate: float = 1.18
@export_range(0.0, 100.0, 0.1) var normal_gold_multiplier: float = 1.0
@export_range(0.0, 100.0, 0.1) var elite_gold_multiplier: float = 2.0
@export_range(0.0, 100.0, 0.1) var special_gold_multiplier: float = 2.5
@export_range(0.0, 100.0, 0.1) var mini_boss_gold_multiplier: float = 4.0
@export_range(0.0, 100.0, 0.1) var treasure_gold_multiplier: float = 3.0
@export_range(0.0, 100.0, 0.1) var gold_monster_multiplier: float = 5.0
@export_range(0.0, 100.0, 0.1) var cursed_gold_multiplier: float = 1.5

var _player: PlayerController
var _combat_system: CombatSystem
var _stage_manager: StageManager


func attach_player(player: PlayerController) -> void:
	_player = player


func attach_combat_system(combat_system: CombatSystem) -> void:
	if _combat_system != null and _combat_system.actor_died.is_connected(_on_actor_died):
		_combat_system.actor_died.disconnect(_on_actor_died)
	_combat_system = combat_system
	if _combat_system == null:
		return
	if not _combat_system.actor_died.is_connected(_on_actor_died):
		_combat_system.actor_died.connect(_on_actor_died)


func attach_stage_manager(stage_manager: StageManager) -> void:
	if _stage_manager != null and _stage_manager.stage_completed.is_connected(_on_stage_completed):
		_stage_manager.stage_completed.disconnect(_on_stage_completed)
	_stage_manager = stage_manager
	if _stage_manager == null:
		return
	gold_growth_rate = _stage_manager.gold_growth_rate
	if not _stage_manager.stage_completed.is_connected(_on_stage_completed):
		_stage_manager.stage_completed.connect(_on_stage_completed)


func calculate_enemy_gold(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var enemy_stats: EnemyStats
	if enemy is EnemyController:
		enemy_stats = (enemy as EnemyController).enemy_runtime.current_stats
	else:
		var enemy_stats_variant: Variant = enemy.get("enemy_stats")
		if not enemy_stats_variant is EnemyStats:
			return 0
		enemy_stats = enemy_stats_variant as EnemyStats
	var enemy_type: int = EnemyType.NORMAL
	if enemy is EnemyController and (enemy as EnemyController).enemy_data != null:
		enemy_type = (enemy as EnemyController).enemy_data.enemy_type
	var reward: float = float(maxi(enemy_stats.gold_reward, 0)) * get_enemy_type_multiplier(enemy_type)
	if reward <= 0.0 or is_nan(reward):
		return 0
	if is_inf(reward):
		return 2147483647
	return maxi(roundi(reward), 1)


func get_enemy_type_multiplier(enemy_type: int) -> float:
	match enemy_type:
		EnemyType.ELITE:
			return maxf(elite_gold_multiplier, 0.0)
		EnemyType.SPECIAL:
			return maxf(special_gold_multiplier, 0.0)
		EnemyType.MINI_BOSS:
			return maxf(mini_boss_gold_multiplier, 0.0)
		EnemyType.TREASURE:
			return maxf(treasure_gold_multiplier, 0.0)
		EnemyType.GOLD:
			return maxf(gold_monster_multiplier, 0.0)
		EnemyType.CURSED:
			return maxf(cursed_gold_multiplier, 0.0)
		_:
			return maxf(normal_gold_multiplier, 0.0)


func calculate_stage_gold(stage_number: int) -> int:
	return EnemyScalingSystem.scale_value(base_stage_gold, gold_growth_rate, maxi(stage_number, 1))


func grant_gold(amount: int, source_name: String = "") -> int:
	if _player == null or not is_instance_valid(_player) or _player.player_progression == null:
		return 0
	var awarded_amount: int = _player.player_progression.add_gold(amount)
	if awarded_amount <= 0:
		return 0
	gold_awarded.emit(awarded_amount, _player.player_progression.gold, source_name)
	return awarded_amount


func grant_stage_reward(stage_number: int) -> int:
	var reward: int = calculate_stage_gold(stage_number)
	return grant_gold(reward, "Stage %d clear" % maxi(stage_number, 1))


func _on_actor_died(actor: Node) -> void:
	if not actor is EnemyController:
		return
	var enemy: EnemyController = actor as EnemyController
	var reward: int = calculate_enemy_gold(enemy)
	if reward > 0:
		grant_gold(reward, enemy.get_display_name())


func _on_stage_completed(stage_state: StageState) -> void:
	if stage_state == null:
		return
	grant_stage_reward(stage_state.stage_number)
