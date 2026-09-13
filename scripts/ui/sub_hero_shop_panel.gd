class_name SubHeroShopPanel
extends Control

const SubHeroQualityResource = preload("res://scripts/sub_hero/sub_hero_quality.gd")
const SubHeroSummonServiceResource = preload("res://scripts/sub_hero/sub_hero_summon_service.gd")
const SubHeroCatalogResource = preload("res://scripts/sub_hero/sub_hero_catalog.gd")
const SubHeroProgressionServiceResource = preload("res://scripts/sub_hero/sub_hero_progression_service.gd")

signal panel_closed
signal data_changed

@export var summon_service: SubHeroSummonService

const COLOR_PANEL := Color("120f1b")
const COLOR_PANEL_ALT := Color("1a1524")
const COLOR_TEXT := Color("eee7d8")
const COLOR_MUTED := Color("9d93ae")
const COLOR_GOLD := Color("e8c465")
const COLOR_RED := Color("d46a78")
const COLOR_GREEN := Color("89c797")

var _player: Node
var _panel: PanelContainer
var _gold_label: Label
var _owned_label: Label
var _status_label: Label
var _result_content: VBoxContainer
var _summon_button: Button
var _last_result: Dictionary = {}


func _ready() -> void:
	if summon_service == null:
		summon_service = SubHeroSummonServiceResource.new()
	_sync_balance_profile()
	_build_ui()
	_layout_panel()
	_render_result()
	_refresh()


## §7: the summon PRICE comes from the profile's `G`, so the service is handed the same profile
## instance the hero and the enemies read — never a restated constant.
func _sync_balance_profile() -> void:
	if summon_service == null or _player == null:
		return
	var player_profile: Variant = _player.get("balance_profile")
	if player_profile is BalanceProfile and player_profile != null:
		summon_service.balance_profile = player_profile as BalanceProfile


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_panel()


func set_player(player: Node) -> void:
	_player = player
	_sync_balance_profile()
	_refresh()


func show_panel() -> void:
	_refresh()
	visible = true


func hide_panel() -> void:
	visible = false
	panel_closed.emit()


