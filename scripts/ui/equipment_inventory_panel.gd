class_name EquipmentInventoryPanel
extends Control

## Portrait-first equipment management panel for the existing inventory model.
## Item buttons are generated from EquipmentInventory so this UI stays data-driven.
signal panel_closed

const EMPTY_SLOT_ICON: Texture2D = preload("res://assets/ui/inventory/Icon_Frame.png")
const EQUIPMENT_ICON_BY_SLOT: Dictionary = {
	EquipmentSlot.WEAPON: preload("res://assets/items/icons/Icon_Eq_Weapon.png"),
	EquipmentSlot.HELMET: preload("res://assets/items/icons/Icon_Eq_Head.png"),
	EquipmentSlot.ARMOR: preload("res://assets/items/icons/Icon_Eq_Chest.png"),
	EquipmentSlot.GLOVES: preload("res://assets/items/icons/Icon_Eq_Glowes.png"),
	EquipmentSlot.BOOTS: preload("res://assets/items/icons/Icon_Eq_boots.png"),
	EquipmentSlot.RING: preload("res://assets/items/icons/Icon_Eq_ring.png"),
	EquipmentSlot.AMULET: preload("res://assets/items/icons/Icon_Eq_neck.png"),
}

@onready var _close_button: Button = %CloseButton
@onready var _equipped_grid: GridContainer = %EquippedGrid
@onready var _inventory_grid: GridContainer = %InventoryGrid
@onready var _inventory_count_label: Label = %InventoryCount
@onready var _item_name_label: Label = %ItemName
@onready var _item_details_label: Label = %ItemDetails
@onready var _comparison_label: Label = %ComparisonLabel
@onready var _equip_button: Button = %EquipButton
@onready var _discard_button: Button = %DiscardButton

var _player: PlayerController
var _inventory: EquipmentInventory
var _selected_item: EquipmentInstance
var _refresh_scheduled: bool = false


func _ready() -> void:
	_close_button.pressed.connect(hide_inventory)
	_equip_button.pressed.connect(equip_selected_item)
	_discard_button.pressed.connect(discard_selected_item)
	_equipped_grid.columns = 4
	_inventory_grid.columns = 3
	_refresh()


func set_player(player: PlayerController) -> void:
	if _inventory != null:
		if _inventory.inventory_changed.is_connected(_on_inventory_changed):
			_inventory.inventory_changed.disconnect(_on_inventory_changed)
		if _inventory.item_selected.is_connected(_on_item_selected):
			_inventory.item_selected.disconnect(_on_item_selected)
	_player = player
	_inventory = _player.get_inventory() if _player != null else null
	if _inventory != null:
		if not _inventory.inventory_changed.is_connected(_on_inventory_changed):
			_inventory.inventory_changed.connect(_on_inventory_changed)
		if not _inventory.item_selected.is_connected(_on_item_selected):
			_inventory.item_selected.connect(_on_item_selected)
	_request_refresh()


func show_inventory() -> void:
	visible = true
	_request_refresh()


func hide_inventory() -> void:
	visible = false
	panel_closed.emit()


func toggle_inventory() -> void:
	show_inventory() if not visible else hide_inventory()


func select_item(item: EquipmentInstance) -> bool:
	if _inventory == null or item == null:
		return false
	var selected: bool = _inventory.select_item(item)
	if selected:
		_selected_item = _inventory.get_selected_item()
		_request_refresh()
	return selected


func get_selected_item() -> EquipmentInstance:
	return _selected_item


func equip_selected_item() -> bool:
	if _inventory == null or _selected_item == null:
		return false
	var equipped: bool = _player != null and _player.equip_item(_selected_item)
	if equipped:
		_request_refresh()
	return equipped


func discard_selected_item() -> bool:
	if _inventory == null or _selected_item == null:
		return false
	var discarded: bool = _player != null and _player.discard_item(_selected_item)
	if discarded:
		_selected_item = null
		_request_refresh()
	return discarded


func _on_inventory_changed() -> void:
	if _selected_item != null and not _inventory.has_item(_selected_item):
		_selected_item = null
	_request_refresh()


func _on_item_selected(item: EquipmentInstance) -> void:
	_selected_item = item
	_request_refresh()


func _request_refresh() -> void:
	if _refresh_scheduled:
		return
	_refresh_scheduled = true
	call_deferred("_run_scheduled_refresh")


func _run_scheduled_refresh() -> void:
	_refresh_scheduled = false
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	_clear_grid(_equipped_grid)
	_clear_grid(_inventory_grid)
	if _inventory == null:
		_inventory_count_label.text = "INVENTORY 0 / 0"
		_clear_details()
		return

	_inventory_count_label.text = "INVENTORY %d / %d" % [_inventory.get_item_count(), _inventory.capacity]
	for slot in range(EquipmentSlot.WEAPON, EquipmentSlot.AMULET + 1):
		_equipped_grid.add_child(_create_equipped_button(slot, _inventory.get_equipped_item(slot)))
	var inventory_items: Array[EquipmentInstance] = _inventory.get_items()
	_inventory_grid.columns = 3 if not inventory_items.is_empty() else 1
	if inventory_items.is_empty():
		_inventory_grid.add_child(_create_empty_inventory_label())
	else:
		for item in inventory_items:
			_inventory_grid.add_child(_create_inventory_button(item))
	_refresh_details()


