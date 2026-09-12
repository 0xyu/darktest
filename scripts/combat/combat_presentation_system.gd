class_name CombatPresentationSystem
extends Node

const GameLocaleResource = preload("res://scripts/systems/game_locale.gd")

## Emitted once the last player attack sequence started by the hero's turn
## action has fully finished playing. The turn system waits on this before
## starting the enemy phase so enemies do not begin moving/attacking while the
## player's own swing is still animating.
signal player_attacks_idle

## Emitted when the first enemy strike of a presentation sequence starts
## animating (true) and once the last one has completely finished (false). The
## combat scene uses it to hold the hero's MOVEMENT while an enemy swing is on
## screen: the hero may still act from the cell it stands on, but stepping to
## another cell would visibly race the enemy's attack.
signal enemy_attack_presentation_changed(active: bool)

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
## Number of player attack sequences (basic attacks and per-target skill hits)
## currently still animating. Reaches zero once the hero's action reads as done.
var _active_player_attacks: int = 0
## Number of enemy attack sequences (boss multi-hits included) currently still
## animating. Enemy turn bookkeeping ends the enemy phase as soon as the strike
## is RESOLVED, so this counter is what tells whether the swing is still on
## screen; player-driven movement stays locked while it is above zero.
var _active_enemy_attacks: int = 0
## Number of Sub Hero impact sequences still in flight (projectile travel, impact,
## damage number and the death they may trigger). Counted from the request itself
## so a queued sequence is never missed while it is still travelling.
var _active_impact_feedback: int = 0
## Number of death animations on screen, counted from the actor's death — before
## the collapse's start delay — until the collapse has finished.
var _active_deaths: int = 0


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


## Called by grid_combat after _layout_portrait_grid() teleports units: clears
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


## True while the hero's attack animation from its current turn action is still
## playing. The turn manager polls this before it lets enemies take their turn,
## so a manual attack reads as one finished swing before the enemy reacts.
func is_player_attack_active() -> bool:
	return _active_player_attacks > 0


## True while ANY combat presentation sequence is still on screen: the hero's own
## attack, an enemy strike, a Sub Hero impact, or a death animation.
##
## Gameplay is already decided when these play (the last enemy counts as defeated
## the moment its HP reaches zero), so a consumer that rebuilds the arena — the
## FARMING re-spawn — polls this first and otherwise frees the enemy in the middle
## of its final blow, losing the damage number and the death animation.
func is_presentation_active() -> bool:
	return (
		_active_player_attacks > 0
		or _active_enemy_attacks > 0
		or _active_impact_feedback > 0
		or _active_deaths > 0
	)


func _on_attack_resolved(result: DamageResult) -> void:
	if result == null:
		return
	# Only the hero's own attack sequences gate the enemy phase; sub-hero and
	# enemy strikes are independent and must never be counted here.
	var is_player_attacker: bool = is_instance_valid(result.attacker) and result.attacker == _player
	# Enemy strikes are the only ones that lock the hero's movement: the enemy turn
	# is already over by the time the swing lands on screen, so the lock is what
	# keeps a manual step from racing the attack. Sub Heroes have their own
	# feedback path and are deliberately never counted here.
	var is_enemy_attacker: bool = is_instance_valid(result.attacker) and result.attacker is EnemyController
	if is_player_attacker:
		_active_player_attacks += 1
	if is_enemy_attacker:
		_begin_enemy_attack_presentation()
	await _play_attack(result)
	# §12 Life Steal and Stun: HP the player never sees restored reads as a bug, and a
	# turn an enemy silently loses needs a reason on screen.
	if result.lifesteal_heal > 0 and is_instance_valid(result.attacker):
		_play_heal(result.attacker, result.lifesteal_heal)
	if not result.applied_status_id.is_empty() and is_instance_valid(result.target):
		_play_status(result.target, result.applied_status_id, result.applied_status_turns)
	# The sequence ends with the attacker's recovery step still running; let it
	# settle so the attacker is back in place before the next beat (the hero's
	# swing before the enemy turn, the enemy's swing before the hero may walk on).
	await _wait(CombatPresentationConfig.RECOVERY * _speed_multiplier)
	if is_player_attacker:
		_active_player_attacks = maxi(_active_player_attacks - 1, 0)
		if _active_player_attacks == 0:
			player_attacks_idle.emit()
	if is_enemy_attacker:
		_finish_enemy_attack_presentation()


## Counts one enemy strike on screen; the FIRST one announces the lock so the host
## holds player movement, and boss multi-hits simply stack on top of it.
func _begin_enemy_attack_presentation() -> void:
	_active_enemy_attacks += 1
	if _active_enemy_attacks == 1:
		enemy_attack_presentation_changed.emit(true)
		_arm_enemy_attack_lock_timeout()


## Drops the enemy-strike lock and its counter unconditionally. The combat host
## calls this whenever the arena is rebuilt (the enemies whose swing was animating
## no longer exist), and the watchdog below calls it for a sequence whose animation
## never reports back — a strike must never strand the hero's movement.
func reset_enemy_attack_presentation() -> void:
	if _active_enemy_attacks == 0:
		return
	_active_enemy_attacks = 0
	enemy_attack_presentation_changed.emit(false)


func _finish_enemy_attack_presentation() -> void:
	_active_enemy_attacks = maxi(_active_enemy_attacks - 1, 0)
	if _active_enemy_attacks == 0:
		enemy_attack_presentation_changed.emit(false)


# ---------------------------------------------------------------------------
# Enemy-strike lock safety net
# ---------------------------------------------------------------------------


