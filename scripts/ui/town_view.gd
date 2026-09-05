class_name TownView
extends Control

## Portrait town hub listing selectable facilities. Reached from the DEV panel
## (DevelopmentPanel.town_view_requested); the combat HUD toggles this view in
## place of CombatView. Each facility row only emits a request — the HUD decides
## which panel (EquipmentInventoryPanel / SkillPanel) actually opens, so the town
## stays a dumb list of destinations.

signal close_requested
signal warehouse_requested
signal skills_requested

const COLOR_GOLD := Color("e8c465")
const COLOR_GOLD_BRIGHT := Color("f4d28b")
const COLOR_TEXT := Color("d8cfdf")
const COLOR_MUTED := Color("8f879d")
const COLOR_BLUE := Color("71a9ed")
const COLOR_PANEL_BG := Color("120f1b")
const COLOR_BORDER := Color("604a2b")


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.012, 0.01, 0.018, 0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	panel.offset_right = -8.0
	panel.offset_bottom = -8.0
	panel.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL_BG, COLOR_BORDER, 2, 10))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	content.add_child(_build_header())

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color("8c5e26")
	content.add_child(rule)

	var prompt := Label.new()
	prompt.text = "选择一个场所"
	prompt.add_theme_color_override("font_color", COLOR_MUTED)
	prompt.add_theme_font_size_override("font_size", 12)
	content.add_child(prompt)

	var list := VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.alignment = BoxContainer.ALIGNMENT_CENTER
	list.add_theme_constant_override("separation", 14)
	content.add_child(list)

	list.add_child(_make_facility_card("仓库", "存放与取回装备 · 背包满时自动存入", COLOR_GOLD, _on_warehouse_pressed))
	list.add_child(_make_facility_card("技能导师", "消耗技能点学习与升级技能", COLOR_BLUE, _on_skills_pressed))


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 52)
	header.add_theme_constant_override("separation", 8)

	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.add_theme_constant_override("separation", 0)
	header.add_child(title_block)

	var title := Label.new()
	title.text = "TOWN"
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 24)
	title_block.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "城镇 · 选择设施"
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	subtitle.add_theme_font_size_override("font_size", 10)
	title_block.add_child(subtitle)

	var close_button := Button.new()
	close_button.custom_minimum_size = Vector2(64, 44)
	close_button.text = "✕"
	close_button.add_theme_color_override("font_color", COLOR_TEXT)
	close_button.add_theme_font_size_override("font_size", 15)
	close_button.add_theme_stylebox_override("normal", _make_style(Color("0e0c14"), Color("3f344c"), 1, 6))
	close_button.add_theme_stylebox_override("hover", _make_style(Color("1c1720"), COLOR_GOLD, 2, 6))
	close_button.add_theme_stylebox_override("pressed", _make_style(Color("443022"), COLOR_GOLD_BRIGHT, 2, 6))
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_button)
	return header


func _make_facility_card(title_text: String, subtitle_text: String, accent: Color, action: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 92)
	button.add_theme_stylebox_override("normal", _make_style(Color("171224"), Color("3f344c"), 1, 8))
	button.add_theme_stylebox_override("hover", _make_style(Color("241a30"), accent, 2, 8))
	button.add_theme_stylebox_override("pressed", _make_style(Color("443022"), accent.lightened(0.2), 2, 8))
	button.pressed.connect(action)

	var label_box := VBoxContainer.new()
	label_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label_box.offset_left = 16.0
	label_box.offset_top = 6.0
	label_box.offset_right = -16.0
	label_box.offset_bottom = -6.0
	label_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_box.alignment = BoxContainer.ALIGNMENT_CENTER
	label_box.add_theme_constant_override("separation", 4)
	button.add_child(label_box)

	var title_label := Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.text = title_text
	title_label.add_theme_color_override("font_color", accent)
	title_label.add_theme_font_size_override("font_size", 20)
	label_box.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_label.text = subtitle_text
	subtitle_label.add_theme_color_override("font_color", COLOR_MUTED)
	subtitle_label.add_theme_font_size_override("font_size", 11)
	label_box.add_child(subtitle_label)

	return button


func _on_warehouse_pressed() -> void:
	warehouse_requested.emit()


func _on_skills_pressed() -> void:
	skills_requested.emit()


func _make_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
