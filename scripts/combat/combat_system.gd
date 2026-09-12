class_name CombatSystem
extends Node

signal attack_resolved(result: DamageResult)
signal actor_died(actor: Node)
signal skill_resolved(skill_id: StringName, hit_count: int)
signal skill_failed(skill_id: StringName, reason: String)

var _random_number_generator := RandomNumberGenerator.new()
var _turn_manager: TurnManager
var _player_actor: Node
var _combat_targets: Array[Node] = []


func _ready() -> void:
	_random_number_generator.randomize()


func attach_turn_manager(turn_manager: TurnManager) -> void:
	_turn_manager = turn_manager


func set_player_actor(player: Node) -> void:
	_player_actor = player


func set_combat_targets(targets: Array[Node]) -> void:
	_combat_targets = targets.duplicate()


func connect_actor(actor: Node) -> void:
	if actor == null:
		return
	if actor.has_signal("attack_requested"):
		var attack_signal: Signal = actor.attack_requested
		if not attack_signal.is_connected(_on_attack_requested):
			attack_signal.connect(_on_attack_requested)
	if actor.has_signal("area_attack_requested"):
		var area_attack_signal: Signal = actor.area_attack_requested
		if not area_attack_signal.is_connected(_on_area_attack_requested):
			area_attack_signal.connect(_on_area_attack_requested)
	if actor.has_signal("skill_requested"):
		var skill_signal: Signal = actor.skill_requested
		if not skill_signal.is_connected(_on_skill_requested):
			skill_signal.connect(_on_skill_requested)


func resolve_attack(
	attacker: Node,
	target: Node,
	damage_multiplier: float = 1.0,
	attack_range_override: int = -1,
	skill_id: StringName = &""
) -> DamageResult:
	return _resolve_attack(attacker, target, damage_multiplier, attack_range_override, skill_id, true)


func _resolve_attack(
	attacker: Node,
	target: Node,
	damage_multiplier: float = 1.0,
	attack_range_override: int = -1,
	skill_id: StringName = &"",
	consume_player_action: bool = true
) -> DamageResult:
	var result := DamageResult.new()
	result.attacker_id = _get_actor_id(attacker)
	result.target_id = _get_actor_id(target)
	result.skill_id = skill_id
	# Presentation-layer node references (animations); never used for gameplay.
	result.attacker = attacker
	result.target = target
	if not _is_actor_authorized(attacker) or not _is_valid_attack(attacker, target, attack_range_override):
		# §4: a refused attack never happened — no action is spent, and the input
		# surface reports the reason as text instead of a strike animation.
		result.is_miss = true
		result.is_refused = true
		attack_resolved.emit(result)
		return result

	var attacker_stats: Resource = _get_combat_stats(attacker)
	var target_stats: Resource = _get_combat_stats(target)
	var attack_context: Dictionary = {}
	if attacker.has_method("create_attack_context"):
		attack_context = attacker.create_attack_context(target)
	var equipment_multiplier: float = 1.0
	if attacker.has_method("get_equipment_damage_multiplier"):
		equipment_multiplier = maxf(float(attacker.get_equipment_damage_multiplier(target, attack_context)), 0.0)
	var attack_power: int = maxi(int(_get_stat_float(attacker_stats, &"attack")), 0)
	var defense: int = maxi(int(_get_stat_float(target_stats, &"defense")), 0)
	result.raw_damage = maxi(1, attack_power - defense)
	var modified_damage: float = float(result.raw_damage) * maxf(damage_multiplier, 0.0) * equipment_multiplier
	# §12 `damage_vs_elite` / `damage_vs_boss`: one more multiplier, applied after
	# the defense subtraction like every other multiplier (§5).
	modified_damage *= _get_enemy_tier_multiplier(attacker_stats, target)
	result.final_damage = maxi(1, roundi(modified_damage))

	# §12 Dodge: the target evades the strike entirely. Attacking a dodging enemy is
	# still a real action, so it spends the action — only a refused attack does not.
	var dodge: float = _get_stat_ratio(target_stats, &"dodge")
	if dodge > 0.0 and _random_number_generator.randf() < dodge:
		result.is_miss = true
		result.is_dodge = true
		result.final_damage = 0
		_consume_player_action(attacker, consume_player_action)
		attack_resolved.emit(result)
		return result

	var critical_chance: float = 0.0
	var critical_damage: float = 1.0
	if attacker_stats is PlayerStats:
		critical_chance = clampf(attacker_stats.critical_chance, 0.0, 1.0)
		critical_damage = maxf(attacker_stats.critical_damage, 1.0)
	if critical_chance > 0.0 and _random_number_generator.randf() < critical_chance:
		result.is_critical = true
		result.final_damage = maxi(1, roundi(modified_damage * critical_damage))

	var remaining_hp: int = maxi(_get_current_hp(target, target_stats) - result.final_damage, 0)
	_set_current_hp(target, target_stats, remaining_hp)
	_consume_player_action(attacker, consume_player_action)
	result.target_defeated = remaining_hp <= 0
	if target.has_method("clamp_current_hp"):
		target.clamp_current_hp()
	# §12 Life Steal and Stun, both driven by the affixes on the attacker.
	_apply_life_steal(attacker, attacker_stats, result)
	_apply_stun(attacker_stats, target, result)
	if attacker.has_method("apply_equipment_attack_effects"):
		attacker.apply_equipment_attack_effects(target, result, attack_context)
	if result.target_defeated:
		resolve_defeat(target)
	elif is_instance_valid(target) and target.has_method("queue_redraw"):
		target.queue_redraw()
	attack_resolved.emit(result)
	return result