## Bounds the lock: an enemy strike whose animation never reports back (its
## attacker freed mid-swing, e.g. by a stage restart) must not strand the hero's
## movement. The turn manager bounds its own presentation wait the same way.
func _arm_enemy_attack_lock_timeout() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var watchdog: SceneTreeTimer = tree.create_timer(CombatPresentationConfig.ENEMY_ATTACK_LOCK_TIMEOUT)
	watchdog.timeout.connect(_on_enemy_attack_lock_timeout)


func _on_enemy_attack_lock_timeout() -> void:
	reset_enemy_attack_presentation()


func _play_attack(result: DamageResult) -> void:
	var attacker: Node = result.attacker
	var target: Node = result.target
	if not _is_presentable(attacker) or not _is_presentable(target):
		return
	var mult: float = _speed_multiplier
	var dir: Vector2 = (target as Node2D).global_position - (attacker as Node2D).global_position

	if result.is_refused:
		# §4: nothing was struck, so there is nothing to animate or to number. The
		# host reports the refusal as status text instead.
		return

	if result.is_miss:
		var dodge_token := _token_for(target)
		if dodge_token != null and not dodge_token.is_dying():
			dodge_token.play_dodge(dir)
		_spawn_number((target as Node2D).global_position, DamageNumber.Kind.DODGE, 0, _locale.translate("fx.dodge"))
		return

	# §16 A Magic Tome spell is cast from where the hero stands and flies to an enemy
	# anywhere on the grid. It must never use the weapon dash, which would fling the
	# sprite across the battlefield, so it takes the projectile path with its own VFX.
	var magic_skill := MagicTomeCatalog.get_skill(result.skill_id)
	var is_magic: bool = not magic_skill.skill_id.is_empty()
	var heavy: bool = result.skill_id == &"execution_strike"
	var is_projectile: bool = result.skill_id == &"arcane_bolt" or is_magic
	var is_player_attack: bool = attacker == _player
	var intensity: float = CombatPresentationConfig.PLAYER_INTENSITY if is_player_attack else 1.0
	var strong: bool = result.is_critical or heavy or is_player_attack
	var attacker_token := _token_for(attacker)
	var target_token := _token_for(target)

	# If the attacker just moved this action, let its walk finish first so the
	# sprite is seen stepping cell-by-cell; an immediate wind-up would cut the
	# move short and snap/fling it across the whole multi-cell jump.
	if attacker_token != null and attacker_token.is_moving():
		await attacker_token.move_finished
		if not is_instance_valid(attacker_token):
			return

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
			magic_skill.vfx_id if is_magic else &"arcane",
			mult
		)
		await _wait(CombatPresentationConfig.PROJECTILE_TRAVEL * mult)
	if not is_instance_valid(target):
		_recover_attacker(attacker_token if is_instance_valid(attacker_token) else null)
		return

	# 3) Impact: VFX, hit stop (token tween pause — never Engine.time_scale).
	var target_pos: Vector2 = (target as Node2D).global_position
	if is_magic:
		_spawn_vfx(magic_skill.vfx_id, target_pos, dir, strong, mult)
	elif is_projectile:
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


## Counts one death animation as an active presentation for the whole sequence,
## start delay included, and hands the animation to _run_death so every early exit
## still releases the counter.
func _play_death(actor: Node) -> void:
	_active_deaths += 1
	await _run_death(actor)
	_active_deaths = maxi(_active_deaths - 1, 0)


func _run_death(actor: Node) -> void:
	await _wait(CombatPresentationConfig.DEATH_DELAY * _speed_multiplier)
	if not is_instance_valid(actor):
		return
	# The Player is never collapse-hidden: PlayerController.handle_defeat()
	# presents its defeat as a greyed, still-standing hero, and the defeat
	# retreat quickly revives it onto the previous stage. Running play_death()
	# here would fade and hide the hero's sprite (even after that revive).
	if actor is PlayerController:
		return
	var token := _token_for(actor)
	if token == null or token.is_dying():
		return
	token.play_death()
	# Held until the collapse has finished (the token reports it even when it
	# leaves the tree mid-animation) so nothing rebuilds the arena over it.
	await token.death_finished


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
	# Same guard as attacks: don't wind up until the caster's walk has settled.
	if caster_token != null and caster_token.is_moving():
		await caster_token.move_finished
		if not is_instance_valid(caster_token):
			return
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
##
## Counted as an active presentation from the request, because the target can be
## the last enemy of a wave: the kill is already decided here while the projectile
## is still travelling.
func _play_sub_hero_feedback(result: DamageResult, target: Node) -> void:
	if result == null or result.is_miss or not _is_presentable(target):
		return
	_active_impact_feedback += 1
	await _run_sub_hero_feedback(result, target)
	_active_impact_feedback = maxi(_active_impact_feedback - 1, 0)


func _run_sub_hero_feedback(result: DamageResult, target: Node) -> void:
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


## Lifts a status label clear of the damage number spawned on the same hit.
const STATUS_LABEL_OFFSET := Vector2(0.0, -36.0)


## Floating label for a status a hit applied (the §12 Stun affix). Rides the neutral
## MISS kind so a status needs no new presentation tuning values.
func _play_status(unit: Node, status_id: StringName, turns: int) -> void:
	if not _is_presentable(unit):
		return
	var label: String = _locale.translate("fx.%s" % status_id)
	if turns > 1:
		label = "%s %d" % [label, turns]
	_spawn_number((unit as Node2D).global_position + STATUS_LABEL_OFFSET, DamageNumber.Kind.MISS, 0, label)


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
