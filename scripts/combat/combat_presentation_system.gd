class_name CombatPresentationSystem
extends Node

const GameLocaleResource = preload("res://scripts/systems/game_locale.gd")

## Event-driven combat presentation layer. It only reacts to gameplay signals
## (damage is already resolved when they fire) and never writes gameplay,
## grid or turn state. All motion happens through CharacterToken offsets,
## procedural CombatVFX, DamageNumbers and camera offset shake.
##
## Await safety: coroutines here await token.motion_phase_finished (emitted
## even when a phase is interrupted or the token leaves the tree) and use
## node-bound tween timers (_wait), so nothing can hang when the scene is
## freed mid-animation.

@export var combat_system_path: NodePath = NodePath("../CombatSystem")
@export var auto_combat_path: NodePath = NodePath("../AutoCombatController")
@export var camera_path: NodePath = NodePath("../CombatCamera")
@export var player_path: NodePath = NodePath("../Player")
@export var stage_manager_path: NodePath = NodePath("../StageManager")
@export var sub_hero_manager_path: NodePath = NodePath("../SubHeroCombatManager")

var _root: Node
var _combat_system: CombatSystem
var _auto_combat: AutoCombatController
var _camera: Camera2D
var _player: PlayerController
var _stage_manager: StageManager
var _sub_hero_manager: SubHeroCombatManager
var _vfx_layer: Node2D
var _number_layer: Node2D
var _locale: GameLocale = GameLocaleResource.new()
var _shake_tween: Tween
var _shake_rng := RandomNumberGenerator.new()
var _number_rng := RandomNumberGenerator.new()
var _speed_multiplier: float = 1.0


func _ready() -> void:
	_root = get_parent()
	_combat_system = get_node_or_null(combat_system_path) as CombatSystem
	_auto_combat = get_node_or_null(auto_combat_path) as AutoCombatController
	_camera = get_node_or_null(camera_path) as Camera2D
	_player = get_node_or_null(player_path) as PlayerController
	_stage_manager = get_node_or_null(stage_manager_path) as StageManager
	_sub_hero_manager = get_node_or_null(sub_hero_manager_path) as SubHeroCombatManager
	_vfx_layer = Node2D.new()
	_vfx_layer.name = &"VfxLayer"
	add_child(_vfx_layer)
	_number_layer = Node2D.new()
	_number_layer.name = &"NumberLayer"
	add_child(_number_layer)
	_shake_rng.randomize()
	_number_rng.randomize()
	if _combat_system != null:
		_combat_system.attack_resolved.connect(_on_attack_resolved)
		_combat_system.actor_died.connect(_on_actor_died)
	if _auto_combat != null:
		_auto_combat.auto_mode_changed.connect(_on_auto_mode_changed)
		_auto_combat.farming_changed.connect(_on_farming_changed)
		_auto_combat.game_speed_changed.connect(_on_game_speed_changed)
	if _player != null:
		_player.healing_item_used.connect(_on_healing_item_used)
		_player.item_used.connect(_on_item_used)
	if _sub_hero_manager != null:
		_sub_hero_manager.attack_feedback_requested.connect(_on_sub_hero_attack_feedback_requested)
	if _stage_manager != null:
		# Spawned units create their tokens in _ready; sync speeds right after.
		_stage_manager.stage_started.connect(_on_stage_started_sync_speed)
		_stage_manager.enemy_spawned.connect(_on_enemy_spawned_sync_speed)
	get_viewport().size_changed.connect(_center_camera)
	_center_camera()
	_refresh_speed()


func _exit_tree() -> void:
	_kill_shake()
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = Vector2.ZERO


## Called by GridTest after _layout_portrait_grid() teleports units: clears
## any residual token offset so visuals re-anchor to the new positions.
func notify_layout_changed() -> void:
	for token in _all_tokens():
		token.snap()


## Dev-panel entry point: plays a presentation case against real nodes with a
## fabricated DamageResult. Never touches damage/turn/grid state.
func test_effect(case: StringName) -> void:
	_run_test_effect(case)


# ---------------------------------------------------------------------------
# Main attack sequence
# ---------------------------------------------------------------------------


