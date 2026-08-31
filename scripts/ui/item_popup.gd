class_name ItemPopup
extends Control

## Modal item dialog opened by the inventory panel when an item is clicked.
##
## Shows the item's name/details and, depending on the item kind and where it
## lives, the relevant actions:
##   - Consumables (potions): a Use button (no comparison / no equip).
##   - Equipment: an Equip button plus a side-by-side comparison against the item
##     currently equipped in that slot (current slot item on the left, clicked
##     item on the right). Equipping closes the dialog; an already-equipped item
##     opened from a slot shows "已装备".
##   - Bag items: a 放入仓库 (store) button moves them to the warehouse.
##   - Warehouse items (opened with from_storage): a 取出 (withdraw) button moves
##     them back to the bag.
## Discard and Close are always available for bag/warehouse items.
##
## The layout is code-built to match the inventory panel's dark-fantasy styling.
## It is instantiated by EquipmentInventoryPanel via `preload()` so a cold
## headless harness run does not depend on the global class cache.

const COLOR_GOLD := Color("e8c465")
const COLOR_TEXT := Color("d8cfdf")
const COLOR_MUTED := Color("8f879d")
const COLOR_GREEN := Color("82d49b")
const COLOR_RED := Color("d46a78")

var _player: PlayerController
var _item: EquipmentInstance
var _from_storage: bool = false

var _backdrop: ColorRect
var _panel_container: PanelContainer
var _name_label: Label
var _details_label: Label
var _comparison_section: HBoxContainer
var _current_name_label: Label
var _current_details_label: Label
var _clicked_name_label: Label
var _clicked_details_label: Label
var _comparison_label: Label
var _use_button: Button
var _equip_button: Button
var _store_button: Button
var _withdraw_button: Button
var _discard_button: Button
var _close_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# PRESET_MODE_MINSIZE preserves a fresh Control's zero size (offsets go
	# negative), so pin the anchors and zero the offsets to truly fill the parent.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	_build_ui()
	visible = false


## Opens the dialog for `item`. `player` provides the inventory/equip/use/
## discard/storage actions; the dialog refreshes itself after each action.
## `from_storage` marks items clicked inside the warehouse, which swap the
## Equip/Store actions for a single Withdraw action.
func open_for(player: PlayerController, item: EquipmentInstance, from_storage: bool = false) -> void:
	_player = player
	_item = item
	_from_storage = from_storage
	_refresh()
	visible = true


func close() -> void:
	visible = false
	_player = null
	_item = null


func is_open() -> bool:
	return visible


func get_item() -> EquipmentInstance:
	return _item


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.01, 0.008, 0.016, 0.72)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	_panel_container = PanelContainer.new()
	_panel_container.set_anchors_preset(Control.PRESET_CENTER)
	_panel_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel_container.custom_minimum_size = Vector2(360, 0)
	_panel_container.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel_container)

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	_panel_container.add_child(details)

	_name_label = Label.new()
	_name_label.text = ""
	_name_label.add_theme_color_override("font_color", COLOR_GOLD)
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.clip_text = true
	details.add_child(_name_label)

	_details_label = Label.new()
	_details_label.text = ""
	_details_label.add_theme_color_override("font_color", COLOR_TEXT)
	_details_label.add_theme_font_size_override("font_size", 13)
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_details_label)

	# Side-by-side comparison: the currently equipped item on the left, the
	# clicked item on the right. Only shown when comparing un-equipped gear.
	_comparison_section = HBoxContainer.new()
	_comparison_section.add_theme_constant_override("separation", 12)
	details.add_child(_comparison_section)

	var current_column: Dictionary = _make_item_column("当前装备")
	_current_name_label = current_column["name"]
	_current_details_label = current_column["details"]
	_comparison_section.add_child(current_column["root"])

	var vs_label := Label.new()
	vs_label.text = "VS"
	vs_label.add_theme_color_override("font_color", Color("5a5463"))
	vs_label.add_theme_font_size_override("font_size", 13)
	vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_comparison_section.add_child(vs_label)

	var clicked_column: Dictionary = _make_item_column("点击装备")
	_clicked_name_label = clicked_column["name"]
	_clicked_details_label = clicked_column["details"]
	_comparison_section.add_child(clicked_column["root"])

	_comparison_label = Label.new()
	_comparison_label.text = ""
	_comparison_label.add_theme_color_override("font_color", COLOR_MUTED)
	_comparison_label.add_theme_font_size_override("font_size", 12)
	_comparison_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_comparison_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	button_row.custom_minimum_size = Vector2(0, 42)
	details.add_child(button_row)

	_use_button = _make_action_button("使用", true)
	_use_button.pressed.connect(_on_use_pressed)
	button_row.add_child(_use_button)

	_equip_button = _make_action_button("装备", true)
	_equip_button.pressed.connect(_on_equip_pressed)
	button_row.add_child(_equip_button)

	_store_button = _make_action_button("放入仓库", false)
	_store_button.pressed.connect(_on_store_pressed)
	button_row.add_child(_store_button)

	_withdraw_button = _make_action_button("取出", true)
	_withdraw_button.pressed.connect(_on_withdraw_pressed)
	button_row.add_child(_withdraw_button)

	_discard_button = _make_action_button("丢弃", false)
	_discard_button.pressed.connect(_on_discard_pressed)
	button_row.add_child(_discard_button)

	_close_button = _make_action_button("关闭", false)
	_close_button.pressed.connect(close)
	button_row.add_child(_close_button)


