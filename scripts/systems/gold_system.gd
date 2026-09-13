class_name GoldSystem
extends Node

## Awards Gold from defeated enemies and completed stages (§6.1).
signal gold_awarded(amount: int, current_gold: int, source_name: String)

@export_range(0.0, 100.0, 0.1) var normal_gold_multiplier: float = 1.0
@export_range(0.0, 100.0, 0.1) var elite_gold_multiplier: float = 2.0
@export_range(0.0, 100.0, 0.1) var special_gold_multiplier: float = 2.5
@export_range(0.0, 100.0, 0.1) var mini_boss_gold_multiplier: float = 4.0
@export_range(0.0, 100.0, 0.1) var treasure_gold_multiplier: float = 3.0
@export_range(0.0, 100.0, 0.1) var gold_monster_multiplier: float = 5.0
@export_range(0.0, 100.0, 0.1) var cursed_gold_multiplier: float = 1.5
## §7: injected by the host that also owns the provider; a headless fixture falls back to the
## shipped default instead of restating a balance number.
@export var balance_profile: BalanceProfile

var _player: PlayerController
var _combat_system: CombatSystem
var _stage_manager: StageManager
## §6.1: one settlement per kill, keyed by the enemy's runtime instance id — see
## [method ExperienceSystem.settle_kill_experience] for the same rule on the EXP side.
var _settled_enemies: Dictionary = {}


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


func attach_stage_manager(stage_manager: StageManager) -> void:
	if _stage_manager != null and _stage_manager.stage_completed.is_connected(_on_stage_completed):
		_stage_manager.stage_completed.disconnect(_on_stage_completed)
	_stage_manager = stage_manager
	if _stage_manager == null:
		return
	if not _stage_manager.stage_completed.is_connected(_on_stage_completed):
		_stage_manager.stage_completed.connect(_on_stage_completed)


## §6.1 `enemy_gold = round(base_gold * G(S) * offset_mult * type_gold)`. The enemy's runtime
## `gold_reward` already carries all three factors — [EnemyScaling] writes it once when the stage
## is built — so this reads it and applies nothing a second time. Gold has NO player-level
## catch-up by design.
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
	if enemy_stats == null:
		return 0
	var reward: float = float(maxi(enemy_stats.gold_reward, 0))
	if reward <= 0.0 or is_nan(reward):
		return 0
	return BalanceFormulas.round_reward(get_balance_profile(), reward, 0)


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


## §6.1 `stage_clear_gold = round(50 * G(S))`, the shared formula the stage build and the clear
## reward both use.
func calculate_stage_gold(stage_number: int) -> int:
	return BalanceFormulas.stage_clear_gold(get_balance_profile(), maxi(stage_number, 1))


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


## §6.1: the single Gold entry for a kill, guarded so a duplicate death signal pays once.
func settle_kill_gold(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var key: int = enemy.get_instance_id()
	if _settled_enemies.has(key):
		return 0
	var reward: int = calculate_enemy_gold(enemy)
	if reward <= 0:
		return 0
	_settled_enemies[key] = true
	var source_name: String = "enemy"
	if enemy is EnemyController:
		source_name = (enemy as EnemyController).get_display_name()
	return grant_gold(reward, source_name)


func reset_settlements() -> void:
	_settled_enemies.clear()


func _on_actor_died(actor: Node) -> void:
	if not actor is EnemyController:
		return
	settle_kill_gold(actor)


func _on_stage_completed(stage_state: StageState) -> void:
	if stage_state == null:
		return
	grant_stage_reward(stage_state.stage_number)