func _on_attack_resolved(result: DamageResult) -> void:
	if result == null:
		return
	_play_attack(result)


func _play_attack(result: DamageResult) -> void:
	var attacker: Node = result.attacker
	var target: Node = result.target
	if not _is_presentable(attacker) or not _is_presentable(target):
		return
	var mult: float = _speed_multiplier
	var dir: Vector2 = (target as Node2D).global_position - (attacker as Node2D).global_position

	if result.is_miss:
		var dodge_token := _token_for(target)
		if dodge_token != null and not dodge_token.is_dying():
			dodge_token.play_dodge(dir)
		_spawn_number((target as Node2D).global_position, DamageNumber.Kind.MISS, 0, _locale.translate("fx.miss"))
		return

	var heavy: bool = result.skill_id == &"execution_strike"
	var is_projectile: bool = result.skill_id == &"arcane_bolt"
	var is_player_attack: bool = attacker == _player
	var intensity: float = CombatPresentationConfig.PLAYER_INTENSITY if is_player_attack else 1.0
	var strong: bool = result.is_critical or heavy or is_player_attack
	var attacker_token := _token_for(attacker)
	var target_token := _token_for(target)

	# 1) Anticipation, then dash (projectile casts hold position instead).
	if attacker_token != null and not attacker_token.is_dying():
		attacker_token.wind_up(dir, heavy, intensity)
		await attacker_token.motion_phase_finished
		if not is_instance_valid(attacker_token):
			return
		if not is_projectile:
			attacker_token.dash(dir, heavy, intensity)
			await attacker_token.motion_phase_finished
			if not is_instance_valid(attacker_token):
				return

	# 2) Projectile travel (the HUD keeps its own Sub Hero projectile; this
	#    path only serves grid spells such as arcane_bolt).
	if is_projectile:
		if not is_instance_valid(target):
			_recover_attacker(attacker_token if is_instance_valid(attacker_token) else null)
			return
		var projectile := CombatVFX.new()
		_vfx_layer.add_child(projectile)
		projectile.setup_projectile(
			(attacker as Node2D).global_position + Vector2(0.0, -12.0),
			(target as Node2D).global_position,
			&"arcane",
			mult
		)
		await _wait(CombatPresentationConfig.PROJECTILE_TRAVEL * mult)
	if not is_instance_valid(target):
		_recover_attacker(attacker_token if is_instance_valid(attacker_token) else null)
		return

	# 3) Impact: VFX, hit stop (token tween pause — never Engine.time_scale).
	var target_pos: Vector2 = (target as Node2D).global_position
	if is_projectile:
		_spawn_vfx(&"arcane", target_pos, dir, strong, mult)
	else:
		_spawn_vfx(_vfx_for_skill(result.skill_id), target_pos, dir, strong, mult)
		if result.skill_id == &"whirlwind" and is_instance_valid(attacker):
			_spawn_vfx(&"area", (attacker as Node2D).global_position, dir, strong, mult)
	var hitstop: float = _hitstop_for(result, heavy) * mult
	if attacker_token != null and is_instance_valid(attacker_token):
		attacker_token.freeze(hitstop)
	if target_token != null and is_instance_valid(target_token):
		target_token.freeze(hitstop)
	await _wait(hitstop + CombatPresentationConfig.IMPACT_PAUSE * mult)

	# 4) Hit reaction + damage number + camera shake.
	if is_instance_valid(target):
		target_pos = (target as Node2D).global_position
		var variant: int = CharacterToken.HitVariant.NORMAL
		if result.is_critical:
			variant = CharacterToken.HitVariant.CRITICAL
		elif heavy:
			variant = CharacterToken.HitVariant.HEAVY
		if target_token != null and is_instance_valid(target_token) and not target_token.is_dying():
			target_token.play_hit_reaction(variant, dir)
		var kind: int = DamageNumber.Kind.CRITICAL if result.is_critical else DamageNumber.Kind.NORMAL
		var label: String = ""
		if result.is_critical:
			label = "%s %d" % [_locale.translate("fx.critical"), result.final_damage]
		_spawn_number(target_pos, kind, result.final_damage, label)
	# The attacker (or its token) can be freed by stage cleanup while this
	# coroutine awaits — never pass a freed reference across typed parameters.
	_shake_for(result, heavy, attacker if is_instance_valid(attacker) else null)

	# 5) Recovery.
	_recover_attacker(attacker_token if is_instance_valid(attacker_token) else null)