func toggle_panel() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.015, 0.04, 0.82)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.name = "ShopPanel"
	_panel.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL, Color("604a2b"), 2, 10))
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "SUB HERO SUMMON"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 21)
	header.add_child(title)
	var close_button := _make_button("CLOSE", false)
	close_button.custom_minimum_size = Vector2(92, 40)
	close_button.pressed.connect(hide_panel)
	header.add_child(close_button)

	var subtitle := Label.new()
	subtitle.text = "Call a persistent ally. Duplicates become progression."
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(subtitle)

	var economy_row := HBoxContainer.new()
	economy_row.add_theme_constant_override("separation", 12)
	content.add_child(economy_row)
	_gold_label = Label.new()
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_label.add_theme_color_override("font_color", COLOR_GOLD)
	_gold_label.add_theme_font_size_override("font_size", 16)
	economy_row.add_child(_gold_label)
	_owned_label = Label.new()
	_owned_label.add_theme_color_override("font_color", COLOR_TEXT)
	_owned_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	economy_row.add_child(_owned_label)

	var odds_panel := PanelContainer.new()
	odds_panel.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL_ALT, Color("3f344c"), 1, 6))
	content.add_child(odds_panel)
	var odds_margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		odds_margin.add_theme_constant_override("margin_" + side, 9)
	odds_panel.add_child(odds_margin)
	var odds_content := VBoxContainer.new()
	odds_content.add_theme_constant_override("separation", 4)
	odds_margin.add_child(odds_content)
	var odds_title := Label.new()
	odds_title.text = "QUALITY ODDS"
	odds_title.add_theme_color_override("font_color", COLOR_MUTED)
	odds_title.add_theme_font_size_override("font_size", 11)
	odds_content.add_child(odds_title)
	var odds_row := HBoxContainer.new()
	odds_row.add_theme_constant_override("separation", 8)
	odds_content.add_child(odds_row)
	for quality in [SubHeroQuality.COMMON, SubHeroQuality.RARE, SubHeroQuality.LEGENDARY]:
		var quality_label := Label.new()
		quality_label.text = "%s %s" % [_quality_name(quality).to_upper(), _format_weight(quality)]
		quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quality_label.add_theme_color_override("font_color", SubHeroQualityResource.get_color(quality))
		quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		odds_row.add_child(quality_label)

	_summon_button = _make_button("SUMMON", true)
	_summon_button.custom_minimum_size = Vector2(0, 52)
	_summon_button.pressed.connect(_on_summon_pressed)
	content.add_child(_summon_button)

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(0, 26)
	_status_label.add_theme_color_override("font_color", COLOR_MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_status_label)

	var result_title := Label.new()
	result_title.text = "LATEST RESULT"
	result_title.add_theme_color_override("font_color", COLOR_MUTED)
	result_title.add_theme_font_size_override("font_size", 11)
	content.add_child(result_title)

	var result_panel := PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL_ALT, Color("3f344c"), 1, 6))
	content.add_child(result_panel)
	var result_margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		result_margin.add_theme_constant_override("margin_" + side, 10)
	result_panel.add_child(result_margin)
	_result_content = VBoxContainer.new()
	_result_content.add_theme_constant_override("separation", 6)
	result_margin.add_child(_result_content)

	var footer := Label.new()
	footer.text = "Sub Heroes attack continuously during active combat."
	footer.add_theme_color_override("font_color", COLOR_MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(footer)


func _layout_panel() -> void:
	if _panel == null:
		return
	var viewport_size := size
	var half_width: float = minf(320.0, maxf(viewport_size.x * 0.5 - 20.0, 140.0))
	var half_height: float = minf(370.0, maxf(viewport_size.y * 0.5 - 20.0, 220.0))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -half_width
	_panel.offset_top = -half_height
	_panel.offset_right = half_width
	_panel.offset_bottom = half_height


func _on_summon_pressed() -> void:
	if _player == null or summon_service == null:
		_set_status("Summon unavailable.", COLOR_RED)
		return
	var result: Dictionary = summon_service.summon(_player)
	if not bool(result.get("success", false)):
		_set_status(_get_failure_text(str(result.get("reason", ""))), COLOR_RED)
		_refresh()
		return
	_last_result = result
	var data: SubHeroData = result.get("data") as SubHeroData
	var result_text := "NEW RECRUIT" if bool(result.get("is_new", false)) else "DUPLICATE CONVERTED"
	_set_status("%s  //  %s" % [result_text, data.display_name if data != null else "Sub Hero"], COLOR_GREEN)
	_render_result()
	_refresh()
	data_changed.emit()


func _render_result() -> void:
	if _result_content == null:
		return
	for child in _result_content.get_children():
		child.queue_free()
	if _last_result.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No summon yet."
		empty_label.add_theme_color_override("font_color", COLOR_MUTED)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_result_content.add_child(empty_label)
		return

	var data: SubHeroData = _last_result.get("data") as SubHeroData
	var instance: SubHeroInstance = _last_result.get("instance") as SubHeroInstance
	if data == null:
		return
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 10)
	_result_content.add_child(identity_row)
	var portrait := Label.new()
	portrait.text = _get_initials(data.display_name)
	portrait.custom_minimum_size = Vector2(58, 58)
	portrait.add_theme_color_override("font_color", SubHeroQualityResource.get_color(data.quality))
	portrait.add_theme_stylebox_override("normal", _make_style(COLOR_PANEL, SubHeroQualityResource.get_color(data.quality), 2, 6))
	portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_theme_font_size_override("font_size", 18)
	identity_row.add_child(portrait)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_row.add_child(details)
	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	name_label.add_theme_font_size_override("font_size", 18)
	details.add_child(name_label)
	var quality_label := Label.new()
	quality_label.text = "%s  •  LV %d" % [_quality_name(data.quality).to_upper(), int(_last_result.get("level", 1))]
	quality_label.add_theme_color_override("font_color", SubHeroQualityResource.get_color(data.quality))
	details.add_child(quality_label)
	var stat_label := Label.new()
	stat_label.text = "ATK %d  •  INTERVAL %.1fs" % [data.attack_damage, data.attack_interval]
	stat_label.add_theme_color_override("font_color", COLOR_MUTED)
	details.add_child(stat_label)

	var progress_label := Label.new()
	var duplicate_count: int = int(_last_result.get("duplicate_count", 0))
	var requirement: int = 3
	if _player != null and _player.has_method("get_sub_hero_progression"):
		var service: SubHeroProgressionService = _player.get_sub_hero_progression()
		requirement = service.duplicates_per_level
	progress_label.text = "DUPLICATE PROGRESS  %d / %d" % [duplicate_count, requirement]
	progress_label.add_theme_color_override("font_color", COLOR_GREEN if not bool(_last_result.get("is_new", false)) else COLOR_MUTED)
	_result_content.add_child(progress_label)

	var assign_label := Label.new()
	assign_label.text = "ASSIGN TO ACTIVE SLOT"
	assign_label.add_theme_color_override("font_color", COLOR_MUTED)
	assign_label.add_theme_font_size_override("font_size", 11)
	_result_content.add_child(assign_label)
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	_result_content.add_child(slot_row)
	for slot_index in SubHeroProgressionService.MAX_ACTIVE_SLOTS:
		var slot_button := _make_button("SLOT %d" % (slot_index + 1), false)
		slot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var active_id: StringName = _get_active_slot_id(slot_index)
		if active_id == data.id:
			slot_button.text = "SLOT %d  ACTIVE" % (slot_index + 1)
		else:
			slot_button.pressed.connect(_on_assign_slot.bind(slot_index, data.id))
		if not active_id.is_empty() and active_id != data.id:
			# Assignment is allowed only to an empty slot or the same hero.
			slot_button.disabled = true
		slot_row.add_child(slot_button)


