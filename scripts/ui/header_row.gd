class_name HeaderRow
extends Control

@export var gold: int = 0:
	set(value):
		gold = maxi(value, 0)
		_refresh_gold_label()

@export_enum("Player Turn", "Enemy Turn", "Victory", "Defeat") var turn_phase: int = TurnState.PLAYER_TURN:
	set(value):
		turn_phase = value
		_refresh_turn_label()

@onready var _gold_label: Label = %GoldLabel
@onready var _turn_label: Label = %TurnLabel


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	_refresh_gold_label()
	_refresh_turn_label()

func _refresh_gold_label() -> void:
	if _gold_label != null:
		_gold_label.text = _format_number(gold)


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
