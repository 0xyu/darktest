class_name CharacterToken
extends Node2D

## Static character token: one piece of art plus a ground shadow. All motion
## comes from transient local `position` offsets that are always tweened back
## to ZERO. Gameplay keeps owning the parent unit's global_position and
## grid_position; this node never writes gameplay state.
##
## Safety contract:
## - Every tween is created with create_tween() so it dies with the node.
## - `motion_phase_finished` is emitted at the end of each awaitable phase,
##   from snap() when a running phase is cut short, and from _exit_tree() as a
##   last resort, so presentation coroutines can never hang.
## - process_mode is ALWAYS so the death animation still runs after an enemy
##   sets itself to PROCESS_MODE_DISABLED.

enum HitVariant { NORMAL, CRITICAL, HEAVY, MISS, DODGE, BLOCK, DEATH }

signal motion_phase_finished
signal move_finished
signal death_finished

const RED_FLASH_TINT: Color = Color(1.0, 0.32, 0.28)
const SHADOW_COLOR: Color = Color("08070c", 0.45)

var speed_multiplier: float = 1.0

var _rect: Rect2 = Rect2(-24.0, -27.0, 48.0, 48.0)
var _shadow_scale: float = 1.0
var _dying: bool = false
var _motion_tween: Tween = null
## Chained per-cell walk state. Gameplay may teleport the unit across several
## grid cells within one decision (AUTO burst, enemy multi-cell chase); those
## steps are queued and replayed one cell at a time so the token visibly walks
## the grid instead of gliding over the whole path in a single leap.
var _move_active: bool = false
var _pending_steps: Array[Vector2] = []
var _pending_durations: Array[float] = []
var _step_to: Vector2 = Vector2.ZERO
var _body: Node2D
var _avatar: TokenDrawer
var _flash: TokenDrawer


## Minimal code-drawn sprite holder used for both the avatar and the additive
## flash overlay. Draws a generic placeholder body when no texture is set.
class TokenDrawer:
	extends Node2D

	var texture: Texture2D = null
	var rect: Rect2 = Rect2()

	func _draw() -> void:
		if texture != null:
			draw_texture_rect(texture, rect, false)
			return
		draw_circle(Vector2.ZERO, 18.0, Color("9d5267"))
		draw_circle(Vector2(0, -5), 7.0, Color("e4c5a1"))
		draw_line(Vector2(-9, 7), Vector2(9, 7), Color("4a1d2e"), 4.0)


func _init() -> void:
	_body = Node2D.new()
	_body.name = &"Body"
	add_child(_body)
	_avatar = TokenDrawer.new()
	_avatar.name = &"Avatar"
	_body.add_child(_avatar)
	_flash = TokenDrawer.new()
	_flash.name = &"Flash"
	var flash_material := CanvasItemMaterial.new()
	flash_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash.material = flash_material
	_flash.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_body.add_child(_flash)


func _ready() -> void:
	# Parent enemies disable their process mode on defeat; the death animation
	# must survive that.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	_kill_motion(false)
	motion_phase_finished.emit()
	if _dying:
		death_finished.emit()


## Assigns the static art. `nearest` keeps pixel-art atlas cells crisp;
## `texture == null` falls back to a generic placeholder body.
func setup(texture: Texture2D, rect: Rect2, nearest: bool) -> void:
	_rect = rect
	_avatar.texture = texture
	_avatar.rect = rect
	_flash.texture = texture
	_flash.rect = rect
	if nearest:
		_avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		_avatar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_flash.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_avatar.queue_redraw()
	_flash.queue_redraw()
	queue_redraw()


