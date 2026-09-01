class_name MainNavigation
extends Control

## Persistent foreground navigation for the portrait combat screen.
## Character and Inventory reuse the existing equipment/inventory panel;
## the remaining entries are presentation-only until their systems exist.
signal character_pressed
signal inventory_pressed

const TOWN_TEXTURE: Texture2D = preload("res://assets/ui/buttons/forge.png")
const CHARACTER_TEXTURE: Texture2D = preload("res://assets/ui/buttons/character.png")
const HP_TEXTURE: Texture2D = preload("res://assets/ui/hud/hp.png")
const MANA_TEXTURE: Texture2D = preload("res://assets/ui/hud/mana.png")
const INVENTORY_TEXTURE: Texture2D = preload("res://assets/ui/buttons/bag.png")
const BATTLEFIELD_TEXTURE: Texture2D = preload("res://assets/ui/buttons/map.png")

const COLOR_TEXT := Color("e8dfd0")
const COLOR_MUTED := Color("9b8f9e")
const COLOR_GOLD := Color("e5b95c")
const COLOR_BORDER := Color("5b422d")

var _hp_label: Label
var _mana_label: Label


func _ready() -> void:
	_build_ui()


func set_player_status(current_hp: int, max_hp: int, _level: int, current_mana: int, max_mana: int) -> void:
	if _hp_label == null:
		return
	_hp_label.text = "HP %d / %d" % [maxi(current_hp, 0), maxi(max_hp, 0)]
	_mana_label.text = "MP %d / %d" % [maxi(current_mana, 0), maxi(max_mana, 0)]


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	margin.add_child(row)

	_add_icon_item(row, "城镇", TOWN_TEXTURE, false)
	_add_separator(row)
	_add_icon_item(row, "角色", CHARACTER_TEXTURE, true, _on_character_pressed)
	_add_separator(row)
	_add_status_item(row, "血量", HP_TEXTURE, "HP 0 / 0", "hp")
	_add_separator(row)
	_add_status_item(row, "mana", MANA_TEXTURE, "MP 0 / 0", "mana")
	_add_separator(row)
	_add_icon_item(row, "背包", INVENTORY_TEXTURE, true, _on_inventory_pressed)
	_add_separator(row)
	_add_icon_item(row, "战场", BATTLEFIELD_TEXTURE, false)


func _add_icon_item(row: HBoxContainer, label_text: String, texture: Texture2D, clickable: bool, callback: Callable = Callable()) -> void:
	var item := _create_item(row, label_text)
	var icon_box := _create_icon_box(item, texture)
	_create_label(item, label_text, false)
	if clickable:
		_add_click_target(item, callback)
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _add_status_item(row: HBoxContainer, label_text: String, texture: Texture2D, value_text: String, value_key: String) -> void:
	var item := _create_item(row, label_text)
	_create_icon_box(item, texture)
	var value_label := _create_label(item, value_text, true)
	match value_key:
		"hp":
			_hp_label = value_label
		"mana":
			_mana_label = value_label


func _create_item(row: HBoxContainer, label_text: String) -> Control:
	var item := Control.new()
	item.name = label_text + "NavigationItem"
	item.custom_minimum_size = Vector2(0, 140)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(item)
	return item


func _create_icon_box(item: Control, texture: Texture2D) -> TextureRect:
	var icon_box := TextureRect.new()
	icon_box.custom_minimum_size = Vector2(0, 103)
	icon_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_box.texture = texture
	icon_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_box.offset_left = 2
	icon_box.offset_top = 1
	icon_box.offset_right = -2
	icon_box.offset_bottom = -22
	item.add_child(icon_box)
	return icon_box


func _create_label(item: Control, label_text: String, is_value: bool) -> Label:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", COLOR_GOLD if is_value else COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 10 if is_value else 11)
	label.custom_minimum_size = Vector2(0, 20)
	label.size_flags_vertical = Control.SIZE_SHRINK_END
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -22
	label.offset_bottom = 0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(label)
	return label


func _add_click_target(item: Control, callback: Callable) -> void:
	var button := Button.new()
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _make_button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", _make_button_style(Color(0.8, 0.58, 0.2, 0.12), COLOR_BORDER, 1))
	button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.8, 0.58, 0.2, 0.2), COLOR_GOLD, 1))
	button.pressed.connect(callback)
	item.add_child(button)


func _add_separator(row: HBoxContainer) -> void:
	var separator := VSeparator.new()
	separator.custom_minimum_size = Vector2(1, 120)
	separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	separator.add_theme_stylebox_override("separator", _make_button_style(Color("33252a"), Color("4f3a2a"), 0))
	row.add_child(separator)


func _on_character_pressed() -> void:
	character_pressed.emit()


func _on_inventory_pressed() -> void:
	inventory_pressed.emit()


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("09080d")
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.border_width_top = 2
	return style


func _make_button_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(3)
	return style
