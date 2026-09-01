class_name MainNavigation
extends Control

## Scene-owned navigation. This script only handles signals and live player data.
signal character_pressed
signal inventory_pressed
signal shop_pressed

@onready var _hp_label: Label = %HPValue
@onready var _mana_label: Label = %ManaValue
@onready var _level_label: Label = %LevelValue
@onready var _hp_orb: ResourceOrb = $Panel/Margin/Row/PlayerResourceStatus/HPOrb
@onready var _mana_orb: ResourceOrb = $Panel/Margin/Row/PlayerResourceStatus/ManaOrb
@onready var _experience_fill: ColorRect = %ExperienceFill
@onready var _experience_percent_label: Label = %ExperiencePercent

func set_player_status(current_hp: int, max_hp: int, level: int, current_mana: int, max_mana: int, experience_ratio: float = 0.0) -> void:
	_hp_label.text = "%s / %s" % [_format_number(current_hp), _format_number(max_hp)]
	_mana_label.text = "%s / %s" % [_format_number(current_mana), _format_number(max_mana)]
	_level_label.text = str(maxi(level, 1))
	var ratio := clampf(experience_ratio, 0.0, 1.0)
	_hp_orb.set_fill_ratio(float(current_hp) / float(maxi(max_hp, 1)))
	_mana_orb.set_fill_ratio(float(current_mana) / float(maxi(max_mana, 1)))
	_experience_fill.size.x = 227.0 * ratio
	_experience_percent_label.text = "%.1f%%" % (ratio * 100.0)

func _on_character_pressed() -> void:
	character_pressed.emit()

func _on_inventory_pressed() -> void:
	inventory_pressed.emit()

func _on_shop_pressed() -> void:
	shop_pressed.emit()

func _format_number(value: int) -> String:
	var negative := value < 0
	var digits := str(absi(value))
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.substr(digits.length() - 3, 3))
		digits = digits.substr(0, digits.length() - 3)
	groups.push_front(digits)
	return ("-" if negative else "") + ",".join(groups)
