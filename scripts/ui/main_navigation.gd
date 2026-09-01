class_name MainNavigation
extends Control

## Persistent foreground navigation for the portrait combat screen.
## The center resource frame is presentation-only; side entries reuse the
## existing navigation signals and panels where those systems are available.
signal character_pressed
signal inventory_pressed
signal shop_pressed

const FORGE_TEXTURE: Texture2D = preload("res://assets/ui/buttons/forge.png")
const CHARACTER_TEXTURE: Texture2D = preload("res://assets/ui/buttons/character.png")
const CHARACTER_BUTTON_BACKGROUND: Texture2D = preload("res://assets/ui/buttons/btn-bg-normal.png")
const INVENTORY_TEXTURE: Texture2D = preload("res://assets/ui/buttons/bag.png")
const MODES_TEXTURE: Texture2D = preload("res://assets/ui/buttons/map.png")
const REWARDS_TEXTURE: Texture2D = preload("res://assets/ui/buttons/reward.png")
const SHOP_TEXTURE: Texture2D = preload("res://assets/ui/buttons/shop.png")
const RESOURCE_FRAME_TEXTURE: Texture2D = preload("res://assets/ui/hud/hp-mana.png")
const RESOURCE_ORB_SCRIPT: Script = preload("res://scripts/ui/resource_orb.gd")

const COLOR_TEXT := Color("e8dfd0")
const COLOR_GOLD := Color("e5b95c")
const COLOR_HP := Color("f1d6d0")
const COLOR_MANA := Color("d5e6ff")
const COLOR_EXP := Color("42d6dc")
const COLOR_BORDER := Color("5b422d")

var _hp_label: Label
var _mana_label: Label
var _level_label: Label
var _hp_orb: Control
var _mana_orb: Control
var _experience_bar: ColorRect
var _experience_fill: ColorRect
var _experience_percent_label: Label


func _ready() -> void:
	_build_ui()


func set_player_status(
	current_hp: int,
	max_hp: int,
	level: int,
	current_mana: int,
	max_mana: int,
	experience_ratio: float = 0.0,
) -> void:
	if _hp_label == null:
		return
	_hp_label.text = "%s / %s" % [_format_number(current_hp), _format_number(max_hp)]
	_mana_label.text = "%s / %s" % [_format_number(current_mana), _format_number(max_mana)]
	_level_label.text = str(maxi(level, 1))
	var ratio := clampf(experience_ratio, 0.0, 1.0)
	if _hp_orb != null:
		_hp_orb.call("set_fill_ratio", float(current_hp) / float(maxi(max_hp, 1)))
	if _mana_orb != null:
		_mana_orb.call("set_fill_ratio", float(current_mana) / float(maxi(max_mana, 1)))
	_experience_fill.size.x = 227.0 * ratio
	_experience_percent_label.text = "%.1f%%" % (ratio * 100.0)


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	margin.add_child(row)

	var left_items := HBoxContainer.new()
	left_items.name = "LeftNavigationItems"
	left_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_items.size_flags_stretch_ratio = 1.0
	left_items.add_theme_constant_override("separation", 1)
	row.add_child(left_items)
	_add_icon_item(left_items, "CHARACTER", CHARACTER_TEXTURE, true, _on_character_pressed, CHARACTER_BUTTON_BACKGROUND)
	_add_icon_item(left_items, "INVENTORY", INVENTORY_TEXTURE, true, _on_inventory_pressed)
	_add_icon_item(left_items, "FORGE", FORGE_TEXTURE, false)

	var resource_status := _create_resource_status()
	resource_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_status.size_flags_stretch_ratio = 1.25
	row.add_child(resource_status)

	var right_items := HBoxContainer.new()
	right_items.name = "RightNavigationItems"
	right_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_items.size_flags_stretch_ratio = 1.0
	right_items.add_theme_constant_override("separation", 1)
	row.add_child(right_items)
	_add_icon_item(right_items, "MODES", MODES_TEXTURE, false)
	_add_icon_item(right_items, "REWARDS", REWARDS_TEXTURE, false)
	_add_icon_item(right_items, "SHOP", SHOP_TEXTURE, true, _on_shop_pressed)