func _make_action_button(text: String, gold: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("f8e0a0") if gold else Color("c9bdb4"))
	button.add_theme_color_override("font_disabled_color", Color("4a4552"))
	_apply_button_style(button, gold)
	return button


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _item == null:
		return
	var rarity: int = _item.get_rarity()
	_name_label.text = _item.get_display_name()
	_name_label.modulate = _get_rarity_color(rarity)

	if _from_storage:
		_show_storage_item()
		return

	if _item.is_consumable():
		_name_label.visible = true
		_details_label.visible = true
		_comparison_section.visible = false
		_panel_container.custom_minimum_size = Vector2(360, 0)
		_details_label.text = _format_consumable_details(_item)
		_comparison_label.text = ""
		_comparison_label.visible = false
		_use_button.visible = true
		_use_button.disabled = _is_heal_unavailable()
		_equip_button.visible = false
		_store_button.visible = true
		_store_button.disabled = _is_storage_full()
		_withdraw_button.visible = false
		_discard_button.disabled = false
		return

	_use_button.visible = false
	_equip_button.visible = true
	if _item.is_equipped:
		_name_label.visible = true
		_details_label.visible = true
		_comparison_section.visible = false
		_panel_container.custom_minimum_size = Vector2(360, 0)
		_details_label.text = _format_equipment_details(_item)
		_comparison_label.text = "已装备"
		_comparison_label.modulate = COLOR_GREEN
		_comparison_label.visible = true
		_equip_button.disabled = true
		_store_button.visible = false
		_withdraw_button.visible = false
		_discard_button.disabled = true
		return

	# Comparison: current slot item on the left, clicked item on the right.
	_name_label.visible = false
	_details_label.visible = false
	_comparison_section.visible = true
	_panel_container.custom_minimum_size = Vector2(460, 0)

	var current_item: EquipmentInstance = _current_slot_item()
	if current_item != null:
		_current_name_label.text = current_item.get_display_name()
		_current_name_label.modulate = _get_rarity_color(current_item.get_rarity())
		_current_details_label.text = _format_equipment_details(current_item)
		_current_details_label.visible = true
	else:
		_current_name_label.text = "空部位"
		_current_name_label.modulate = COLOR_MUTED
		_current_details_label.text = ""
		_current_details_label.visible = false

	_clicked_name_label.text = _item.get_display_name()
	_clicked_name_label.modulate = _get_rarity_color(rarity)
	_clicked_details_label.text = _format_equipment_details(_item)

	var comparison: EquipmentComparison = _get_comparison()
	if comparison != null:
		_comparison_label.text = _format_comparison(comparison)
		_comparison_label.modulate = COLOR_GREEN if comparison.is_upgrade() else COLOR_RED
		_comparison_label.visible = true
	else:
		_comparison_label.text = ""
		_comparison_label.visible = false
	_equip_button.disabled = false
	_store_button.visible = true
	_store_button.disabled = _is_storage_full()
	_withdraw_button.visible = false
	_discard_button.disabled = false


## Warehouse view: item details + a single Withdraw action (no equip/use/store).
func _show_storage_item() -> void:
	_name_label.visible = true
	_details_label.visible = true
	_comparison_section.visible = false
	_panel_container.custom_minimum_size = Vector2(360, 0)
	_details_label.text = (
		_format_consumable_details(_item) if _item.is_consumable() else _format_equipment_details(_item)
	)
	_comparison_label.text = "仓库物品"
	_comparison_label.modulate = COLOR_MUTED
	_comparison_label.visible = true
	_use_button.visible = false
	_equip_button.visible = false
	_store_button.visible = false
	_withdraw_button.visible = true
	_withdraw_button.disabled = _is_bag_full()
	_discard_button.disabled = false


func _is_bag_full() -> bool:
	return _player == null or _player.get_inventory() == null or _player.get_inventory().get_remaining_capacity() <= 0


func _is_storage_full() -> bool:
	return _player == null or _player.get_storage() == null or _player.get_storage().get_remaining_capacity() <= 0


func _is_heal_unavailable() -> bool:
	if _player == null or _player.player_stats == null:
		return true
	return _player.player_stats.current_hp <= 0 or _player.player_stats.current_hp >= _player.player_stats.max_hp


