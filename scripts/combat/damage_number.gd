class_name DamageNumber
extends Node2D

var amount: int = 0
var is_critical: bool = false
var _time_remaining: float = 0.8


func setup(damage_amount: int, critical: bool) -> void:
	amount = damage_amount
	is_critical = critical
	z_index = 20
	queue_redraw()


func _process(delta: float) -> void:
	_time_remaining -= delta
	position.y -= 30.0 * delta
	modulate.a = clampf(_time_remaining / 0.8, 0.0, 1.0)
	if _time_remaining <= 0.0:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var color := Color("f1d277") if is_critical else Color("f1e6d0")
	var size: int = 24 if is_critical else 19
	var text := ("CRIT %d" % amount) if is_critical else str(amount)
	draw_string(font, Vector2(-34, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 68, size, color)
