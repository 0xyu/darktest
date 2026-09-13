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
## §7: injected by the host that also owns the provider; a headless fixture falls back to the
## shipped default instead of restating a balance number.
@export var balance_profile: BalanceProfile

var _player: PlayerController
var _combat_system: CombatSystem
## §5: one settlement per kill. A farming respawn, a lobby teardown or a second
## `resolve_defeat()` for the same enemy must not pay a second time, so every settled enemy is
## remembered by its runtime instance id.
var _settled_enemies: Dictionary = {}
## What each settled kill paid, so the combat log reads the SAME number that reached the purse.
var _settled_amounts: Dictionary = {}


func get_balance_profile() -> BalanceProfile:
	return balance_profile if balance_profile != null else BalanceProfile.get_default()


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


## §5: the EXP ONE kill pays, settled at the moment of the kill:
## `max(1, round(100 * G(S) * offset_mult * type_exp * catchup(S, L)))`.
##
## The enemy's runtime `experience_reward` already carries `100 * G(S)`, the real level offset and
## the type multiplier, applied exactly ONCE when the stage was built ([EnemyScaling] writes it).
## This function adds the `catchup(S, L)` factor and nothing else — a second G or a second type
## multiplier here is exactly the double settlement §8's R2 forbids.
##
## `stage_number` is optional: a caller that knows the stage passes it, and otherwise the enemy's
## own runtime level stands in for it, which is the stage it was spawned for.
func calculate_enemy_experience(enemy: Node, stage_number: int = 0) -> int:
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
	if enemy_stats == null:
		return 0
	var reward: float = float(maxi(enemy_stats.experience_reward, 0))
	if reward <= 0.0 or is_nan(reward):
		return 0
	var profile: BalanceProfile = get_balance_profile()
	var safe_stage: int = stage_number if stage_number > 0 else _resolve_stage_number(enemy)
	# The player's level is sampled BEFORE the settlement (§5), which is what lets one kill cross
	# several levels and still pay every one of them.
	var level: int = _get_player_level()
	var catchup: float = BalanceFormulas.experience_catchup(profile, safe_stage, level)
	return BalanceFormulas.round_reward(profile, reward * catchup, 1)


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


## §5/§6 "every reward settles exactly once": the single EXP entry for a kill. The settled set is
## keyed by the enemy's runtime instance id, so a duplicate death signal, a re-resolved defeat or
## a Sub Hero finishing a target the player already killed pays nothing the second time.
func settle_kill_experience(enemy: Node, stage_number: int = 0) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var key: int = enemy.get_instance_id()
	if _settled_enemies.has(key):
		return 0
	var reward: int = calculate_enemy_experience(enemy, stage_number)
	if reward <= 0:
		return 0
	_settled_enemies[key] = true
	_settled_amounts[key] = reward
	var source_name: String = "enemy"
	if enemy is EnemyController:
		source_name = (enemy as EnemyController).get_display_name()
	grant_experience(reward, source_name)
	return reward


## What this kill actually paid, for the combat log. Reading the settled amount instead of
## recomputing it is what keeps the number on screen equal to the number in the purse — a second
## computation could disagree with the settlement it is describing.
func get_settled_experience(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	return int(_settled_amounts.get(enemy.get_instance_id(), 0))


## Forgets one enemy's settlement (a respawned stage spawns a NEW node, so this exists only for a
## fixture that re-uses an instance).
func clear_kill_settlement(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_settled_enemies.erase(enemy.get_instance_id())


func reset_settlements() -> void:
	_settled_enemies.clear()
	_settled_amounts.clear()


func _on_actor_died(actor: Node) -> void:
	if not actor is EnemyController:
		return
	settle_kill_experience(actor)


## The main character's level, sampled before the settlement. Without a hero (a headless fixture)
## the catch-up is neutral, which is the same as a level-synced player.
func _get_player_level() -> int:
	if _player == null or not is_instance_valid(_player) or _player.player_progression == null:
		return 1
	return maxi(_player.player_progression.level, 1)


## The stage a kill belongs to, read from the enemy's own runtime level when the caller did not
## pass one. `enemy_level` is what the stage build wrote (`S + offset`, clamped), so it is a
## better source than the scene's current stage number while a stage is being torn down.
func _resolve_stage_number(enemy: Node) -> int:
	if enemy is EnemyController:
		return maxi((enemy as EnemyController).enemy_level, 1)
	return 1
