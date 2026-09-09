class_name CombatVFX
extends Node2D

## Data-driven procedural combat VFX (SubHeroAttackEffect-style code drawing).
## One node per effect; a StringName category selects the drawing routine, so
## effects never branch on enemy identity and need no textures.
##
## Performance rules: all randomness is pre-seeded in setup() (never in
## _draw()), lifetimes are short (0.08-0.25 s scaled by speed) and every
## instance frees itself. Dark-gothic palette from CombatPresentationConfig.

const MAX_PARTICLES: int = 10
const ACCENT_GOLD: Color = Color("e8c465")

var vfx_id: StringName = &"impact"
var direction: Vector2 = Vector2.DOWN
var strong: bool = false
var speed_multiplier: float = 1.0

var _elapsed: float = 0.0
var _lifetime: float = CombatPresentationConfig.IMPACT_LIFETIME
var _is_projectile: bool = false
var _origin: Vector2 = Vector2.ZERO
var _destination: Vector2 = Vector2.ZERO
var _impact_id: StringName = &"impact"

# Pre-seeded jitter (setup only, never per frame).
var _jitter_x := PackedFloat32Array()
var _jitter_y := PackedFloat32Array()
var _jitter_phase := PackedFloat32Array()


## Instant effect at this node's position. `dir` orients slashes/bolts;
## `is_strong` scales radius/line width for crits, heavies and the player.
func setup(id: StringName, dir: Vector2, is_strong: bool, speed: float) -> void:
	vfx_id = id
	direction = _safe_direction(dir)
	strong = is_strong
	speed_multiplier = maxf(speed, 0.05)
	z_index = 15
	_lifetime = _base_lifetime(id) * speed_multiplier
	_seed_random()
	queue_redraw()


## Travels from `from` to `to` (global positions) over PROJECTILE_TRAVEL,
## then plays the `impact_id` effect at the destination and frees itself.
func setup_projectile(from: Vector2, to: Vector2, impact_id: StringName, speed: float) -> void:
	_is_projectile = true
	_origin = from
	_destination = to
	_impact_id = impact_id
	vfx_id = impact_id
	direction = _safe_direction(to - from)
	speed_multiplier = maxf(speed, 0.05)
	z_index = 15
	_lifetime = (CombatPresentationConfig.PROJECTILE_TRAVEL + _base_lifetime(impact_id)) * speed_multiplier
	global_position = from
	_seed_random()
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if _is_projectile:
		var travel: float = CombatPresentationConfig.PROJECTILE_TRAVEL * speed_multiplier
		if _elapsed < travel:
			var ratio: float = clampf(_elapsed / maxf(travel, 0.0001), 0.0, 1.0)
			global_position = _origin.lerp(_destination, ease(ratio, 0.75))
		else:
			global_position = _destination
	if _elapsed >= _lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _is_projectile:
		var travel: float = CombatPresentationConfig.PROJECTILE_TRAVEL * speed_multiplier
		if _elapsed < travel:
			_draw_projectile_flight()
			return
		var impact_t: float = clampf((_elapsed - travel) / maxf(_lifetime - travel, 0.0001), 0.0, 1.0)
		_draw_category(_impact_id, impact_t)
		return
	_draw_category(vfx_id, clampf(_elapsed / maxf(_lifetime, 0.0001), 0.0, 1.0))


func _draw_projectile_flight() -> void:
	var color: Color = _category_color(_impact_id)
	var trail: Vector2 = -direction * 16.0
	var core_radius: float = 6.0 if strong else 4.5
	draw_line(trail, Vector2.ZERO, Color(color, 0.35), 3.0, true)
	draw_circle(Vector2.ZERO, core_radius, color)
	draw_circle(Vector2.ZERO, core_radius + 4.0, Color(color, 0.20), false, 2.0)


func _draw_category(id: StringName, t: float) -> void:
	var alpha: float = 1.0 - t
	match id:
		&"slash":
			_draw_slash(t, alpha, false)
		&"heavy_slash":
			_draw_slash(t, alpha, true)
		&"impact":
			_draw_impact(t, alpha)
		&"fire":
			_draw_fire(t, alpha)
		&"ice":
			_draw_ice(t, alpha)
		&"lightning":
			_draw_lightning(t, alpha)
		&"poison":
			_draw_poison(t, alpha)
		&"holy":
			_draw_holy(t, alpha)
		&"dark":
			_draw_dark(t, alpha)
		&"arcane":
			_draw_arcane(t, alpha)
		&"heal":
			_draw_heal(t, alpha)
		&"buff":
			_draw_arrow(t, alpha, true)
		&"debuff":
			_draw_arrow(t, alpha, false)
		&"area":
			_draw_area(t, alpha)
		_:
			_draw_impact(t, alpha)