func _on_actor_died(actor: Node) -> void:
	_play_death(actor)


func _play_death(actor: Node) -> void:
	await _wait(CombatPresentationConfig.DEATH_DELAY * _speed_multiplier)
	if not is_instance_valid(actor):
		return
	var token := _token_for(actor)
	if token == null or token.is_dying():
		return
	token.play_death()


# ---------------------------------------------------------------------------
# Spells / Sub Heroes / Healing
# ---------------------------------------------------------------------------


func _play_spell(caster: Node, target: Node, element: StringName, is_projectile: bool, is_area: bool) -> void:
	if not _is_presentable(caster) or not _is_presentable(target):
		return
	var mult: float = _speed_multiplier
	var dir: Vector2 = (target as Node2D).global_position - (caster as Node2D).global_position
	var is_player_cast: bool = caster == _player
	var intensity: float = CombatPresentationConfig.PLAYER_INTENSITY if is_player_cast else 1.0
	var caster_token := _token_for(caster)
	if caster_token != null and not caster_token.is_dying():
		caster_token.wind_up(dir, false, intensity)
		await caster_token.motion_phase_finished
		if not is_instance_valid(caster_token):
			return
	if is_projectile:
		if not is_instance_valid(target):
			_recover_attacker(caster_token if is_instance_valid(caster_token) else null)
			return
		var projectile := CombatVFX.new()
		_vfx_layer.add_child(projectile)
		projectile.setup_projectile(
			(caster as Node2D).global_position + Vector2(0.0, -12.0),
			(target as Node2D).global_position,
			element,
			mult
		)
		await _wait(CombatPresentationConfig.PROJECTILE_TRAVEL * mult)
	if not is_instance_valid(target):
		_recover_attacker(caster_token if is_instance_valid(caster_token) else null)
		return
	var target_pos: Vector2 = (target as Node2D).global_position
	_spawn_vfx(element, target_pos, dir, is_player_cast, mult)
	if is_area:
		_spawn_vfx(&"area", target_pos, dir, is_player_cast, mult)
	var target_token := _token_for(target)
	if target_token != null and is_instance_valid(target_token) and not target_token.is_dying():
		target_token.play_hit_reaction(CharacterToken.HitVariant.NORMAL, dir)
	_recover_attacker(caster_token if is_instance_valid(caster_token) else null)


func _on_sub_hero_attack_feedback_requested(result: DamageResult, target: Node) -> void:
	_play_sub_hero_feedback(result, target)


## The HUD already draws the Sub Hero projectile (SubHeroAttackEffect); this
## only lands the world-space impact once that projectile would have arrived.
func _play_sub_hero_feedback(result: DamageResult, target: Node) -> void:
	if result == null or result.is_miss or not _is_presentable(target):
		return
	var mult: float = _speed_multiplier
	await _wait(CombatPresentationConfig.PROJECTILE_TRAVEL * mult)
	if not is_instance_valid(target):
		return
	var target_pos: Vector2 = (target as Node2D).global_position
	_spawn_vfx(&"impact", target_pos, Vector2.DOWN, false, mult)
	_spawn_number(target_pos, DamageNumber.Kind.NORMAL, result.final_damage, "")
	var token := _token_for(target)
	if token != null and not token.is_dying():
		token.play_hit_reaction(CharacterToken.HitVariant.NORMAL, Vector2.DOWN)
	if result.target_defeated:
		_play_death(target)


func _on_healing_item_used(_remaining_items: int, amount_healed: int) -> void:
	_play_heal(_player, amount_healed)


func _on_item_used(_item: EquipmentInstance, amount_healed: int) -> void:
	_play_heal(_player, amount_healed)


