class_name HeaderRow
extends Control

@export var gold: int = 0:
	set(value):
		gold = maxi(value, 0)
		_refresh_gold_label()

@export var player_level: int = 1:
	set(value):
		player_level = maxi(value, 1)
		_refresh_level_label()

## Assign max_hp BEFORE current_hp — the display clamps current_hp against max_hp.
@export var max_hp: int = 1:
	set(value):
		max_hp = maxi(value, 1)
		_refresh_hp_display()

@export var current_hp: int = 1:
	set(value):
		current_hp = maxi(value, 0)
		_refresh_hp_display()

@export_enum("Player Turn", "Enemy Turn", "Victory", "Defeat") var turn_phase: int = TurnState.PLAYER_TURN:
	set(value):
		turn_phase = value
		_refresh_turn_label()

@onready var _gold_label: Label = %GoldLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _level_label: Label = %LevelLabel
@onready var _hp_bar: ProgressBar = %PlayerHPBar
@onready var _hp_value_label: Label = %PlayerHPValue


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	_refresh_gold_label()
	_refresh_level_label()
	_refresh_hp_display()
	_refresh_turn_label()


func _refresh_gold_label() -> void:
	if _gold_label != null:
		_gold_label.text = _format_number(gold)


func _refresh_level_label() -> void:
	if _level_label != null:
		_level_label.text = str(player_level)


func _refresh_hp_display() -> void:
	if _hp_bar == null or _hp_value_label == null:
		return
	var shown_hp: int = clampi(current_hp, 0, max_hp)
	_hp_bar.max_value = max_hp
	_hp_bar.value = shown_hp
	_hp_value_label.text = "%d / %d" % [shown_hp, max_hp]


func _refresh_turn_label() -> void:
	if _turn_label != null:
		_turn_label.text = _get_turn_label()
		_turn_label.modulate = _get_turn_color()


func _get_turn_label() -> String:
	match turn_phase:
		TurnState.PLAYER_TURN:
			return "YOUR TURN"
		TurnState.ENEMY_TURN:
			return "ENEMY TURN"
		TurnState.VICTORY:
			return "VICTORY"
		TurnState.DEFEAT:
			return "DEFEAT"
		_:
			return "-"


func _get_turn_color() -> Color:
	match turn_phase:
		TurnState.PLAYER_TURN:
			return Color("d9b565")
		TurnState.ENEMY_TURN:
			return Color("d46a78")
		TurnState.VICTORY:
			return Color("89c797")
		TurnState.DEFEAT:
			return Color("d46a78")
		_:
			return Color("b9afc6")


func _format_number(value: int) -> String:
	var text_value: String = str(maxi(value, 0))
	var formatted: String = ""
	while text_value.length() > 3:
		formatted = "," + text_value.substr(text_value.length() - 3, 3) + formatted
		text_value = text_value.substr(0, text_value.length() - 3)
	return text_value + formatted
