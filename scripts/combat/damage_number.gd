class_name DamageNumber
extends Node2D

## Floating combat text spawned by the presentation layer. The kind drives
## color, size and default text; spawners may override the text with a
## localized string (MISS/DODGE/BLOCK/CRITICAL via GameLocale).
##
## Animation is one node-bound tween (dies with the node): pop-in scale,
## upward drift, late fade, then self-free.

enum Kind { NORMAL, CRITICAL, HEAL, POISON, BURN, BLEED, MISS, DODGE, BLOCK }

var kind: Kind = Kind.NORMAL
var amount: int = 0
var text: String = ""
var speed_multiplier: float = 1.0

var _animation_started: bool = false


func setup(number_kind: Kind, value: int = 0, custom_text: String = "", speed: float = 1.0) -> void:
	kind = number_kind
	amount = value
	text = custom_text
	speed_multiplier = maxf(speed, 0.05)
	z_index = 20
	scale = Vector2(0.5, 0.5)
	queue_redraw()
	if is_inside_tree():
		_start_animation()
	elif not _animation_started:
		tree_entered.connect(_start_animation, CONNECT_ONE_SHOT)


func _start_animation() -> void:
	if _animation_started:
		return
	_animation_started = true
	var lifetime: float = CombatPresentationConfig.NUMBER_LIFETIME * speed_multiplier
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, lifetime * 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", position.y - CombatPresentationConfig.NUMBER_RISE, lifetime) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.45).set_delay(lifetime * 0.55)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var display: String = text if not text.is_empty() else _default_text()
	var size: int = _kind_font_size()
	var text_origin := Vector2(-44.0, 0.0)
	# Outline first so the number stays readable over bright VFX at 720x1280.
	draw_string_outline(font, text_origin, display, HORIZONTAL_ALIGNMENT_CENTER, 88, size, 4, CombatPresentationConfig.NUMBER_OUTLINE_COLOR)
	draw_string(font, text_origin, display, HORIZONTAL_ALIGNMENT_CENTER, 88, size, _kind_color())


func _default_text() -> String:
	match kind:
		Kind.CRITICAL:
			return "%d!" % amount
		Kind.HEAL:
			return "+%d" % amount
		Kind.MISS:
			return "MISS"
		Kind.DODGE:
			return "DODGE"
		Kind.BLOCK:
			return "BLOCK"
		_:
			return str(amount)


func _kind_color() -> Color:
	match kind:
		Kind.CRITICAL:
			return CombatPresentationConfig.COLOR_CRIT
		Kind.HEAL:
			return CombatPresentationConfig.COLOR_HEAL
		Kind.POISON:
			return CombatPresentationConfig.COLOR_POISON
		Kind.BURN:
			return CombatPresentationConfig.COLOR_FIRE
		Kind.BLEED:
			return CombatPresentationConfig.COLOR_BLEED
		Kind.MISS, Kind.DODGE:
			return CombatPresentationConfig.COLOR_MISS
		Kind.BLOCK:
			return CombatPresentationConfig.COLOR_BLOCK
		_:
			return CombatPresentationConfig.COLOR_DAMAGE


func _kind_font_size() -> int:
	match kind:
		Kind.CRITICAL:
			return CombatPresentationConfig.NUMBER_FONT_SIZE_CRIT
		Kind.MISS, Kind.DODGE, Kind.BLOCK:
			return CombatPresentationConfig.NUMBER_FONT_SIZE - 2
		_:
			return CombatPresentationConfig.NUMBER_FONT_SIZE
