class_name MainNavigation
extends Control

## Scene-owned navigation. This script only handles signals and live player data.
signal character_pressed
signal inventory_pressed
signal shop_pressed

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
