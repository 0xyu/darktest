class_name EquipmentInventoryPanel
extends Control

## Portrait-first equipment management panel for the existing inventory model.
## Item buttons are generated from EquipmentInventory so this UI stays data-driven.
signal panel_closed

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


func _ready() -> void:
	_close_button.pressed.connect(hide_inventory)
	_equip_button.pressed.connect(equip_selected_item)
	_discard_button.pressed.connect(discard_selected_item)
	_equipped_grid.columns = 4
	_inventory_grid.columns = 4
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
	_refresh()


func show_inventory() -> void:
	visible = true
	_refresh()


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
		_refresh()
	return selected


func get_selected_item() -> EquipmentInstance:
	return _selected_item


func equip_selected_item() -> bool:
	if _inventory == null or _selected_item == null:
		return false
	var equipped: bool = _player != null and _player.equip_item(_selected_item)
	if equipped:
		_refresh()
	return equipped


func discard_selected_item() -> bool:
	if _inventory == null or _selected_item == null:
		return false
	var discarded: bool = _player != null and _player.discard_item(_selected_item)
	if discarded:
		_selected_item = null
		_refresh()
	return discarded


func _on_inventory_changed() -> void:
	if _selected_item != null and not _inventory.has_item(_selected_item):
		_selected_item = null
	_refresh()


func _on_item_selected(item: EquipmentInstance) -> void:
	_selected_item = item
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
	for item in _inventory.get_items():
		_inventory_grid.add_child(_create_inventory_button(item))
	_refresh_details()


func _create_equipped_button(slot: int, item: EquipmentInstance) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.text = _format_slot_button_text(slot, item)
	button.tooltip_text = item.get_display_name() if item != null else "Empty %s slot" % EquipmentSlot.get_display_name(slot)
	button.add_theme_color_override("font_color", _get_rarity_color(item.get_rarity()) if item != null else Color("8f879d"))
	button.pressed.connect(_on_equipped_slot_pressed.bind(item))
	button.button_pressed = item != null and item == _selected_item
	return button


func _create_inventory_button(item: EquipmentInstance) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 62)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.text = _format_inventory_button_text(item)
	button.tooltip_text = _format_item_details(item)
	button.add_theme_color_override("font_color", _get_rarity_color(item.get_rarity()))
	button.pressed.connect(_on_inventory_item_pressed.bind(item))
	button.button_pressed = item == _selected_item
	return button


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
	return "%s\n%s" % [slot_name, item.get_display_name()]


func _format_inventory_button_text(item: EquipmentInstance) -> String:
	var rarity_name: String = EquipmentRarity.get_display_name(item.get_rarity()).to_upper()
	return "%s\n%s" % [rarity_name.substr(0, 3), item.get_display_name()]


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
		child.free()


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