func _get_comparison() -> EquipmentComparison:
	if _player == null or _player.get_inventory() == null:
		return null
	return _player.get_inventory().create_comparison(_item)


func _current_slot_item() -> EquipmentInstance:
	if _player == null or _player.get_inventory() == null:
		return null
	return _player.get_inventory().get_equipped_item(_item.get_slot())


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_use_pressed() -> void:
	if _player != null and _player.use_item(_item):
		close()


func _on_equip_pressed() -> void:
	if _player != null and _player.equip_item(_item):
		close()


func _on_store_pressed() -> void:
	if _player != null and _player.move_to_storage(_item):
		close()


func _on_withdraw_pressed() -> void:
	if _player != null and _player.move_to_bag(_item):
		close()


func _on_discard_pressed() -> void:
	if _player == null:
		return
	var discarded: bool = _player.discard_storage_item(_item) if _from_storage else _player.discard_item(_item)
	if discarded:
		close()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close()


# ---------------------------------------------------------------------------
# Formatting & styling helpers
# ---------------------------------------------------------------------------

func _format_consumable_details(item: EquipmentInstance) -> String:
	var lines: Array[String] = [
		"消耗品  •  物品等级 %d" % item.get_item_level(),
		"回复最大生命的 %.0f%%" % (item.get_heal_ratio() * 100.0),
	]
	if item.definition != null and not item.definition.description.is_empty():
		lines.append(item.definition.description)
	return "\n".join(lines)


func _format_equipment_details(item: EquipmentInstance) -> String:
	var lines: Array[String] = [
		"%s  •  物品等级 %d" % [EquipmentSlot.get_display_name(item.get_slot()), item.get_item_level()],
	]
	for affix in item.affixes:
		if affix == null:
			continue
		var value_text: String = "%+.0f%%" % (affix.value * 100.0) if affix.is_percentage else "%+d" % roundi(affix.value)
		lines.append("%s  %s" % [affix.display_name, value_text])
	return "\n".join(lines)


func _format_comparison(comparison: EquipmentComparison) -> String:
	var rows: Array[Dictionary] = comparison.get_stat_rows()
	var lines: Array[String] = []
	if rows.is_empty():
		lines.append("无属性变化")
	else:
		for row in rows:
			lines.append("%s  %s" % [row["display_name"], row["formatted_delta"]])
	lines.append("强度  %s" % ("+%.1f" % comparison.score_delta if comparison.score_delta >= 0.0 else "%.1f" % comparison.score_delta))
	return "\n".join(lines)


func _get_rarity_color(rarity: int) -> Color:
	match rarity:
		EquipmentRarity.UNCOMMON:
			return COLOR_GREEN
		EquipmentRarity.RARE:
			return Color("71a9ed")
		EquipmentRarity.EPIC:
			return Color("b995ef")
		EquipmentRarity.LEGENDARY:
			return Color("e8af4f")
		EquipmentRarity.MYTHIC:
			return Color("f078b2")
		_:
			return Color("b9afc6")


## Builds one comparison column (header + item name + item details) inside a
## subtle card. Returns { "root": PanelContainer, "name": Label, "details": Label }.
func _make_item_column(header_text: String) -> Dictionary:
	var column_root := PanelContainer.new()
	column_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column_root.add_theme_stylebox_override("panel", _column_style())

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column_root.add_child(column)

	var header := Label.new()
	header.text = header_text
	header.add_theme_color_override("font_color", COLOR_MUTED)
	header.add_theme_font_size_override("font_size", 11)
	column.add_child(header)

	var name_label := Label.new()
	name_label.text = ""
	name_label.add_theme_color_override("font_color", COLOR_GOLD)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.clip_text = true
	column.add_child(name_label)

	var details_label := Label.new()
	details_label.text = ""
	details_label.add_theme_color_override("font_color", COLOR_TEXT)
	details_label.add_theme_font_size_override("font_size", 12)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(details_label)

	return {"root": column_root, "name": name_label, "details": details_label}


func _column_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171120", 0.9)
	style.border_color = Color("3a3147")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("120e18", 0.99)
	style.border_color = Color("6c5331")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_top = 14
	style.content_margin_right = 16
	style.content_margin_bottom = 14
	return style


func _apply_button_style(button: Button, gold: bool) -> void:
	var accent := Color("745325") if gold else Color("3f3a48")
	var normal := _make_button_style(Color("241708") if gold else Color("12101a"), accent, 1)
	var hover := _make_button_style(Color("362412") if gold else Color("1c1720"), accent.lightened(0.25), 2)
	var pressed := _make_button_style(Color("2b1f12"), Color("e1ae58"), 2)
	var disabled := _make_button_style(Color("0a0910"), Color("211d28"), 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", disabled)


func _make_button_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	return style