## Visual-only movement: gameplay has already teleported the unit to the new
## cell, so the token backs up by `offset` (old - new) and walks the one grid
## cell back, with a small hop and shadow response. Consecutive calls issued
## within one decision (AUTO burst, enemy multi-cell chase) are chained: each
## step queues the freshly reached cell and is replayed one cell at a time, so
## the token walks the grid instead of leaping across all cells at once.
func play_move(offset: Vector2, _cells: int, fast: bool) -> void:
	if _dying or offset == Vector2.ZERO:
		return
	var unit := get_parent() as Node2D
	if unit == null or not is_instance_valid(unit):
		return
	if _move_active:
		# Gameplay advanced again before the previous step settled: queue the
		# freshly reached cell (one contiguous cell after the last target).
		var reached: Vector2 = unit.global_position
		var last: Vector2 = _step_to if _pending_steps.is_empty() else (_pending_steps.back() as Vector2)
		if reached != last:
			_pending_steps.append(reached)
			_pending_durations.append(_move_step_duration(fast))
		return
	_start_motion()
	_move_active = true
	_pending_steps.clear()
	_pending_durations.clear()
	# The unit already sits at the destination; back the visual up by `offset`
	# (old cell) so it walks one cell to the reached position.
	var reached: Vector2 = unit.global_position
	_begin_move_step(reached + offset, reached, _move_step_duration(fast))


## Hard reset of the transient offset (teleports, portrait-grid relayout).
func snap() -> void:
	if _dying:
		# The death presentation owns the visuals until it finishes.
		return
	_kill_motion(_is_motion_running())
	position = Vector2.ZERO
	_body.position = Vector2.ZERO
	_shadow_scale = 1.0
	queue_redraw()


func wind_up(direction: Vector2, heavy: bool, intensity: float = 1.0) -> void:
	_start_motion()
	var dir: Vector2 = _safe_direction(direction)
	var back_scale: float = CombatPresentationConfig.HEAVY_ANTICIPATION_SCALE if heavy else 1.0
	var target_offset: Vector2 = -dir * CombatPresentationConfig.ANTICIPATION_OFFSET * back_scale * intensity
	_motion_tween = create_tween()
	_motion_tween.tween_property(self, "position", target_offset, CombatPresentationConfig.ANTICIPATION * speed_multiplier) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_callback(motion_phase_finished.emit)