## Metallic arc sweeping across the attack direction.
func _draw_slash(t: float, alpha: float, heavy: bool) -> void:
	var angle: float = direction.angle()
	var radius: float = (38.0 if strong else 30.0) if heavy else (30.0 if strong else 24.0)
	var sweep: float = lerpf(0.25, 1.5, t)
	var width: float = (3.5 if strong else 2.5) if not heavy else 4.5
	draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
	draw_arc(Vector2.ZERO, radius, -sweep, sweep, 14, Color("d8dde6", alpha * 0.9), width)
	if heavy:
		draw_arc(Vector2.ZERO, radius * 0.9, -sweep - 0.5, sweep - 0.5, 14, Color("b94d63", alpha * 0.7), width * 0.8)
	draw_arc(Vector2.ZERO, radius * 0.8, -sweep * 0.8, sweep * 0.8, 12, Color("8d93a3", alpha * 0.45), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Expanding ring plus cross lines (SubHeroAttackEffect impact language).
func _draw_impact(t: float, alpha: float) -> void:
	var radius: float = lerpf(5.0, 30.0 if strong else 24.0, t)
	draw_circle(Vector2.ZERO, radius, Color("8d2438", alpha * 0.18), false, 3.0)
	draw_arc(Vector2.ZERO, radius * 0.65, 0.0, TAU, 16, Color(ACCENT_GOLD, alpha), 2.0)
	draw_line(Vector2(-radius, 0.0), Vector2(radius, 0.0), Color("b94d63", alpha * 0.8), 2.0, true)
	draw_line(Vector2(0.0, -radius), Vector2(0.0, radius), Color("b94d63", alpha * 0.8), 2.0, true)


## Rising sparks over an orange glow.
func _draw_fire(t: float, alpha: float) -> void:
	var color: Color = CombatPresentationConfig.COLOR_FIRE
	draw_circle(Vector2.ZERO, lerpf(6.0, 16.0, t), Color(color, alpha * 0.22))
	for i in MAX_PARTICLES:
		var px: float = _jitter_x[i] * 14.0
		var py: float = lerpf(6.0, -14.0 - _jitter_y[i] * 18.0, t)
		draw_circle(Vector2(px, py), maxf(2.2 - t * 1.5, 0.4), Color(color, alpha * (0.45 + _jitter_phase[i] * 0.5)))


## Pale-blue shards radiating outward with a frost ring.
func _draw_ice(t: float, alpha: float) -> void:
	var color: Color = CombatPresentationConfig.COLOR_ICE
	for i in MAX_PARTICLES:
		var ang: float = _jitter_phase[i] * TAU
		var radial := Vector2(cos(ang), sin(ang))
		var dist: float = lerpf(4.0, 18.0, t) * (0.6 + _jitter_x[i] * 0.2 + 0.2)
		draw_line(radial * dist, radial * (dist + 4.5), Color(color, alpha), 2.0)
	draw_arc(Vector2.ZERO, lerpf(4.0, 14.0, t), 0.0, TAU, 12, Color(color, alpha * 0.5), 1.5)


## Fixed zigzag bolt from above (jitter seeded once, so the shape is stable).
func _draw_lightning(t: float, alpha: float) -> void:
	var color: Color = CombatPresentationConfig.COLOR_LIGHTNING
	var points := PackedVector2Array()
	points.append(Vector2(_jitter_x[0] * 6.0, -48.0))
	var segments: int = 5
	for i in range(1, segments + 1):
		var frac: float = float(i) / float(segments)
		points.append(Vector2(_jitter_x[i] * 10.0, lerpf(-48.0, 8.0, frac)))
	draw_polyline(points, Color(color, alpha), 2.5)
	draw_polyline(points, Color(1.0, 1.0, 1.0, alpha * 0.55), 1.0)
	if t < 0.5:
		draw_circle(Vector2.ZERO, 11.0, Color(color, (0.5 - t) * 0.6))


## Green bubbles drifting up.
func _draw_poison(t: float, alpha: float) -> void:
	var color: Color = CombatPresentationConfig.COLOR_POISON
	for i in MAX_PARTICLES:
		var px: float = _jitter_x[i] * 12.0
		var py: float = lerpf(8.0, -16.0 - _jitter_y[i] * 10.0, t)
		draw_circle(Vector2(px, py), 1.4 + _jitter_phase[i] * 2.0, Color(color, alpha * 0.65))


## Golden ring with a rising beam.
func _draw_holy(t: float, alpha: float) -> void:
	var color: Color = CombatPresentationConfig.COLOR_HOLY
	draw_arc(Vector2.ZERO, lerpf(10.0, 22.0, t), 0.0, TAU, 20, Color(color, alpha * 0.9), 2.5)
	draw_circle(Vector2.ZERO, lerpf(4.0, 12.0, t), Color(color, alpha * 0.22))
	draw_line(Vector2(0.0, 0.0), Vector2(0.0, lerpf(-12.0, -34.0, t)), Color(color, alpha * 0.5), 3.0)


## Purple ring imploding toward a dark core.
func _draw_dark(t: float, alpha: float) -> void:
	var color: Color = CombatPresentationConfig.COLOR_DARK
	var radius: float = lerpf(24.0, 6.0, t)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 16, Color(color, alpha * 0.9), 2.5)
	draw_circle(Vector2.ZERO, radius * 0.5, Color("1a0f24", alpha * 0.5))