func _on_assign_slot(slot_index: int, hero_id: StringName) -> void:
	if _player != null and _player.has_method("assign_sub_hero_slot") and _player.assign_sub_hero_slot(slot_index, hero_id):
		_set_status("Active slot %d assigned." % (slot_index + 1), COLOR_GREEN)
		_render_result()
		data_changed.emit()


func _refresh() -> void:
	var progression: PlayerProgression = _player.get("player_progression") as PlayerProgression if _player != null else null
	if progression == null:
		_gold_label.text = "GOLD --"
		_owned_label.text = "OWNED --"
		_summon_button.disabled = true
		return
	_gold_label.text = "GOLD %s" % _format_number(progression.gold)
	var owned_count: int = _player.get_sub_hero_progression().get_owned_count() if _player.has_method("get_sub_hero_progression") else 0
	_owned_label.text = "OWNED %d / %d" % [owned_count, SubHeroCatalogResource.get_all_data().size()]
	if summon_service == null:
		_summon_button.disabled = true
		return
	if summon_service == null:
		_summon_button.disabled = true
		return
	# §6.2: the price is recomputed here from the current collection, so the button can never
	# advertise a stale cost after a successful summon.
	var summon_cost: int = maxi(summon_service.calculate_summon_cost(_player), 0)
	_summon_button.text = "SUMMON  •  %d GOLD" % summon_cost
	_summon_button.disabled = progression.gold < summon_cost
	if _last_result.is_empty():
		_render_result()


func _get_active_slot_id(slot_index: int) -> StringName:
	if _player == null or not _player.has_method("get_sub_hero_progression"):
		return &""
	var progression: SubHeroProgressionService = _player.get_sub_hero_progression()
	if slot_index < 0 or slot_index >= progression.active_slot_ids.size():
		return &""
	return progression.active_slot_ids[slot_index]


func _set_status(text: String, color: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _quality_name(quality: int) -> String:
	return SubHeroQualityResource.get_display_name(quality)


func _format_weight(quality: int) -> String:
	if summon_service == null or summon_service.summon_table == null:
		return "--"
	var total: float = summon_service.summon_table.get_total_weight()
	if total <= 0.0:
		return "0%"
	return "%.1f%%" % (summon_service.summon_table.get_weight(quality) / total * 100.0)


func _get_failure_text(reason: String) -> String:
	match reason:
		"INSUFFICIENT_GOLD":
			return "Not enough gold."
		"NO_HEROES_FOR_QUALITY":
			return "No Sub Hero is configured for that quality."
		"INVALID_SUMMON_TABLE":
			return "Summon table is unavailable."
		_:
			return "Summon unavailable."


func _get_initials(display_name: String) -> String:
	var parts := display_name.split(" ", false)
	if parts.size() >= 2:
		return (str(parts[0]).left(1) + str(parts[1]).left(1)).to_upper()
	return display_name.left(2).to_upper()


func _format_number(value: int) -> String:
	var text_value := str(maxi(value, 0))
	var formatted := ""
	while text_value.length() > 3:
		formatted = "," + text_value.substr(text_value.length() - 3, 3) + formatted
		text_value = text_value.substr(0, text_value.length() - 3)
	return text_value + formatted


func _make_button(text: String, highlighted: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_color_override("font_color", COLOR_GOLD if highlighted else COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", Color("5e5868"))
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", _make_style(Color("241c2e") if highlighted else Color("181522"), Color("745325") if highlighted else Color("3f344c"), 1, 6))
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