## The ONE kill path: defeat handling plus the actor_died broadcast that every
## reward listener (EXP, gold, loot) and the presentation layer subscribe to.
## Player attacks, skills and Sub Heroes all finish a lethal blow here, so a kill
## grants identical rewards no matter who landed it.
func resolve_defeat(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("handle_defeat"):
		target.handle_defeat()
	if target.has_method("queue_redraw"):
		target.queue_redraw()
	actor_died.emit(target)


func _on_attack_requested(attacker: Node, target: Node) -> void:
	var result := resolve_attack(attacker, target)
	if _turn_manager == null or attacker != _player_actor:
		return
	# A refused attack (§4) leaves the action and the turn untouched.
	if result != null and result.is_refused:
		return
	if _turn_manager.is_player_turn():
		_turn_manager.complete_player_turn()


func _on_area_attack_requested(attacker: Node, target: Node, attack_range: int, damage_multiplier: float) -> void:
	resolve_attack(attacker, target, damage_multiplier, attack_range)


func _on_skill_requested(attacker: Node, target: Node, skill_id: StringName) -> void:
	if not resolve_skill(attacker, skill_id, target):
		return
	if _turn_manager != null and attacker == _player_actor and _turn_manager.is_player_turn():
		_turn_manager.complete_player_turn()


## Range/validity check for a BASIC attack, exposed so an input surface can refuse
## an impossible attack instead of resolving it as a miss that still consumes the
## player's action (a click on a distant enemy must not waste the turn). The rule
## itself stays here — callers never re-implement attack range.
func can_attack(attacker: Node, target: Node) -> bool:
	return _is_valid_attack(attacker, target)


func can_use_skill(attacker: Node, skill_id: StringName, selected_target: Node = null) -> bool:
	var skill := SkillCatalog.get_skill(skill_id)
	if skill.skill_id.is_empty():
		return false
	if _get_skill_level(attacker, skill_id) <= 0:
		return false
	if skill.is_area_skill():
		for combat_target in _combat_targets:
			if _is_valid_attack(attacker, combat_target, skill.range_cells):
				return true
		return false
	return _is_valid_attack(attacker, selected_target, skill.range_cells)


func resolve_skill(attacker: Node, skill_id: StringName, selected_target: Node = null) -> bool:
	var skill := SkillCatalog.get_skill(skill_id)
	if skill.skill_id.is_empty():
		skill_failed.emit(skill_id, "Unknown skill")
		return false
	if not can_use_skill(attacker, skill_id, selected_target):
		skill_failed.emit(skill_id, "No valid target")
		return false
	if not _is_actor_authorized(attacker):
		skill_failed.emit(skill_id, "Actor cannot act")
		return false

	var hit_count: int = 0
	var skill_level: int = _get_skill_level(attacker, skill_id)
	var skill_damage_multiplier: float = skill.get_damage_multiplier(skill_level)
	if skill.is_area_skill():
		# Copy the list because defeating the final enemy can trigger stage cleanup
		# while this skill is still resolving its remaining hits.
		var targets: Array[Node] = _combat_targets.duplicate()
		for combat_target in targets:
			if _is_valid_attack(attacker, combat_target, skill.range_cells):
				var area_result := _resolve_attack(attacker, combat_target, skill_damage_multiplier, skill.range_cells, skill.skill_id, false)
				if not area_result.is_refused:
					hit_count += 1
	else:
		var result := _resolve_attack(attacker, selected_target, skill_damage_multiplier, skill.range_cells, skill.skill_id, false)
		if not result.is_refused:
			hit_count = 1
	if hit_count > 0 and attacker == _player_actor and _turn_manager != null:
		_turn_manager.consume_player_action(attacker)

	skill_resolved.emit(skill.skill_id, hit_count)
	return hit_count > 0


func _get_skill_level(attacker: Node, skill_id: StringName) -> int:
	if attacker == null or not is_instance_valid(attacker):
		return 0
	if attacker.has_method("get_skill_level"):
		return maxi(int(attacker.get_skill_level(skill_id)), 0)
	var progression: Variant = attacker.get("player_progression")
	if progression is PlayerProgression:
		return maxi((progression as PlayerProgression).get_skill_level(skill_id), 0)
	return 0


func _is_valid_attack(attacker: Node, target: Node, attack_range_override: int = -1) -> bool:
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		return false
	if attacker == target:
		return false
	var attacker_stats: Resource = _get_combat_stats(attacker)
	var target_stats: Resource = _get_combat_stats(target)
	if attacker_stats == null or target_stats == null:
		return false
	if _get_current_hp(attacker, attacker_stats) <= 0 or _get_current_hp(target, target_stats) <= 0:
		return false
	var attacker_cell: Vector2i = _get_grid_position(attacker)
	var target_cell: Vector2i = _get_grid_position(target)
	var attack_range: int = attack_range_override if attack_range_override >= 0 else maxi(int(attacker_stats.get("attack_range")), 0)
	return _grid_distance(attacker_cell, target_cell) <= attack_range


func _is_actor_authorized(attacker: Node) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	if _turn_manager == null:
		return true
	if attacker == _player_actor:
		return _turn_manager.is_action_available(attacker)
	return _turn_manager.is_active_actor(attacker)


func _get_combat_stats(actor: Node) -> Resource:
	if actor == null or not is_instance_valid(actor):
		return null
	var player_stats: Variant = actor.get("player_stats")
	if player_stats is PlayerStats:
		return player_stats
	var enemy_runtime: Variant = actor.get("enemy_runtime")
	if enemy_runtime is EnemyRuntime:
		return enemy_runtime.current_stats
	var enemy_stats: Variant = actor.get("enemy_stats")
	if enemy_stats is EnemyStats:
		return enemy_stats
	return null


func _get_current_hp(actor: Node, stats: Resource) -> int:
	if actor is EnemyController:
		var enemy: EnemyController = actor as EnemyController
		enemy.sync_runtime_state()
		return enemy.enemy_runtime.current_hp
	return int(stats.get("current_hp")) if stats != null else 0


func _set_current_hp(actor: Node, stats: Resource, value: int) -> void:
	if actor is EnemyController:
		(actor as EnemyController).set_current_hp(value)
		return
	if stats != null:
		stats.set("current_hp", value)


## Spends the player's action for one resolved attack. Refused attacks return
## before this point, so reaching here means a real strike happened.
func _consume_player_action(attacker: Node, consume: bool) -> void:
	if not consume or _turn_manager == null:
		return
	if attacker != _player_actor:
		return
	_turn_manager.consume_player_action(attacker)


## A stats value as a float. Stats are duck-typed (`PlayerStats` / `EnemyStats`),
## so a statistic a given actor does not define reads as `fallback` instead of
## failing the call — an enemy simply has no `damage_vs_elite`.
func _get_stat_float(stats: Resource, stat_id: StringName, fallback: float = 0.0) -> float:
	if stats == null:
		return fallback
	var value: Variant = stats.get(stat_id)
	if value == null:
		return fallback
	return float(value)


## A statistic that is a 0..1 fraction (dodge, stun chance), clamped so an authored
## affix can never exceed certainty.
func _get_stat_ratio(stats: Resource, stat_id: StringName) -> float:
	return clampf(_get_stat_float(stats, stat_id), 0.0, 1.0)


## §12 `damage_vs_elite` / `damage_vs_boss`. The bonus only applies to the tier it
## names, so a boss affix never inflates damage against normal spawns.
func _get_enemy_tier_multiplier(attacker_stats: Resource, target: Node) -> float:
	if attacker_stats == null or target == null or not is_instance_valid(target):
		return 1.0
	if not target.has_method("get_enemy_type"):
		return 1.0
	var enemy_type: int = int(target.get_enemy_type())
	var stat_id: StringName = &""
	if enemy_type == EnemyType.MINI_BOSS:
		stat_id = &"damage_vs_boss"
	elif enemy_type == EnemyType.ELITE:
		stat_id = &"damage_vs_elite"
	if stat_id.is_empty():
		return 1.0
	return 1.0 + maxf(_get_stat_float(attacker_stats, stat_id), 0.0)


## §12 Life Steal: a fraction of the damage actually dealt comes back as HP, capped
## at the attacker's maximum. The amount that landed is reported on the result so
## the presentation layer can show it.
func _apply_life_steal(attacker: Node, attacker_stats: Resource, result: DamageResult) -> void:
	if result.final_damage <= 0:
		return
	var life_steal: float = maxf(_get_stat_float(attacker_stats, &"life_steal"), 0.0)
	if life_steal <= 0.0:
		return
	var requested: int = roundi(float(result.final_damage) * life_steal)
	if requested <= 0:
		return
	var max_hp: int = maxi(int(_get_stat_float(attacker_stats, &"max_hp")), 0)
	var current_hp: int = _get_current_hp(attacker, attacker_stats)
	var healed: int = mini(requested, maxi(max_hp - current_hp, 0))
	if healed <= 0:
		return
	_set_current_hp(attacker, attacker_stats, current_hp + healed)
	if attacker.has_method("clamp_current_hp"):
		attacker.clamp_current_hp()
	result.lifesteal_heal = healed


## §12 Stun: a landed hit may stun its target, which then loses a turn
## (`StatusEffectComponent`). Only an enemy can be stunned, and only by an actor
## whose stats carry a stun chance — a target that is already stunned is refreshed
## without being announced again.
func _apply_stun(attacker_stats: Resource, target: Node, result: DamageResult) -> void:
	if result.target_defeated or target == null or not is_instance_valid(target):
		return
	if not target.has_method("apply_stun"):
		return
	var stun_chance: float = _get_stat_ratio(attacker_stats, &"stun_chance")
	if stun_chance <= 0.0 or _random_number_generator.randf() >= stun_chance:
		return
	if bool(target.apply_stun(StatusEffectComponent.STUN_TURNS)):
		result.applied_status_id = StatusEffectComponent.STUN
		result.applied_status_turns = StatusEffectComponent.STUN_TURNS


func _get_grid_position(actor: Node) -> Vector2i:
	if actor.has_method("get_grid_position"):
		return actor.get_grid_position()
	var value: Variant = actor.get("grid_position")
	if value is Vector2i:
		return value
	return Vector2i.ZERO


func _get_actor_id(actor: Node) -> StringName:
	if actor == null or not is_instance_valid(actor):
		return &""
	var player_id: Variant = actor.get("player_id")
	if player_id is StringName:
		return StringName(player_id)
	var enemy_id: Variant = actor.get("enemy_id")
	if enemy_id is StringName:
		return StringName(enemy_id)
	return &""


func _grid_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