## Small purple burst with sparks (arcane projectile impact).
func _draw_arcane(t: float, alpha: float) -> void:
	var color: Color = CombatPresentationConfig.COLOR_DARK
	draw_arc(Vector2.ZERO, lerpf(4.0, 16.0, t), 0.0, TAU, 14, Color(color, alpha), 2.0)
	for i in MAX_PARTICLES / 2:
		var ang: float = _jitter_phase[i] * TAU
		var radial := Vector2(cos(ang), sin(ang))
		draw_line(radial * lerpf(4.0, 12.0, t), radial * lerpf(8.0, 20.0, t), Color(color, alpha * 0.7), 1.5)


## Green plus sign rising inside a soft ring.
func _draw_heal(t: float, alpha: float) -> void:
	var color: Color = CombatPresentationConfig.COLOR_HEAL
	var rise: float = -18.0 * t
	draw_line(Vector2(-6.0, rise), Vector2(6.0, rise), Color(color, alpha * 0.9), 3.0)
	draw_line(Vector2(0.0, rise - 6.0), Vector2(0.0, rise + 6.0), Color(color, alpha * 0.9), 3.0)
	draw_arc(Vector2.ZERO, lerpf(8.0, 20.0, t), 0.0, TAU, 16, Color(color, alpha * 0.35), 2.0)


## Up (buff, gold) or down (debuff, violet) chevron arrow.
func _draw_arrow(t: float, alpha: float, upward: bool) -> void:
	var color: Color = ACCENT_GOLD if upward else CombatPresentationConfig.COLOR_DARK
	var drift: float = (-16.0 if upward else 16.0) * t
	var tip := Vector2(0.0, drift - (8.0 if upward else -8.0))
	var base := Vector2(0.0, drift + (8.0 if upward else -8.0))
	draw_line(base, tip, Color(color, alpha), 3.0)
	var head_dir: float = -1.0 if upward else 1.0
	draw_line(tip, tip + Vector2(-5.0, head_dir * 6.0), Color(color, alpha), 2.5)
	draw_line(tip, tip + Vector2(5.0, head_dir * 6.0), Color(color, alpha), 2.5)


## Ground shockwave ring, flattened onto the floor plane.
func _draw_area(t: float, alpha: float) -> void:
	var radius: float = lerpf(12.0, 56.0 if strong else 44.0, t)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(ACCENT_GOLD, alpha * 0.6), 2.5)
	draw_arc(Vector2.ZERO, radius * 0.7, 0.0, TAU, 20, Color("b94d63", alpha * 0.4), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _base_lifetime(id: StringName) -> float:
	match id:
		&"lightning":
			return 0.12
		&"impact", &"slash":
			return 0.16
		&"heavy_slash":
			return 0.20
		&"heal", &"buff", &"debuff", &"area":
			return 0.25
		_:
			return CombatPresentationConfig.IMPACT_LIFETIME


func _category_color(id: StringName) -> Color:
	match id:
		&"fire":
			return CombatPresentationConfig.COLOR_FIRE
		&"ice":
			return CombatPresentationConfig.COLOR_ICE
		&"lightning":
			return CombatPresentationConfig.COLOR_LIGHTNING
		&"poison":
			return CombatPresentationConfig.COLOR_POISON
		&"holy":
			return CombatPresentationConfig.COLOR_HOLY
		&"dark", &"arcane":
			return CombatPresentationConfig.COLOR_DARK
		&"heal":
			return CombatPresentationConfig.COLOR_HEAL
		_:
			return ACCENT_GOLD


func _seed_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_jitter_x.resize(MAX_PARTICLES)
	_jitter_y.resize(MAX_PARTICLES)
	_jitter_phase.resize(MAX_PARTICLES)
	for i in MAX_PARTICLES:
		_jitter_x[i] = rng.randf_range(-1.0, 1.0)
		_jitter_y[i] = rng.randf()
		_jitter_phase[i] = rng.randf()


func _safe_direction(dir: Vector2) -> Vector2:
	if dir.length_squared() < 0.000001:
		return Vector2.DOWN
	return dir.normalized()