func dash(direction: Vector2, heavy: bool, intensity: float = 1.0) -> void:
	_start_motion()
	var dir: Vector2 = _safe_direction(direction)
	var lunge: float = CombatPresentationConfig.HEAVY_LUNGE_DISTANCE if heavy else CombatPresentationConfig.LUNGE_DISTANCE
	var duration: float = CombatPresentationConfig.DASH * speed_multiplier * (1.15 if heavy else 1.0)
	_motion_tween = create_tween()
	_motion_tween.tween_property(self, "position", dir * lunge * intensity, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_motion_tween.tween_callback(motion_phase_finished.emit)


func recover() -> void:
	_start_motion()
	_motion_tween = create_tween()
	_motion_tween.tween_property(self, "position", Vector2.ZERO, CombatPresentationConfig.RECOVERY * speed_multiplier) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_callback(motion_phase_finished.emit)


## Non-blocking flash + knockback + vertical shake that always decays to ZERO.
## MISS/DODGE variants are routed to play_dodge(); DEATH to play_death().
func play_hit_reaction(variant: HitVariant, direction: Vector2) -> void:
	if variant == HitVariant.DEATH:
		play_death()
		return
	if variant == HitVariant.MISS or variant == HitVariant.DODGE:
		play_dodge(direction)
		return
	var dir: Vector2 = _safe_direction(direction)
	var knockback: float = CombatPresentationConfig.KNOCKBACK
	var tint: Color = RED_FLASH_TINT
	match variant:
		HitVariant.CRITICAL:
			knockback = CombatPresentationConfig.CRIT_KNOCKBACK
		HitVariant.HEAVY:
			knockback = CombatPresentationConfig.HEAVY_KNOCKBACK
		HitVariant.BLOCK:
			knockback *= 0.5
			tint = CombatPresentationConfig.COLOR_BLOCK
		_:
			pass
	_play_flash(tint)
	_start_motion()
	var duration: float = maxf(
		CombatPresentationConfig.REACTION_SHAKE,
		CombatPresentationConfig.WHITE_FLASH + CombatPresentationConfig.FLASH
	) * speed_multiplier
	_motion_tween = create_tween()
	_motion_tween.tween_method(
		_apply_reaction_frame.bind(dir * knockback, CombatPresentationConfig.REACTION_SHAKE_AMPLITUDE),
		0.0, 1.0, duration
	)
	_motion_tween.tween_callback(_finish_reaction)


## Small sideways hop with no flash, used for MISS/DODGE feedback.
func play_dodge(direction: Vector2) -> void:
	_start_motion()
	var dir: Vector2 = _safe_direction(direction)
	var side := Vector2(-dir.y, dir.x)
	if side.x < 0.0:
		side = -side
	var dodge_offset: Vector2 = side * 10.0
	_motion_tween = create_tween()
	_motion_tween.tween_method(_apply_dodge_frame.bind(dodge_offset), 0.0, 1.0, 0.30 * speed_multiplier) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion_tween.tween_callback(_finish_reaction)


## Collapse: shrink, tilt, fade out, then hide. Emits death_finished once the
## token is invisible; reset_visuals() restores it (retry/revive/dev tests).
func play_death() -> void:
	if _dying:
		return
	_dying = true
	_start_motion()
	position = Vector2.ZERO
	_body.position = Vector2.ZERO
	var duration: float = CombatPresentationConfig.DEATH_DURATION * speed_multiplier
	_motion_tween = create_tween().set_parallel(true)
	_motion_tween.tween_property(self, "scale", Vector2(0.6, 0.6), duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_motion_tween.tween_property(self, "rotation", 0.35, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_motion_tween.tween_property(self, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	_motion_tween.chain().tween_callback(_finish_death)


func is_dying() -> bool:
	return _dying


## True while a (possibly multi-cell) walk is still animating or queued.
func is_moving() -> bool:
	return _move_active


## Full visual restore (revive after retry, dev-panel death test, cleanup).
func reset_visuals() -> void:
	_kill_motion(_is_motion_running())
	_dying = false
	position = Vector2.ZERO
	_body.position = Vector2.ZERO
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color.WHITE
	_shadow_scale = 1.0
	visible = true
	_flash.modulate = Color(1.0, 1.0, 1.0, 0.0)
	queue_redraw()


## Hit stop without Engine.time_scale: pauses the active motion tween for
## `duration` seconds, then resumes it. UI and input keep running normally.
func freeze(duration: float) -> void:
	if duration <= 0.0:
		return
	if _motion_tween == null or not _motion_tween.is_valid() or not _motion_tween.is_running():
		return
	_motion_tween.pause()
	var tree := get_tree()
	if tree == null:
		_motion_tween.play()
		return
	var timer: SceneTreeTimer = tree.create_timer(duration, true, false, false)
	timer.timeout.connect(_unfreeze, CONNECT_ONE_SHOT)


func _unfreeze() -> void:
	# Godot 4 Tween resumes via play(); pause()/play() never restart a tween.
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.play()


func _draw() -> void:
	# Ground shadow flattened onto the floor plane at the avatar's feet.
	var foot_y: float = _rect.end.y
	var radius: float = maxf(_rect.size.x * 0.42, 6.0) * _shadow_scale
	draw_set_transform(Vector2(0.0, foot_y), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, radius, SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _play_flash(tint: Color) -> void:
	# White spike, then decay through the tint color. Additive overlay only;
	# if blending is unavailable the worst case is no visible flash.
	_flash.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var flash_tween := create_tween()
	flash_tween.tween_property(_flash, "modulate:a", 0.9, CombatPresentationConfig.WHITE_FLASH * speed_multiplier)
	flash_tween.tween_property(_flash, "modulate", Color(tint.r, tint.g, tint.b, 0.0), CombatPresentationConfig.FLASH * speed_multiplier)


func _begin_move_step(from_world: Vector2, to_world: Vector2, duration: float) -> void:
	_step_to = to_world
	var unit := get_parent() as Node2D
	if unit == null or not is_instance_valid(unit):
		_move_active = false
		return
	position = from_world - unit.global_position
	_body.position = Vector2.ZERO
	_shadow_scale = 1.0
	queue_redraw()
	_motion_tween = create_tween()
	_motion_tween.tween_method(_apply_move_step.bind(from_world, to_world), 0.0, 1.0, duration)
	_motion_tween.tween_callback(_finish_move_step)


func _move_step_duration(fast: bool) -> float:
	var per_cell: float = CombatPresentationConfig.MOVE_DURATION_PER_CELL_FAST if fast else CombatPresentationConfig.MOVE_DURATION_PER_CELL
	return maxf(per_cell * speed_multiplier, 0.03)


func _apply_move_step(ratio: float, from_world: Vector2, to_world: Vector2) -> void:
	# The parent may already sit several cells ahead (queued burst); render each
	# frame at the interpolated world position by offsetting from the parent.
	var unit := get_parent() as Node2D
	var target: Vector2 = from_world.lerp(to_world, ratio)
	if unit != null and is_instance_valid(unit):
		position = target - unit.global_position
	else:
		position = target - to_world
	var air: float = sin(clampf(ratio / 0.85, 0.0, 1.0) * PI)
	_body.position = Vector2(0.0, -air * CombatPresentationConfig.MOVE_HOP)
	if ratio < 0.75:
		_shadow_scale = lerpf(1.0, 0.90, sin(ratio / 0.75 * PI))
	elif ratio < 0.90:
		_shadow_scale = lerpf(0.90, 1.05, (ratio - 0.75) / 0.15)
	else:
		_shadow_scale = lerpf(1.05, 1.0, (ratio - 0.90) / 0.10)
	queue_redraw()


func _finish_move_step() -> void:
	if not _pending_steps.is_empty():
		var next_to: Vector2 = _pending_steps.pop_front()
		var next_duration: float = _pending_durations.pop_front()
		_begin_move_step(_step_to, next_to, next_duration)
		return
	_move_active = false
	_step_to = Vector2.ZERO
	position = Vector2.ZERO
	_body.position = Vector2.ZERO
	_shadow_scale = 1.0
	queue_redraw()
	motion_phase_finished.emit()
	move_finished.emit()


func _apply_reaction_frame(ratio: float, knock: Vector2, amplitude: float) -> void:
	var decay: float = 1.0 - ratio
	position = knock * decay * decay
	_body.position = Vector2(0.0, -absf(sin(ratio * TAU * 2.0)) * amplitude * decay)


func _apply_dodge_frame(ratio: float, offset: Vector2) -> void:
	var arc: float = sin(ratio * PI)
	position = offset * arc
	_body.position = Vector2(0.0, -6.0 * arc)


func _finish_reaction() -> void:
	position = Vector2.ZERO
	_body.position = Vector2.ZERO
	motion_phase_finished.emit()


func _finish_death() -> void:
	visible = false
	death_finished.emit()


func _start_motion() -> void:
	_kill_motion(_is_motion_running())


func _is_motion_running() -> bool:
	return _motion_tween != null and _motion_tween.is_valid() and _motion_tween.is_running()


## Kills the active motion tween. `emit_finished` releases any coroutine that
## was awaiting motion_phase_finished for the interrupted phase.
func _kill_motion(emit_finished: bool) -> void:
	if _move_active:
		# A walk (possibly with queued steps) is interrupted: drop the remaining
		# steps so it never glides to stale targets. The offset is left as-is —
		# the following phase (snap, reset, hit reaction, ...) repositions it,
		# so the sprite is not yanked onto the destination mid-step.
		_move_active = false
		_pending_steps.clear()
		_pending_durations.clear()
		_step_to = Vector2.ZERO
		move_finished.emit()
	var old_tween: Tween = _motion_tween
	_motion_tween = null
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	if emit_finished:
		motion_phase_finished.emit()


func _safe_direction(direction: Vector2) -> Vector2:
	if direction.length_squared() < 0.000001:
		return Vector2.DOWN
	return direction.normalized()
