class_name SubHeroCombatManager
extends Node

const SubHeroQualityResource = preload("res://scripts/sub_hero/sub_hero_quality.gd")
const DamageNumberResource = preload("res://scripts/combat/damage_number.gd")

## A time-based combat layer that deliberately does not participate in the
## turn manager or query grid distance/pathfinding.
signal attack_resolved(result: DamageResult)
signal attack_feedback_requested(result: DamageResult, target: Node)
signal cooldown_started(hero_id: StringName, duration: float)
signal target_changed(hero_id: StringName, target: Node)
signal combat_cleared
signal combat_state_changed(is_running: bool)

@export_range(0.0, 2.0, 0.01) var level_damage_growth: float = 0.10
@export_range(0.1, 3.0, 0.01) var rare_quality_multiplier: float = 1.10
@export_range(0.1, 3.0, 0.01) var legendary_quality_multiplier: float = 1.20


class ActiveSubHeroState:
	var instance: SubHeroInstance
	var data: SubHeroData
	var elapsed: float = 0.0
	var target: Node


var _active_states: Array[ActiveSubHeroState] = []
var _enemies: Array[Node] = []
var _is_running: bool = false
var _is_paused: bool = false


func _process(delta: float) -> void:
	if not _is_running or _is_paused or delta <= 0.0:
		return
	for state in _active_states:
		_process_sub_hero(state, delta)


func register_active_sub_hero(instance: SubHeroInstance, data: SubHeroData) -> bool:
	if instance == null or data == null or not data.is_valid() or instance.hero_id != data.id:
		return false
	var state := ActiveSubHeroState.new()
	state.instance = instance
	state.data = data
	_active_states.append(state)
	return true


func clear_active_sub_heroes() -> void:
	_active_states.clear()


func start_combat(enemies: Array[Node]) -> void:
	_disconnect_enemy_signals()
	_enemies = enemies.duplicate()
	for state in _active_states:
		state.elapsed = 0.0
		state.target = null
	_connect_enemy_signals()
	_is_paused = false
	_is_running = true
	combat_state_changed.emit(true)
	# Pre-start a full countdown for the first attack. The first swing still
	# waits a full interval, but the UI bar (and CHARGING label) now reflect
	# that wait instead of showing an empty bar + READY. combat_state_changed
	# above resets the bars first; emitting afterwards fills them.
	for state in _active_states:
		if state.data != null and state.instance != null:
			cooldown_started.emit(state.instance.hero_id, maxf(state.data.attack_interval, 0.1))


func stop_combat() -> void:
	if not _is_running and _enemies.is_empty():
		return
	_is_running = false
	_is_paused = false
	for state in _active_states:
		state.elapsed = 0.0
		state.target = null
	_disconnect_enemy_signals()
	_enemies.clear()
	combat_state_changed.emit(false)


func set_combat_paused(paused: bool) -> void:
	_is_paused = paused


func is_combat_running() -> bool:
	return _is_running


func is_combat_paused() -> bool:
	return _is_paused


func add_enemy(enemy: Node) -> void:
	if enemy == null or _enemies.has(enemy):
		return
	_enemies.append(enemy)
	_connect_enemy_signal(enemy)


func get_current_target(hero_id: StringName) -> Node:
	for state in _active_states:
		if state.instance.hero_id == hero_id:
			return state.target
	return null


## Public calculation hook for future Main Hero, synergy, boss, or status
## modifiers. Quality contributes a moderate multiplier; it is not the only
## source of quality identity because definitions also own their base damage,
## interval, tags, and future effects.
func calculate_subhero_damage(data: SubHeroData, instance: SubHeroInstance) -> int:
	if data == null or instance == null:
		return 0
	var level_multiplier: float = 1.0 + float(maxi(instance.level, 1) - 1) * maxf(level_damage_growth, 0.0)
	var quality_multiplier: float = _get_quality_multiplier(data.quality)
	return maxi(roundi(float(data.attack_damage) * level_multiplier * quality_multiplier), 1)


func _process_sub_hero(state: ActiveSubHeroState, delta: float) -> void:
	if state.data == null or state.instance == null or state.data.attack_interval <= 0.0:
		return
	state.elapsed += delta
	var interval: float = maxf(state.data.attack_interval, 0.1)
	while state.elapsed >= interval and _is_running and not _is_paused:
		state.elapsed -= interval
		var target := _select_target(state.data.target_rule)
		if target == null:
			_set_state_target(state, null)
			state.elapsed = 0.0
			return
		_set_state_target(state, target)
		_resolve_attack(state, target)
		if not _is_running:
			return
		if not _has_living_enemies():
			combat_cleared.emit()
			stop_combat()
			return


func _resolve_attack(state: ActiveSubHeroState, target: Node) -> void:
	var result := DamageResult.new()
	result.attacker_id = state.instance.hero_id
	result.target_id = _get_enemy_id(target)
	if not _is_living_enemy(target):
		result.is_miss = true
		attack_resolved.emit(result)
		return

	var damage: int = calculate_subhero_damage(state.data, state.instance)
	var current_hp: int = _get_current_hp(target)
	if not _set_current_hp(target, maxi(current_hp - damage, 0)):
		result.is_miss = true
		attack_resolved.emit(result)
		return

	result.raw_damage = damage
	result.final_damage = damage
	result.target_defeated = _get_current_hp(target) <= 0
	if target.has_method("clamp_current_hp"):
		target.clamp_current_hp()
	if target.has_method("queue_redraw"):
		target.queue_redraw()
	_spawn_damage_number(target, result)
	attack_feedback_requested.emit(result, target)
	cooldown_started.emit(state.instance.hero_id, maxf(state.data.attack_interval, 0.1))
	if result.target_defeated and target.has_method("handle_defeat"):
		target.handle_defeat()
	if state.data.unique_effect != null and state.data.unique_effect.has_method("on_attack_resolved"):
		state.data.unique_effect.on_attack_resolved(state.instance, target, result.final_damage, {
			"target_defeated": result.target_defeated,
			"sub_hero_data": state.data,
		})
	attack_resolved.emit(result)