func _play_heal(unit: Node, amount: int) -> void:
	if amount <= 0 or not _is_presentable(unit):
		return
	var position: Vector2 = (unit as Node2D).global_position
	_spawn_vfx(&"heal", position, Vector2.UP, false, _speed_multiplier)
	_spawn_number(position, DamageNumber.Kind.HEAL, amount, "")


# ---------------------------------------------------------------------------
# Camera shake (combat area only — the HUD lives on a CanvasLayer)
# ---------------------------------------------------------------------------


func _shake_for(result: DamageResult, heavy: bool, attacker: Node) -> void:
	if heavy:
		_shake(CombatPresentationConfig.SHAKE_HEAVY.x, CombatPresentationConfig.SHAKE_HEAVY.y)
	elif result.is_critical:
		_shake(CombatPresentationConfig.SHAKE_CRIT.x, CombatPresentationConfig.SHAKE_CRIT.y)
	elif _is_boss(attacker):
		_shake(CombatPresentationConfig.SHAKE_NORMAL.x, CombatPresentationConfig.SHAKE_NORMAL.y)


func _shake(intensity: float, duration: float) -> void:
	if _camera == null or not is_instance_valid(_camera) or duration <= 0.0:
		return
	_kill_shake()
	_shake_tween = create_tween()
	_shake_tween.tween_method(_apply_shake.bind(intensity), 0.0, 1.0, duration * _speed_multiplier)
	_shake_tween.tween_callback(_finish_shake)