func _add_icon_item(
	row: HBoxContainer,
	label_text: String,
	texture: Texture2D,
	clickable: bool,
	callback: Callable = Callable(),
	background_texture: Texture2D = null,
) -> void:
	var item := Control.new()
	item.name = label_text + "NavigationItem"
	item.custom_minimum_size = Vector2(0, 190)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(item)

	if background_texture != null:
		var background := TextureRect.new()
		background.name = "ButtonBackground"
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		background.offset_left = 2
		background.offset_top = 2
		background.offset_right = -2
		background.offset_bottom = -2
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		background.texture = background_texture
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(background)

	var icon_box := TextureRect.new()
	icon_box.name = "Icon"
	icon_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_box.offset_left = 3
	icon_box.offset_top = 3
	icon_box.offset_right = -3
	icon_box.offset_bottom = -31
	icon_box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_box.texture = texture
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(icon_box)

	var label := Label.new()
	label.name = "Label"
	label.text = label_text
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -36 if label_text == "CHARACTER" else -28
	label.offset_bottom = -8 if label_text == "CHARACTER" else 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(label)

	if clickable:
		_add_click_target(item, callback)


func _create_resource_status() -> Control:
	var status := Control.new()
	status.name = "PlayerResourceStatus"
	status.custom_minimum_size = Vector2(0, 190)

	var frame := TextureRect.new()
	frame.name = "ResourceFrame"
	frame.set_anchors_preset(Control.PRESET_TOP_WIDE)
	frame.offset_bottom = 178
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture = RESOURCE_FRAME_TEXTURE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_orb = _add_resource_orb(status, "HPOrb", Color("b83b35"), Rect2(6, 14, 119, 148))
	_mana_orb = _add_resource_orb(status, "ManaOrb", Color("2c70cf"), Rect2(142, 14, 119, 148))
	# Keep the metal artwork above the fill while its transparent openings
	# still reveal the current resource amount.
	status.add_child(frame)

	_hp_label = _create_status_label(status, "HPValue", COLOR_HP, Rect2(8, 137, 98, 22), 10)
	_mana_label = _create_status_label(status, "ManaValue", COLOR_MANA, Rect2(159, 137, 98, 22), 10)
	_level_label = _create_status_label(status, "LevelValue", COLOR_TEXT, Rect2(108, 106, 49, 27), 16)

	_experience_bar = ColorRect.new()
	_experience_bar.name = "ExperienceBar"
	_experience_bar.position = Vector2(18, 166)
	_experience_bar.size = Vector2(229, 8)
	_experience_bar.color = Color("171620")
	_experience_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_child(_experience_bar)
	_experience_fill = ColorRect.new()
	_experience_fill.name = "ExperienceFill"
	_experience_fill.position = Vector2(1, 1)
	_experience_fill.size = Vector2(0, 6)
	_experience_fill.color = COLOR_EXP
	_experience_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_experience_bar.add_child(_experience_fill)

	_experience_percent_label = _create_status_label(
		status,
		"ExperiencePercent",
		COLOR_EXP,
		Rect2(99, 175, 67, 17),
		10,
	)
	return status


func _add_resource_orb(parent: Control, orb_name: String, color: Color, rect: Rect2) -> Control:
	var orb := Control.new()
	orb.name = orb_name
	orb.set_script(RESOURCE_ORB_SCRIPT)
	orb.position = rect.position
	orb.size = rect.size
	orb.set("fill_color", color)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(orb)
	return orb


func _create_status_label(
	parent: Control,
	label_name: String,
	color: Color,
	rect: Rect2,
	font_size: int,
) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = "0 / 0"
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
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
	var result := ",".join(groups)
	return ("-" if negative else "") + result


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