func _spawn_damage_number(target: Node, result: DamageResult) -> void:
	if target == null or not is_instance_valid(target) or not target is Node2D:
		return
	var damage_number := DamageNumberResource.new()
	add_child(damage_number)
	damage_number.global_position = (target as Node2D).global_position + Vector2(0.0, -30.0)
	damage_number.setup(result.final_damage, result.is_critical)


func _select_target(target_rule: int) -> Node:
	var living_enemies: Array[Node] = []
	for enemy in _enemies:
		if _is_living_enemy(enemy):
			living_enemies.append(enemy)
	if living_enemies.is_empty():
		return null

	if target_rule == SubHeroTargetRule.BOSS_FIRST:
		var priority_target := _select_lowest_hp(living_enemies, true)
		if priority_target != null:
			return priority_target
	return _select_lowest_hp(living_enemies, false)

	# LOWEST_HP is the default and CLOSEST_TO_DEFEAT intentionally shares this
	# deterministic MVP behavior until enemy distance-independent rules diverge.
	return _select_lowest_hp(living_enemies, false)


func _select_lowest_hp(enemies: Array[Node], priority_only: bool) -> Node:
	var best_target: Node
	var best_hp: int = 2147483647
	for enemy in enemies:
		if priority_only and not _is_priority_enemy(enemy):
			continue
		var current_hp: int = _get_current_hp(enemy)
		if current_hp < best_hp:
			best_hp = current_hp
			best_target = enemy
	return best_target


func _is_priority_enemy(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if enemy.has_method("is_mini_boss") and enemy.is_mini_boss():
		return true
	var enemy_data: Variant = enemy.get("enemy_data")
	if enemy_data == null:
		return false
	var enemy_type: int = int(enemy_data.get("enemy_type"))
	return enemy_type == EnemyType.ELITE or enemy_type == EnemyType.MINI_BOSS


func _is_living_enemy(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if enemy.has_method("is_defeated") and enemy.is_defeated():
		return false
	return _get_current_hp(enemy) > 0


func _has_living_enemies() -> bool:
	for enemy in _enemies:
		if _is_living_enemy(enemy):
			return true
	return false


func _get_current_hp(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	if enemy.has_method("get_current_hp"):
		return maxi(int(enemy.get_current_hp()), 0)
	var enemy_runtime: Variant = enemy.get("enemy_runtime")
	if enemy_runtime != null:
		return maxi(int(enemy_runtime.get("current_hp")), 0)
	var enemy_stats: Variant = enemy.get("enemy_stats")
	if enemy_stats != null:
		return maxi(int(enemy_stats.get("current_hp")), 0)
	return 0


func _set_current_hp(enemy: Node, value: int) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var safe_value: int = maxi(value, 0)
	if enemy.has_method("set_current_hp"):
		enemy.set_current_hp(safe_value)
		if enemy.has_method("queue_redraw"):
			enemy.queue_redraw()
		return true
	var enemy_runtime: Variant = enemy.get("enemy_runtime")
	if enemy_runtime != null:
		enemy_runtime.set("current_hp", safe_value)
		if enemy.has_method("queue_redraw"):
			enemy.queue_redraw()
		return true
	var enemy_stats: Variant = enemy.get("enemy_stats")
	if enemy_stats != null:
		enemy_stats.set("current_hp", safe_value)
		if enemy.has_method("queue_redraw"):
			enemy.queue_redraw()
		return true
	return false


func _get_enemy_id(enemy: Node) -> StringName:
	if enemy == null or not is_instance_valid(enemy):
		return &""
	var enemy_id: Variant = enemy.get("enemy_id")
	return enemy_id if enemy_id is StringName else &""


func _get_quality_multiplier(quality: int) -> float:
	match quality:
		SubHeroQualityResource.RARE:
			return maxf(rare_quality_multiplier, 0.1)
		SubHeroQualityResource.LEGENDARY:
			return maxf(legendary_quality_multiplier, 0.1)
		_:
			return 1.0


func _connect_enemy_signals() -> void:
	for enemy in _enemies:
		_connect_enemy_signal(enemy)


func _connect_enemy_signal(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_signal("defeated"):
		return
	var defeated_signal: Signal = enemy.defeated
	if not defeated_signal.is_connected(_on_enemy_defeated):
		defeated_signal.connect(_on_enemy_defeated)


func _disconnect_enemy_signals() -> void:
	for enemy in _enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.has_signal("defeated"):
			continue
		var defeated_signal: Signal = enemy.defeated
		if defeated_signal.is_connected(_on_enemy_defeated):
			defeated_signal.disconnect(_on_enemy_defeated)


func _on_enemy_defeated(enemy: Node = null) -> void:
	for state in _active_states:
		if enemy == null or state.target == enemy:
			_set_state_target(state, null)
	if _is_running and not _has_living_enemies():
		combat_cleared.emit()
		stop_combat()


func _set_state_target(state: ActiveSubHeroState, target: Node) -> void:
	if state.target == target:
		return
	state.target = target
	target_changed.emit(state.instance.hero_id, target)
