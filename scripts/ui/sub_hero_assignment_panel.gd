class_name SubHeroAssignmentPanel
extends Control

const SubHeroCatalogResource = preload("res://scripts/sub_hero/sub_hero_catalog.gd")
const SubHeroProgressionServiceResource = preload("res://scripts/sub_hero/sub_hero_progression_service.gd")
const SubHeroQualityResource = preload("res://scripts/sub_hero/sub_hero_quality.gd")

signal panel_closed
signal data_changed

const COLOR_PANEL := Color("120f1b")
const COLOR_TEXT := Color("eee7d8")
const COLOR_MUTED := Color("9d93ae")
const COLOR_GOLD := Color("e8c465")
const COLOR_RED := Color("d46a78")
const COLOR_GREEN := Color("89c797")

var _player: Node
var _panel: PanelContainer
var _list: VBoxContainer
var _status_label: Label
var _slot_label: Label
var _slot_index: int = 0


func _ready() -> void:
	_build_ui()
	_layout_panel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_panel()


func set_player(player: Node) -> void:
	_player = player


func show_for_slot(slot_index: int) -> void:
	_slot_index = clampi(slot_index, 0, SubHeroProgressionServiceResource.MAX_ACTIVE_SLOTS - 1)
	_refresh_list()
	visible = true


func hide_panel() -> void:
	visible = false
	panel_closed.emit()


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.015, 0.04, 0.82)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.name = "AssignmentPanel"
	_panel.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL, Color("604a2b"), 2, 10))
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "ASSIGN SUB HERO"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 21)
	header.add_child(title)
	var close := _make_button("CLOSE")
	close.custom_minimum_size = Vector2(92, 40)
	close.pressed.connect(hide_panel)
	header.add_child(close)

	_slot_label = Label.new()
	_slot_label.add_theme_color_override("font_color", COLOR_MUTED)
	content.add_child(_slot_label)

	var hint := Label.new()
	hint.text = "Choose an owned Sub Hero for this combat slot. No Gold required."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	content.add_child(hint)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 7)
	content.add_child(_list)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", COLOR_MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_status_label)


func _layout_panel() -> void:
	if _panel == null:
		return
	var viewport_size := size
	var half_width: float = minf(320.0, maxf(viewport_size.x * 0.5 - 20.0, 140.0))
	var half_height: float = minf(360.0, maxf(viewport_size.y * 0.5 - 20.0, 220.0))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -half_width
	_panel.offset_top = -half_height
	_panel.offset_right = half_width
	_panel.offset_bottom = half_height


func _refresh_list() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	_slot_label.text = "COMBAT SLOT %d" % (_slot_index + 1)
	_status_label.text = ""
	if _player == null or not _player.has_method("get_sub_hero_progression"):
		_status_label.text = "No player available."
		return
	var progression: SubHeroProgressionService = _player.get_sub_hero_progression()
	var owned_ids: Array[StringName] = progression.get_owned_hero_ids()
	if owned_ids.is_empty():
		_status_label.text = "No owned Sub Heroes. Use SHOP or DEV first."
		return
	for hero_id in owned_ids:
		var data: SubHeroData = SubHeroCatalogResource.get_data(hero_id)
		var instance: SubHeroInstance = progression.get_owned_instance(hero_id)
		if data == null or instance == null:
			continue
		var button := _make_button(
			"%s  •  %s  •  LV %d  •  ATK %d" % [data.display_name, SubHeroQualityResource.get_display_name(data.quality).to_upper(), instance.level, data.attack_damage]
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_color_override("font_color", SubHeroQualityResource.get_color(data.quality))
		var active_slot: int = _find_active_slot(progression, hero_id)
		if active_slot >= 0 and active_slot != _slot_index:
			button.disabled = true
			button.tooltip_text = "Already assigned to combat slot %d." % (active_slot + 1)
		else:
			button.pressed.connect(_on_hero_selected.bind(hero_id))
		_list.add_child(button)

	var current_id: StringName = _get_active_slot_id(progression, _slot_index)
	if not current_id.is_empty():
		var remove_button := _make_button("REMOVE FROM SLOT %d" % (_slot_index + 1))
		remove_button.add_theme_color_override("font_color", COLOR_RED)
		remove_button.pressed.connect(_on_remove_pressed)
		_list.add_child(remove_button)


func _on_hero_selected(hero_id: StringName) -> void:
	if _player != null and _player.has_method("assign_sub_hero_slot") and _player.assign_sub_hero_slot(_slot_index, hero_id):
		_status_label.text = "Assigned to combat slot %d." % (_slot_index + 1)
		_status_label.add_theme_color_override("font_color", COLOR_GREEN)
		data_changed.emit()
		hide_panel()
	else:
		_status_label.text = "That Sub Hero is already assigned to another slot."
		_status_label.add_theme_color_override("font_color", COLOR_RED)


func _on_remove_pressed() -> void:
	if _player != null and _player.has_method("remove_sub_hero_slot") and _player.remove_sub_hero_slot(_slot_index):
		data_changed.emit()
		hide_panel()


func _get_active_slot_id(progression: SubHeroProgressionService, slot_index: int) -> StringName:
	if slot_index < 0 or slot_index >= progression.active_slot_ids.size():
		return &""
	return progression.active_slot_ids[slot_index]


func _find_active_slot(progression: SubHeroProgressionService, hero_id: StringName) -> int:
	for index in progression.active_slot_ids.size():
		if progression.active_slot_ids[index] == hero_id:
			return index
	return -1


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", Color("5e5868"))
	button.add_theme_stylebox_override("normal", _make_style(Color("181522"), Color("3f344c"), 1, 6))
	button.add_theme_stylebox_override("hover", _make_style(Color("362a3f"), COLOR_GOLD, 2, 6))
	button.add_theme_stylebox_override("pressed", _make_style(Color("4a351b"), COLOR_GOLD, 2, 6))
	return button


func _make_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
