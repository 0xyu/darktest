class_name ExperienceSystem
extends Node

## Awards enemy experience and drives the player's level-up stat growth (the hero
## rebuilds its own numbers from the new level — see PlayerController).
signal experience_awarded(amount: int, current_experience: int, required_experience: int, source_name: String)
signal level_up(new_level: int, max_hp_gain: int, attack_gain: int, defense_gain: int)

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
	var enemy_stats: EnemyStats
	var enemy_level: int = 1
	if enemy is EnemyController:
		var enemy_controller: EnemyController = enemy as EnemyController
		enemy_stats = enemy_controller.enemy_runtime.current_stats
		enemy_level = maxi(enemy_controller.enemy_level, 1)
	else:
		var enemy_stats_variant: Variant = enemy.get("enemy_stats")
		if not enemy_stats_variant is EnemyStats:
			return 0
		enemy_stats = enemy_stats_variant as EnemyStats
	var enemy_type: int = EnemyType.NORMAL
	if enemy is EnemyController and (enemy as EnemyController).enemy_data != null:
		enemy_type = (enemy as EnemyController).enemy_data.enemy_type
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
	if levels_gained > 0:
		# The growth is applied by the hero's OWN rebuild of its derived stats, which
		# is also what a boot, an equip and a load call: ONE function decides what a
		# level and a set of gear are worth, instead of a level-up adding increments
		# that a load could not reproduce. A level-up keeps the current HP where it is.
		_player.recompute_stats_from_level_and_equipment(true)
	# What one level granted, read from the stats the hero just rebuilt itself from —
	# so the reported gain and the applied gain cannot disagree.
	var growth: Dictionary = _player.get_level_growth()
	for level_offset in range(levels_gained):
		var reached_level: int = level_before + level_offset + 1
		level_up.emit(
			reached_level,
			int(growth.get(&"hp", 0)),
			int(growth.get(&"attack", 0)),
			int(growth.get(&"defense", 0))
		)
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
