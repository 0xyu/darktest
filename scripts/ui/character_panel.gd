class_name CharacterPanel
extends Control

## Read-only character sheet: lists the player's combat attributes from
## PlayerStats plus the current level from PlayerProgression.
##
## Display only - it reads existing resources and never mutates gameplay state.

signal panel_closed

## Label / PlayerStats property pairs. Values are read straight off the resource
## so no attribute value is duplicated in the UI layer. `as_percent` renders a
## 0..1 ratio as a whole percentage, `prefix`/`suffix` decorate plain numbers.
const STAT_ROWS: Array[Dictionary] = [
	{"label": "CURRENT HP", "key": "current_hp"},
	{"label": "MAX HP", "key": "max_hp"},
	{"label": "ATTACK", "key": "attack"},
	{"label": "DEFENSE", "key": "defense"},
	{"label": "CRITICAL CHANCE", "key": "critical_chance", "as_percent": true},
	{"label": "CRITICAL DAMAGE", "key": "critical_damage", "suffix": "x"},
	{"label": "MOVEMENT POINTS", "key": "movement_points"},
	{"label": "ATTACK RANGE", "key": "attack_range"},
	{"label": "DODGE", "key": "dodge", "as_percent": true},
	{"label": "LIFE STEAL", "key": "life_steal", "as_percent": true},
	{"label": "DAMAGE VS ELITE", "key": "damage_vs_elite", "as_percent": true},
	{"label": "DAMAGE VS BOSS", "key": "damage_vs_boss", "as_percent": true},
	{"label": "STUN CHANCE", "key": "stun_chance", "as_percent": true},
]

const COLOR_LABEL := Color(0.62, 0.58, 0.68, 1.0)
const COLOR_VALUE := Color(0.91, 0.84, 0.69, 1.0)

@onready var _level_label: Label = %LevelLabel
@onready var _stat_list: VBoxContainer = %StatList
@onready var _close_button: Button = %CloseButton

var _player: PlayerController = null
## Built rows: [{ "row": <STAT_ROWS entry>, "value": <Label> }, ...]
var _rows: Array[Dictionary] = []


func _ready() -> void:
	_close_button.pressed.connect(hide_panel)
	_build_rows()
	visibility_changed.connect(_refresh)
	_refresh()


## Binds the panel to the player it should read. Safe to call repeatedly; the
## DEV panel can replace the player object while this panel still holds the old one.
func set_player(player: PlayerController) -> void:
	if _player != null:
		if _player.level_up.is_connected(_on_player_level_up):
			_player.level_up.disconnect(_on_player_level_up)
		if _player.action_completed.is_connected(_refresh):
			_player.action_completed.disconnect(_refresh)
	_player = player
	if _player != null:
		if not _player.level_up.is_connected(_on_player_level_up):
			_player.level_up.connect(_on_player_level_up)
		if not _player.action_completed.is_connected(_refresh):
			_player.action_completed.connect(_refresh)
	_refresh()


## `level_up` carries the new level; the panel reads every number off the player it is
## bound to, so the argument is only there to match the signal's own signature.
func _on_player_level_up(_new_level: int) -> void:
	_refresh()


func show_panel() -> void:
	visible = true
	_refresh()


func hide_panel() -> void:
	visible = false
	panel_closed.emit()


func toggle_panel() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()


func _build_rows() -> void:
	for child in _stat_list.get_children():
		child.queue_free()
	_rows.clear()
	for row in STAT_ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)

		var name_label := Label.new()
		name_label.text = String(row["label"])
		name_label.add_theme_color_override("font_color", COLOR_LABEL)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var value_label := Label.new()
		value_label.add_theme_color_override("font_color", COLOR_VALUE)
		value_label.add_theme_font_size_override("font_size", 13)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		line.add_child(name_label)
		line.add_child(value_label)
		_stat_list.add_child(line)
		_rows.append({"row": row, "value": value_label})


func _refresh() -> void:
	var stats: PlayerStats = _player.player_stats if _player != null else null
	var progression: PlayerProgression = _player.player_progression if _player != null else null
	_level_label.text = "LEVEL %d" % (progression.level if progression != null else 1)
	for entry in _rows:
		var value_label: Label = entry["value"]
		value_label.text = _format_value(stats, entry["row"])


func _format_value(stats: PlayerStats, row: Dictionary) -> String:
	if stats == null:
		return "-"
	var value: Variant = stats.get(StringName(row["key"]))
	if value == null:
		return "-"
	if bool(row.get("as_percent", false)):
		return "%d%%" % roundi(float(value) * 100.0)
	return "%s%s" % [value, String(row.get("suffix", ""))]
