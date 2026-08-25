class_name CombatSystem
extends Node

signal attack_resolved(result: DamageResult)
signal actor_died(actor: Node)

@export var feedback_parent_path: NodePath

var _random_number_generator := RandomNumberGenerator.new()
var _turn_manager: TurnManager
var _player_actor: Node


func _ready() -> void:
	_random_number_generator.randomize()


func attach_turn_manager(turn_manager: TurnManager) -> void:
	_turn_manager = turn_manager


func set_player_actor(player: Node) -> void:
	_player_actor = player


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


func resolve_attack(attacker: Node, target: Node, damage_multiplier: float = 1.0, attack_range_override: int = -1) -> DamageResult:
	var result := DamageResult.new()
	result.attacker_id = _get_actor_id(attacker)
	result.target_id = _get_actor_id(target)
	if not _is_valid_attack(attacker, target, attack_range_override):
		result.is_miss = true
		attack_resolved.emit(result)
		return result

	var attacker_stats: Resource = _get_combat_stats(attacker)
	var target_stats: Resource = _get_combat_stats(target)
	var attack_power: int = maxi(int(attacker_stats.get("attack")), 0)
	var defense: int = maxi(int(target_stats.get("defense")), 0)
	result.raw_damage = maxi(1, attack_power - defense)
	result.final_damage = maxi(1, roundi(float(result.raw_damage) * maxf(damage_multiplier, 0.0)))

	var critical_chance: float = clampf(float(attacker_stats.get("critical_chance")), 0.0, 1.0)
	var critical_damage: float = maxf(float(attacker_stats.get("critical_damage")), 1.0)
	if critical_chance > 0.0 and _random_number_generator.randf() < critical_chance:
		result.is_critical = true
		result.final_damage = maxi(1, roundi(result.raw_damage * critical_damage))

	var remaining_hp: int = maxi(int(target_stats.get("current_hp")) - result.final_damage, 0)
	target_stats.set("current_hp", remaining_hp)
	result.target_defeated = remaining_hp <= 0
	if target.has_method("clamp_current_hp"):
		target.clamp_current_hp()
	if result.target_defeated and target.has_method("handle_defeat"):
		target.handle_defeat()
	if is_instance_valid(target) and target.has_method("queue_redraw"):
		target.queue_redraw()
	_spawn_damage_number(target, result)
	attack_resolved.emit(result)
	if result.target_defeated:
		actor_died.emit(target)
	return result


func _on_attack_requested(attacker: Node, target: Node) -> void:
	resolve_attack(attacker, target)
	if _turn_manager == null or attacker != _player_actor:
		return
	if _turn_manager.is_player_turn():
		_turn_manager.complete_player_turn()


func _on_area_attack_requested(attacker: Node, target: Node, attack_range: int, damage_multiplier: float) -> void:
	resolve_attack(attacker, target, damage_multiplier, attack_range)


func _is_valid_attack(attacker: Node, target: Node, attack_range_override: int = -1) -> bool:
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		return false
	if attacker == target:
		return false
	var attacker_stats: Resource = _get_combat_stats(attacker)
	var target_stats: Resource = _get_combat_stats(target)
	if attacker_stats == null or target_stats == null:
		return false
	if int(attacker_stats.get("current_hp")) <= 0 or int(target_stats.get("current_hp")) <= 0:
		return false
	var attacker_cell: Vector2i = _get_grid_position(attacker)
	var target_cell: Vector2i = _get_grid_position(target)
	var attack_range: int = attack_range_override if attack_range_override >= 0 else maxi(int(attacker_stats.get("attack_range")), 0)
	return _grid_distance(attacker_cell, target_cell) <= attack_range


func _get_combat_stats(actor: Node) -> Resource:
	if actor == null or not is_instance_valid(actor):
		return null
	var player_stats: Variant = actor.get("player_stats")
	if player_stats is PlayerStats:
		return player_stats
	var enemy_stats: Variant = actor.get("enemy_stats")
	if enemy_stats is EnemyStats:
		return enemy_stats
	return null


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


func _spawn_damage_number(target: Node, result: DamageResult) -> void:
	if target == null or not is_instance_valid(target) or not target is Node2D:
		return
	var feedback_parent: Node = self
	if not feedback_parent_path.is_empty():
		var configured_parent := get_node_or_null(feedback_parent_path)
		if configured_parent != null:
			feedback_parent = configured_parent
	var damage_number := DamageNumber.new()
	feedback_parent.add_child(damage_number)
	damage_number.global_position = target.global_position + Vector2(0, -30)
	damage_number.setup(result.final_damage, result.is_critical)
