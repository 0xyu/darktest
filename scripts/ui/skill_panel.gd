class_name SkillPanel
extends Control

signal panel_closed

const COLOR_GOLD := Color("e8c465")
const COLOR_GOLD_BRIGHT := Color("f4d28b")
const COLOR_TEXT := Color("d8cfdf")
const COLOR_MUTED := Color("8f879d")
const COLOR_GREEN := Color("82d49b")
const COLOR_RED := Color("d46a78")
const COLOR_PANEL := Color("151321")
const COLOR_BORDER := Color("49384a")

@onready var _points_label: Label = %SkillPointsLabel
@onready var _skill_list: VBoxContainer = %SkillList
@onready var _close_button: Button = %CloseButton

var _player: PlayerController
var _connected_progression: PlayerProgression


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(hide_panel)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_rebuild()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide_panel()
		get_viewport().set_input_as_handled()


func set_player(player: PlayerController) -> void:
	if _connected_progression != null:
		if _connected_progression.skill_points_changed.is_connected(_on_skill_progression_changed):
			_connected_progression.skill_points_changed.disconnect(_on_skill_progression_changed)
		if _connected_progression.skill_level_changed.is_connected(_on_skill_level_changed):
			_connected_progression.skill_level_changed.disconnect(_on_skill_level_changed)
	_player = player
	_connected_progression = _player.player_progression if _player != null else null
	if _connected_progression != null:
		_connected_progression.skill_points_changed.connect(_on_skill_progression_changed)
		_connected_progression.skill_level_changed.connect(_on_skill_level_changed)
	_rebuild()


func show_panel() -> void:
	visible = true
	_rebuild()
	_close_button.grab_focus()


func hide_panel() -> void:
	visible = false
	panel_closed.emit()


func toggle_panel() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()


func _on_viewport_size_changed() -> void:
	_rebuild()


func _on_skill_progression_changed(_current_skill_points: int) -> void:
	_rebuild()


func _on_skill_level_changed(_skill_id: StringName, _new_level: int) -> void:
	_rebuild()


func _rebuild() -> void:
	if _points_label == null or _skill_list == null:
		return
	var points: int = _player.get_skill_points() if _player != null else 0
	_points_label.text = "SKILL POINTS  %d" % points
	for child in _skill_list.get_children():
		child.free()
	if _player == null:
		return
	for skill in SkillCatalog.get_all():
		_skill_list.add_child(_create_skill_row(skill))


func _create_skill_row(skill: SkillDefinition) -> PanelContainer:
	var level: int = _player.get_skill_level(skill.skill_id)
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 88)
	row.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL, COLOR_BORDER, 1))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	row.add_child(margin)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	content.add_child(info)

	var name_label := Label.new()
	name_label.text = "%s   LEVEL %d / %d" % [skill.display_name, level, SkillDefinition.MAX_LEVEL]
	name_label.add_theme_color_override("font_color", COLOR_GOLD_BRIGHT if level > 0 else COLOR_TEXT)
	name_label.add_theme_font_size_override("font_size", 14)
	info.add_child(name_label)

	var description_label := Label.new()
	description_label.text = skill.description
	description_label.add_theme_color_override("font_color", COLOR_MUTED)
	description_label.add_theme_font_size_override("font_size", 10)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(description_label)

	var progression_label := Label.new()
	progression_label.text = _get_progression_text(skill, level)
	progression_label.add_theme_color_override("font_color", COLOR_GREEN if level > 0 else COLOR_MUTED)
	progression_label.add_theme_font_size_override("font_size", 10)
	info.add_child(progression_label)

	var upgrade_button := Button.new()
	upgrade_button.custom_minimum_size = Vector2(112, 52)
	upgrade_button.add_theme_font_size_override("font_size", 12)
	upgrade_button.add_theme_color_override("font_color", COLOR_GOLD_BRIGHT)
	upgrade_button.add_theme_color_override("font_disabled_color", COLOR_MUTED)
	upgrade_button.add_theme_stylebox_override("normal", _make_style(Color("211a2c"), Color("6c5331"), 1))
	upgrade_button.add_theme_stylebox_override("hover", _make_style(Color("30243b"), COLOR_GOLD, 2))
	upgrade_button.add_theme_stylebox_override("pressed", _make_style(Color("443022"), COLOR_GOLD_BRIGHT, 2))
	upgrade_button.text = "MAXED" if level >= SkillDefinition.MAX_LEVEL else ("LEARN" if level == 0 else "UPGRADE")
	upgrade_button.disabled = level >= SkillDefinition.MAX_LEVEL or _player.get_skill_points() <= 0
	upgrade_button.pressed.connect(_on_upgrade_pressed.bind(skill.skill_id))
	content.add_child(upgrade_button)
	return row


func _get_progression_text(skill: SkillDefinition, level: int) -> String:
	if level <= 0:
		return "UNLEARNED  •  COST 1 SKILL POINT"
	if level >= SkillDefinition.MAX_LEVEL:
		return "MAXIMUM POWER  •  %.2fx DAMAGE" % skill.get_damage_multiplier(level)
	return "%.2fx DAMAGE  →  %.2fx  •  COST 1 SKILL POINT" % [
		skill.get_damage_multiplier(level),
		skill.get_damage_multiplier(level + 1),
	]


func _on_upgrade_pressed(skill_id: StringName) -> void:
	if _player != null and _player.upgrade_skill(skill_id):
		_rebuild()


func _make_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	return style
