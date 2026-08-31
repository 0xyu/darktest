extends PanelContainer

const SubHeroQualityResource = preload("res://scripts/sub_hero/sub_hero_quality.gd")

signal pressed

@onready var _portrait: TextureRect = $Margin/Content/PortraitBox/Portrait
@onready var _portrait_fallback: Label = $Margin/Content/PortraitBox/Fallback
@onready var _name_label: Label = $Margin/Content/Details/NameLabel
@onready var _quality_label: Label = $Margin/Content/Details/QualityLabel
@onready var _level_label: Label = $Margin/Content/Details/LevelLabel
@onready var _feedback_label: Label = $Margin/Content/Details/FeedbackLabel
@onready var _cooldown_bar: ProgressBar = $Margin/Content/Details/CooldownBar

var _bound_hero_id: StringName = &""
var _feedback_time_remaining: float = 0.0
var _cooldown_time_remaining: float = 0.0


func _ready() -> void:
	_configure_cooldown_bar()
	_show_empty()


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	if _feedback_time_remaining > 0.0:
		_feedback_time_remaining = maxf(_feedback_time_remaining - delta, 0.0)
		_feedback_label.modulate.a = clampf(_feedback_time_remaining / 0.8, 0.0, 1.0)
		if is_zero_approx(_feedback_time_remaining):
			_update_state_label()
	if _cooldown_time_remaining > 0.0:
		_cooldown_time_remaining = maxf(_cooldown_time_remaining - delta, 0.0)
		_cooldown_bar.value = _cooldown_time_remaining
		if is_zero_approx(_cooldown_time_remaining):
			_cooldown_bar.value = 0.0
			_update_state_label()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func set_slot(data: Resource, instance: Resource) -> void:
	if data == null or instance == null:
		_show_empty()
		return
	_bound_hero_id = StringName(str(data.get("id")))
	var display_name: String = str(data.get("display_name"))
	var quality: int = int(data.get("quality"))
	var level: int = maxi(int(instance.get("level")), 1)
	var attack_damage: int = maxi(int(data.get("attack_damage")), 1)
	var attack_interval: float = maxf(float(data.get("attack_interval")), 0.1)
	_name_label.text = display_name
	_quality_label.text = SubHeroQualityResource.get_display_name(quality).to_upper()
	_quality_label.modulate = SubHeroQualityResource.get_color(quality)
	_level_label.text = "LV %d  •  %d DMG  •  %.1fs" % [level, attack_damage, attack_interval]
	_feedback_label.text = "READY"
	_feedback_label.modulate = Color("9d93ae")
	_feedback_time_remaining = 0.0
	_reset_cooldown()
	var portrait_texture: Texture2D = data.get("portrait") as Texture2D
	_portrait.texture = portrait_texture
	_portrait.visible = portrait_texture != null
	_portrait_fallback.visible = portrait_texture == null
	_portrait_fallback.text = _get_initials(display_name)
	_portrait_fallback.modulate = SubHeroQualityResource.get_color(quality)
	_apply_frame_style(SubHeroQualityResource.get_color(quality), true)


func clear_slot() -> void:
	_show_empty()


func show_attack_feedback(damage: int) -> void:
	if _bound_hero_id.is_empty():
		return
	_feedback_label.text = "HIT  -%d" % maxi(damage, 0)
	_feedback_label.modulate = Color("f2c15e")
	_feedback_time_remaining = 0.8


func start_cooldown(duration: float) -> void:
	var safe_duration: float = maxf(duration, 0.1)
	_cooldown_time_remaining = safe_duration
	_cooldown_bar.max_value = safe_duration
	_cooldown_bar.value = safe_duration
	# Pre-started bars (combat start / re-sync) must flip a stale "READY" label
	# into CHARGING; at real attack time the hit text is showing and stays.
	if _feedback_time_remaining <= 0.0:
		_update_state_label()


func reset_cooldown() -> void:
	_reset_cooldown()


func get_bound_hero_id() -> StringName:
	return _bound_hero_id


func _show_empty() -> void:
	_bound_hero_id = &""
	_name_label.text = "EMPTY SLOT"
	_quality_label.text = "UNASSIGNED"
	_quality_label.modulate = Color("756b80")
	_level_label.text = "ASSIGN SUB HERO"
	_feedback_label.text = "WAITING"
	_feedback_label.modulate = Color("756b80")
	_portrait.texture = null
	_portrait.visible = false
	_portrait_fallback.visible = true
	_portrait_fallback.text = "+"
	_portrait_fallback.modulate = Color("756b80")
	_feedback_time_remaining = 0.0
	_reset_cooldown()
	_apply_frame_style(Color("49384a"), false)


func _configure_cooldown_bar() -> void:
	_cooldown_bar.min_value = 0.0
	_cooldown_bar.max_value = 1.0
	_cooldown_bar.value = 0.0
	_cooldown_bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color("211b2d")
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("d1a94e")
	_cooldown_bar.add_theme_stylebox_override("background", background)
	_cooldown_bar.add_theme_stylebox_override("fill", fill)


func _reset_cooldown() -> void:
	_cooldown_time_remaining = 0.0
	_cooldown_bar.max_value = 1.0
	_cooldown_bar.value = 0.0


## Derives the status text from the real cooldown so "READY" only appears once
## the countdown has actually reached zero. While charging, the label shows
## CHARGING instead of pretending the hero is ready to fire.
func _update_state_label() -> void:
	if _bound_hero_id.is_empty():
		return
	if _cooldown_time_remaining > 0.0:
		_feedback_label.text = "CHARGING"
		_feedback_label.modulate = Color("756b80")
	else:
		_feedback_label.text = "READY"
		_feedback_label.modulate = Color("9d93ae")


func _apply_frame_style(frame_color: Color, filled: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("151321") if filled else Color("100e18")
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = frame_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", style)


func _get_initials(display_name: String) -> String:
	var words := display_name.split(" ", false)
	if words.size() >= 2:
		return "%s%s" % [words[0].left(1), words[1].left(1)]
	return display_name.left(2).to_upper()