func _apply_shake(ratio: float, intensity: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var decay: float = 1.0 - ratio
	_camera.offset = Vector2(
		_shake_rng.randf_range(-1.0, 1.0),
		_shake_rng.randf_range(-1.0, 1.0)
	) * intensity * decay


func _finish_shake() -> void:
	_shake_tween = null
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = Vector2.ZERO


func _kill_shake() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = Vector2.ZERO


func _center_camera() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	# Equivalent to the previous camera-less framing: the camera sits at the
	# middle of the viewport and only shake writes to `offset`.
	_camera.position = viewport.get_visible_rect().size * 0.5


# ---------------------------------------------------------------------------
# Speed integration (AutoCombatController is the single source of speed)
# ---------------------------------------------------------------------------


func _on_auto_mode_changed(_enabled: bool) -> void:
	_refresh_speed()


func _on_farming_changed(_enabled: bool) -> void:
	_refresh_speed()


func _on_game_speed_changed(_speed: int) -> void:
	_refresh_speed()


func _on_stage_started_sync_speed(_stage_state: StageState, _enemies: Array[Node]) -> void:
	_refresh_speed.call_deferred()


func _on_enemy_spawned_sync_speed(_enemy: Node) -> void:
	_refresh_speed.call_deferred()


func _refresh_speed() -> void:
	if _auto_combat == null or not is_instance_valid(_auto_combat):
		return
	_speed_multiplier = CombatPresentationConfig.get_speed_multiplier(
		_auto_combat.is_auto_enabled() or _auto_combat.is_farming_enabled(),
		_auto_combat.get_game_speed()
	)
	for token in _all_tokens():
		token.speed_multiplier = _speed_multiplier


# ---------------------------------------------------------------------------
# Dev-panel test cases
# ---------------------------------------------------------------------------


func _run_test_effect(case: StringName) -> void:
	var target: Node = _first_living_enemy()
	match case:
		&"normal":
			_play_attack(_fake_result(target, 12, false, &"", false))
		&"critical":
			_play_attack(_fake_result(target, 34, true, &"", false))
		&"heavy":
			_play_attack(_fake_result(target, 40, false, &"execution_strike", false))
		&"miss":
			_play_attack(_fake_result(target, 0, false, &"", true))
		&"block":
			if not _is_presentable(target):
				return
			var block_token := _token_for(target)
			if block_token != null and not block_token.is_dying():
				var block_dir: Vector2 = (target as Node2D).global_position - _player.global_position if _player != null else Vector2.DOWN
				block_token.play_hit_reaction(CharacterToken.HitVariant.BLOCK, block_dir)
			_spawn_number((target as Node2D).global_position, DamageNumber.Kind.BLOCK, 0, _locale.translate("fx.block"))
		&"fire":
			_play_spell(_player, target, &"fire", false, false)
		&"lightning":
			_play_spell(_player, target, &"lightning", false, true)
		&"heal":
			_play_heal(_player, 25)
		&"death":
			await _run_death_test(target)


## Plays the death animation on a living enemy and restores it afterwards, so
## the dev button can be pressed repeatedly without touching gameplay state.
func _run_death_test(target: Node) -> void:
	if not _is_presentable(target):
		return
	var token := _token_for(target)
	if token == null or token.is_dying():
		return
	token.play_death()
	await token.death_finished
	if is_instance_valid(token):
		token.reset_visuals()


func _fake_result(target: Node, damage: int, critical: bool, skill_id: StringName, miss: bool) -> DamageResult:
	var result := DamageResult.new()
	result.attacker = _player
	result.target = target
	result.final_damage = damage
	result.is_critical = critical
	result.skill_id = skill_id
	result.is_miss = miss
	return result


func _first_living_enemy() -> Node:
	if _root == null or not is_instance_valid(_root):
		return null
	for node in _root.find_children("*", "EnemyController", true, false):
		var enemy := node as EnemyController
		if enemy != null and is_instance_valid(enemy) and not enemy.is_defeated():
			return enemy
	return null


# ---------------------------------------------------------------------------
# Spawners and helpers
# ---------------------------------------------------------------------------


func _vfx_for_skill(skill_id: StringName) -> StringName:
	match skill_id:
		&"whirlwind":
			return &"slash"
		&"execution_strike":
			return &"heavy_slash"
		&"arcane_bolt":
			return &"arcane"
		_:
			return &"slash"


func _hitstop_for(result: DamageResult, heavy: bool) -> float:
	if heavy:
		return CombatPresentationConfig.HITSTOP_HEAVY
	if result.is_critical:
		return CombatPresentationConfig.HITSTOP_CRIT
	return CombatPresentationConfig.HITSTOP_NORMAL


func _spawn_vfx(vfx_id: StringName, world_position: Vector2, dir: Vector2, is_strong: bool, mult: float) -> void:
	var vfx := CombatVFX.new()
	_vfx_layer.add_child(vfx)
	vfx.global_position = world_position
	vfx.setup(vfx_id, dir, is_strong, mult)


func _spawn_number(world_position: Vector2, kind: int, amount: int, label: String) -> void:
	var number := DamageNumber.new()
	_number_layer.add_child(number)
	number.global_position = world_position + Vector2(_number_rng.randf_range(-12.0, 12.0), -30.0)
	number.setup(kind, amount, label, _speed_multiplier)


func _token_for(unit: Node) -> CharacterToken:
	if unit == null or not is_instance_valid(unit):
		return null
	var token := unit.get_node_or_null(^"CharacterToken") as CharacterToken
	if token != null:
		token.speed_multiplier = _speed_multiplier
	return token


func _all_tokens() -> Array[CharacterToken]:
	var tokens: Array[CharacterToken] = []
	if _root == null or not is_instance_valid(_root):
		return tokens
	for node in _root.find_children("CharacterToken", "CharacterToken", true, false):
		var token := node as CharacterToken
		if token != null:
			tokens.append(token)
	return tokens


func _recover_attacker(token: CharacterToken) -> void:
	if token != null and is_instance_valid(token) and not token.is_dying():
		token.recover()


func _is_presentable(unit: Node) -> bool:
	return unit != null and is_instance_valid(unit) and unit is Node2D and unit.is_inside_tree()


func _is_boss(attacker: Node) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	var boss_flag: Variant = attacker.get("is_mini_boss")
	return boss_flag is bool and bool(boss_flag)


## Node-bound wait: dies with this node, so an await can never resume on a
## freed presentation system (no orphan-timer errors on scene changes).
func _wait(seconds: float) -> void:
	if seconds <= 0.0 or not is_inside_tree():
		return
	var wait_tween := create_tween()
	wait_tween.tween_interval(seconds)
	await wait_tween.finished