func _create_equipped_button(slot: int, item: EquipmentInstance) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 78)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.text = _format_slot_button_text(slot, item)
	button.icon = _get_equipment_icon(slot) if item != null else EMPTY_SLOT_ICON
	button.tooltip_text = item.get_display_name() if item != null else "Empty %s slot" % EquipmentSlot.get_display_name(slot)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", _get_rarity_color(item.get_rarity()) if item != null else Color("8f879d"))
	_apply_button_style(button, item.get_rarity() if item != null else EquipmentRarity.COMMON, item != null)
	button.pressed.connect(_on_equipped_slot_pressed.bind(item))
	button.button_pressed = item != null and item == _selected_item
	return button


func _create_inventory_button(item: EquipmentInstance) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 88)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.text = _format_inventory_button_text(item)
	button.icon = _get_equipment_icon(item.get_slot())
	button.tooltip_text = _format_item_details(item)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", _get_rarity_color(item.get_rarity()))
	_apply_button_style(button, item.get_rarity(), true)
	button.pressed.connect(_on_inventory_item_pressed.bind(item))
	button.button_pressed = item == _selected_item
	return button


func _create_empty_inventory_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(0, 176)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color("62596d"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_font_size_override("font_size", 13)
	label.text = "✧\nNO UNCLAIMED RELICS\n\nLoot from combat will appear here."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _on_equipped_slot_pressed(item: EquipmentInstance) -> void:
	if item != null:
		select_item(item)


func _on_inventory_item_pressed(item: EquipmentInstance) -> void:
	select_item(item)


func _refresh_details() -> void:
	if _selected_item == null or _inventory == null:
		_clear_details()
		return
	var rarity: int = _selected_item.get_rarity()
	_item_name_label.text = _selected_item.get_display_name()
	_item_name_label.modulate = _get_rarity_color(rarity)
	_item_details_label.text = _format_item_details(_selected_item)
	var current_item: EquipmentInstance = _inventory.get_equipped_item(_selected_item.get_slot())
	if _selected_item.is_equipped:
		_comparison_label.text = "EQUIPPED  •  CURRENT ITEM"
		_comparison_label.modulate = Color("89c797")
	else:
		var comparison: EquipmentComparison = _inventory.create_comparison(_selected_item)
		_comparison_label.text = _format_comparison(comparison, current_item)
		_comparison_label.modulate = Color("89c797") if comparison != null and comparison.is_upgrade() else Color("d46a78")
	_equip_button.disabled = _selected_item.is_equipped
	_discard_button.disabled = _selected_item.is_equipped


func _clear_details() -> void:
	_item_name_label.text = "SELECT AN ITEM"
	_item_name_label.modulate = Color("b9afc6")
	_item_details_label.text = "Choose equipment to inspect its affixes."
	_comparison_label.text = "COMPARISON  •  NO ITEM SELECTED"
	_comparison_label.modulate = Color("8f879d")
	_equip_button.disabled = true
	_discard_button.disabled = true


func _format_slot_button_text(slot: int, item: EquipmentInstance) -> String:
	var slot_name: String = EquipmentSlot.get_display_name(slot).to_upper()
	if item == null:
		return "%s\n—" % slot_name
	return "%s\n%s\nILVL %d" % [slot_name, item.get_display_name(), item.get_item_level()]


func _format_inventory_button_text(item: EquipmentInstance) -> String:
	var rarity_name: String = EquipmentRarity.get_display_name(item.get_rarity()).to_upper()
	return "%s  •  ILVL %d\n%s" % [rarity_name, item.get_item_level(), item.get_display_name().to_upper()]


func _get_equipment_icon(slot: int) -> Texture2D:
	return EQUIPMENT_ICON_BY_SLOT.get(slot) as Texture2D


func _format_item_details(item: EquipmentInstance) -> String:
	var lines: Array[String] = [
		"%s  •  ITEM LEVEL %d" % [EquipmentSlot.get_display_name(item.get_slot()).to_upper(), item.get_item_level()],
	]
	for affix in item.affixes:
		if affix == null:
			continue
		var value_text: String = "%+.0f%%" % (affix.value * 100.0) if affix.is_percentage else "%+d" % roundi(affix.value)
		lines.append("%s  %s" % [affix.display_name, value_text])
	return "\n".join(lines)


func _format_comparison(comparison: EquipmentComparison, current_item: EquipmentInstance) -> String:
	if comparison == null:
		return "COMPARISON  •  NO BASELINE\nThis slot is empty."
	var current_name: String = current_item.get_display_name() if current_item != null else "EMPTY SLOT"
	var lines: Array[String] = ["COMPARE  •  %s" % current_name]
	var rows: Array[Dictionary] = comparison.get_stat_rows()
	if rows.is_empty():
		lines.append("No stat changes")
	else:
		for row in rows:
			lines.append("%s  %s" % [row["display_name"], row["formatted_delta"]])
	lines.append("POWER  %s" % ("+%.1f" % comparison.score_delta if comparison.score_delta >= 0.0 else "%.1f" % comparison.score_delta))
	return "\n".join(lines)


func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()


func _apply_button_style(button: Button, rarity: int, has_item: bool) -> void:
	var accent: Color = _get_rarity_color(rarity) if has_item else Color("494252")
	var normal := _make_button_style(Color("12101a") if has_item else Color("0e0d14"), accent.darkened(0.45), 1)
	var hover := _make_button_style(Color("1c1720"), accent.lightened(0.1), 2)
	var pressed := _make_button_style(Color("2b1f12"), Color("e1ae58"), 2)
	var disabled := _make_button_style(Color("0a0910"), Color("211d28"), 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_hover_color", accent.lightened(0.18))
	button.add_theme_color_override("font_pressed_color", Color("f4d28b"))
	button.add_theme_color_override("font_disabled_color", Color("4a4552"))


func _make_button_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	return style


func _get_rarity_color(rarity: int) -> Color:
	match rarity:
		EquipmentRarity.UNCOMMON:
			return Color("82d49b")
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
