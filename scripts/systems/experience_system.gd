class_name ExperienceSystem
extends Node

## Awards enemy experience and applies the player's level-up stat growth.
signal experience_awarded(amount: int, current_experience: int, required_experience: int, source_name: String)
signal level_up(new_level: int, max_hp_gain: int, attack_gain: int, defense_gain: int)

@export_range(0, 999999, 1) var base_hp_growth: int = 20
@export_range(0, 999999, 1) var base_attack_growth: int = 2
@export_range(0, 999999, 1) var base_defense_growth: int = 1

@export_range(0.0, 100.0, 0.1) var normal_experience_multiplier: float = 1.0
@export_range(0.0, 100.0, 0.1) var elite_experience_multiplier: float = 2.0
@export_range(0.0, 100.0, 0.1) var special_experience_multiplier: float = 2.5
@export_range(0.0, 100.0, 0.1) var mini_boss_experience_multiplier: float = 4.0
@export_range(0.0, 100.0, 0.1) var treasure_experience_multiplier: float = 1.5
@export_range(0.0, 100.0, 0.1) var gold_experience_multiplier: float = 1.5
@export_range(0.0, 100.0, 0.1) var cursed_experience_multiplier: float = 2.0

var _player: PlayerController
var _combat_system: CombatSystem


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


func calculate_enemy_experience(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var enemy_stats_variant: Variant = enemy.get("enemy_stats")
	if not enemy_stats_variant is EnemyStats:
		return 0
	var enemy_stats: EnemyStats = enemy_stats_variant as EnemyStats
	var enemy_level: int = maxi(enemy_stats.level, 1)
	if enemy is EnemyController:
		var enemy_controller: EnemyController = enemy as EnemyController
		enemy_level = maxi(enemy_controller.enemy_level, 1)
	var enemy_type: int = EnemyType.NORMAL
	var definition_variant: Variant = enemy.get("enemy_definition")
	if definition_variant is EnemyDefinition:
		var definition: EnemyDefinition = definition_variant as EnemyDefinition
		enemy_type = definition.enemy_type
	var level_multiplier: float = 1.0 + float(enemy_level - 1) * 0.10
	var reward: float = float(maxi(enemy_stats.experience_reward, 0)) * level_multiplier
	reward *= get_enemy_type_multiplier(enemy_type)
	if reward <= 0.0 or is_nan(reward):
		return 0
	if is_inf(reward):
		return 2147483647
	return maxi(roundi(reward), 1)


func get_enemy_type_multiplier(enemy_type: int) -> float:
	match enemy_type:
		EnemyType.ELITE:
			return maxf(elite_experience_multiplier, 0.0)
		EnemyType.SPECIAL:
			return maxf(special_experience_multiplier, 0.0)
		EnemyType.MINI_BOSS:
			return maxf(mini_boss_experience_multiplier, 0.0)
		EnemyType.TREASURE:
			return maxf(treasure_experience_multiplier, 0.0)
		EnemyType.GOLD:
			return maxf(gold_experience_multiplier, 0.0)
		EnemyType.CURSED:
			return maxf(cursed_experience_multiplier, 0.0)
		_:
			return maxf(normal_experience_multiplier, 0.0)


func grant_experience(amount: int, source_name: String = "") -> int:
	if _player == null or not is_instance_valid(_player) or _player.player_progression == null:
		return 0
	var safe_amount: int = maxi(amount, 0)
	var progression: PlayerProgression = _player.player_progression
	var level_before: int = maxi(progression.level, 1)
	var levels_gained: int = progression.add_experience(safe_amount)
	var stats: PlayerStats = _player.player_stats
	for level_offset in range(levels_gained):
		if stats != null:
			stats.max_hp += maxi(base_hp_growth, 0)
			stats.attack += maxi(base_attack_growth, 0)
			stats.defense += maxi(base_defense_growth, 0)
			stats.clamp_current_hp()
		var reached_level: int = level_before + level_offset + 1
		level_up.emit(reached_level, maxi(base_hp_growth, 0), maxi(base_attack_growth, 0), maxi(base_defense_growth, 0))
		_player.notify_level_up(reached_level)

	if safe_amount > 0:
		experience_awarded.emit(safe_amount, progression.experience, progression.experience_to_next_level(), source_name)
		_player.notify_experience_gained(safe_amount, progression.experience, progression.experience_to_next_level())
	return levels_gained


func _on_actor_died(actor: Node) -> void:
	if not actor is EnemyController:
		return
	var enemy: EnemyController = actor as EnemyController
	var reward: int = calculate_enemy_experience(enemy)
	if reward <= 0:
		return
	grant_experience(reward, enemy.get_display_name())
