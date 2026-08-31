class_name SubHeroAttackEffect
extends Node2D

## Lightweight, code-drawn projectile and impact effect for Sub Hero attacks.
## It lives on the HUD canvas so the projectile can travel from a slot to a
## world-space enemy without adding a permanent projectile node per hero.
signal finished

const TRAVEL_DURATION: float = 0.18
const IMPACT_DURATION: float = 0.22

var _origin: Vector2
var _destination: Vector2
var _accent_color: Color = Color("e8c465")
var _elapsed: float = 0.0
var _in_impact: bool = false


func setup(origin: Vector2, destination: Vector2, accent_color: Color = Color("e8c465")) -> void:
	_origin = origin
	_destination = destination
	_accent_color = accent_color
	position = origin
	z_index = 100
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if not _in_impact:
		var travel_ratio: float = clampf(_elapsed / TRAVEL_DURATION, 0.0, 1.0)
		position = _origin.lerp(_destination, ease(travel_ratio, 0.75))
		if travel_ratio >= 1.0:
			_in_impact = true
			_elapsed = 0.0
		queue_redraw()
		return

	position = _destination
	if _elapsed >= IMPACT_DURATION:
		finished.emit()
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	if not _in_impact:
		var direction := (_destination - _origin).normalized()
		var trail_start := -direction * 14.0
		draw_line(trail_start, Vector2.ZERO, Color(_accent_color, 0.35), 3.0, true)
		draw_circle(Vector2.ZERO, 5.0, _accent_color)
		draw_circle(Vector2.ZERO, 9.0, Color(_accent_color, 0.20), false, 2.0)
		return

	var impact_ratio: float = clampf(_elapsed / IMPACT_DURATION, 0.0, 1.0)
	var alpha: float = 1.0 - impact_ratio
	var radius: float = lerpf(5.0, 24.0, impact_ratio)
	draw_circle(Vector2.ZERO, radius, Color(_accent_color, alpha * 0.18), false, 3.0)
	draw_arc(Vector2.ZERO, radius * 0.65, 0.0, TAU, 16, Color(_accent_color, alpha), 2.0)
	draw_line(Vector2(-radius, 0.0), Vector2(radius, 0.0), Color(_accent_color, alpha * 0.8), 2.0, true)
	draw_line(Vector2(0.0, -radius), Vector2(0.0, radius), Color(_accent_color, alpha * 0.8), 2.0, true)
