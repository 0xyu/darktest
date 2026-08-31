class_name EquipmentInventoryPanel
extends Control

## Portrait-first character & inventory panel modeled on the
## "game ui design/character-inventory-gui.png" mockup.
## The layout is built in code; frame/tab/icon art is sliced from the shared
## hud-sprite.jpg sheet. Item cells stay data-driven from EquipmentInventory,
## and the public select/equip/discard API is unchanged.
signal panel_closed

const HUD_TEXTURE: Texture2D = preload("res://assets/ui/hud-sprite.jpg")
const PORTRAIT_TEXTURE: Texture2D = preload("res://assets/characters/portraits/Avatar_ref.png")
const KNIGHT_TEXTURE: Texture2D = preload("res://assets/ui/inventory/Knight_equipment.png")

const ItemPopupScript = preload("res://scripts/ui/item_popup.gd")

const EQUIPMENT_ICON_BY_SLOT: Dictionary = {
	EquipmentSlot.WEAPON: preload("res://assets/items/icons/Icon_Eq_Weapon.png"),
	EquipmentSlot.HELMET: preload("res://assets/items/icons/Icon_Eq_Head.png"),
	EquipmentSlot.ARMOR: preload("res://assets/items/icons/Icon_Eq_Chest.png"),
	EquipmentSlot.GLOVES: preload("res://assets/items/icons/Icon_Eq_Glowes.png"),
	EquipmentSlot.BOOTS: preload("res://assets/items/icons/Icon_Eq_boots.png"),
	EquipmentSlot.RING: preload("res://assets/items/icons/Icon_Eq_ring.png"),
	EquipmentSlot.AMULET: preload("res://assets/items/icons/Icon_Eq_neck.png"),
}

## Atlas regions inside the 1200x800 hud-sprite.jpg sheet.
const REGION_PORTRAIT_RING := Rect2(5, 3, 165, 192)
const REGION_COIN := Rect2(178, 15, 46, 46)
const REGION_CLOSE := Rect2(394, 10, 60, 58)
const REGION_TAB_CHARACTER := Rect2(500, 100, 136, 52)
const REGION_TAB_EQUIPMENT := Rect2(638, 102, 120, 50)
const REGION_TAB_ITEMS := Rect2(760, 102, 120, 50)
const REGION_FRAME_BRONZE := Rect2(722, 500, 112, 100)
const REGION_FRAME_GREEN := Rect2(168, 150, 96, 96)
const REGION_FRAME_BLUE := Rect2(168, 256, 96, 96)
const REGION_FRAME_PURPLE := Rect2(168, 362, 96, 96)
const REGION_STAT_ATTACK := Rect2(318, 170, 145, 48)
const REGION_STAT_DEFENSE := Rect2(318, 224, 145, 48)
const REGION_STAT_HP := Rect2(318, 278, 145, 48)
const REGION_DETAILS_BUTTON := Rect2(304, 376, 170, 58)
const REGION_PEDESTAL := Rect2(328, 582, 274, 214)

const LEFT_SLOTS: Array[int] = [
	EquipmentSlot.WEAPON,
	EquipmentSlot.HELMET,
	EquipmentSlot.ARMOR,
	EquipmentSlot.GLOVES,
	EquipmentSlot.BOOTS,
]
const RIGHT_SLOTS: Array[int] = [EquipmentSlot.AMULET, EquipmentSlot.RING]

const COLOR_GOLD := Color("e8c465")
const COLOR_GOLD_BRIGHT := Color("f4d28b")
const COLOR_TEXT := Color("d8cfdf")
const COLOR_MUTED := Color("8f879d")
const COLOR_GREEN := Color("82d49b")
const COLOR_RED := Color("d46a78")

## Warehouse page size (items shown per page, 4 rows x 6 columns).
const STORAGE_PAGE_SIZE: int = 24

enum Tab { CHARACTER, EQUIPMENT, ITEMS }

## Clickable square cell painted from hud-sprite.jpg slices (frame + icon +
## corner text). Used for both equipment slots and bag items.
class InventoryCell extends Control:
	signal cell_pressed(cell: InventoryCell)

	const SHEET: Texture2D = preload("res://assets/ui/hud-sprite.jpg")

	var item: EquipmentInstance = null
	var icon: Texture2D = null
	var frame_region: Rect2 = Rect2()
	var frame_tint: Color = Color.WHITE
	var has_content: bool = false
	var selected: bool = false
	## Equipment slot this cell represents (only slot cells set this; item cells keep -1).
	var slot: int = -1
	## Highlight the cell as the currently-filtered equipment slot.
	var filter_active: bool = false
	var corner_text: String = ""
	var corner_color: Color = Color("82d49b")
	var _hover: bool = false

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			cell_pressed.emit(self)

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_MOUSE_ENTER:
				_hover = true
				queue_redraw()
			NOTIFICATION_MOUSE_EXIT:
				_hover = false
				queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var tint := frame_tint
		if not has_content:
			tint = Color(tint.r, tint.g, tint.b, 0.55)
		draw_texture_rect_region(SHEET, rect, frame_region, tint)
		if _hover:
			draw_rect(Rect2(3, 3, size.x - 6, size.y - 6), Color(1, 1, 1, 0.07))
		if icon != null:
			var icon_size := size * 0.62
			var icon_rect := Rect2((size - icon_size) * 0.5, icon_size)
			var icon_modulate := Color.WHITE if has_content else Color(1, 1, 1, 0.4)
			draw_texture_rect(icon, icon_rect, false, icon_modulate)
		elif item != null and item.is_consumable():
			_draw_potion(size)
		if corner_text != "":
			var font := get_theme_font(&"font", &"Label")
			draw_string(font, Vector2(size.x - 32, size.y - 8), corner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, corner_color)
		if selected:
			draw_rect(rect, Color("f2c15e"), false, 2.0)
		if filter_active:
			draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), Color("6cc6f0"), false, 2.0)

	## Simple potion bottle drawn for consumables (which have no slot icon).
	func _draw_potion(cell_size: Vector2) -> void:
		var body_rect := Rect2(cell_size.x * 0.28, cell_size.y * 0.32, cell_size.x * 0.44, cell_size.y * 0.46)
		var neck_rect := Rect2(cell_size.x * 0.42, cell_size.y * 0.18, cell_size.x * 0.16, cell_size.y * 0.16)
		draw_rect(neck_rect, Color(1, 1, 1, 0.28))
		draw_rect(body_rect, Color("d4697f"))
		var highlight := Rect2(body_rect.position + Vector2(5, 5), Vector2(body_rect.size.x * 0.22, body_rect.size.y * 0.26))
		draw_rect(highlight, Color(1, 1, 1, 0.4))


var _player: PlayerController
var _inventory: EquipmentInventory
var _selected_item: EquipmentInstance
var _refresh_scheduled: bool = false
var _active_tab: int = Tab.CHARACTER
## Equipment slot the item list is filtered to; -1 means no filter.
var _filter_slot: int = -1

# Header
var _header_power_label: Label
var _header_gold_label: Label
var _header_level_label: Label

# Tabs
var _tab_buttons: Array[TextureButton] = []

# Sections
var _character_section: Control
var _equipment_section: Control
var _equipment_grid: GridContainer
var _left_slot_column: VBoxContainer
var _right_slot_column: VBoxContainer
var _inventory_section: Control
var _inventory_body: VBoxContainer
var _inventory_grid: GridContainer
var _inventory_count_label: Label
var _filter_row: Control
var _filter_label: Label

# Storage (warehouse)
var _storage: StorageInventory
var _storage_count_label: Label
var _storage_grid: GridContainer
var _storage_selected_item: EquipmentInstance
var _storage_pager_row: HBoxContainer
var _storage_page_label: Label
var _storage_prev_button: Button
var _storage_next_button: Button
var _storage_page: int = 0

# Character stats
var _attack_value_label: Label
var _defense_value_label: Label
var _hp_value_label: Label
var _detailed_stats_box: Control
var _detailed_stats_labels: Dictionary = {}
var _details_toggle: TextureButton

# Item popup (modal dialog shown on item click)
var _item_popup: Control


func _ready() -> void:
	_build_ui()
	_set_tab(Tab.CHARACTER)
	_refresh()


func set_player(player: PlayerController) -> void:
	if _inventory != null:
		if _inventory.inventory_changed.is_connected(_on_inventory_changed):
			_inventory.inventory_changed.disconnect(_on_inventory_changed)
		if _inventory.item_selected.is_connected(_on_item_selected):
			_inventory.item_selected.disconnect(_on_item_selected)
	if _storage != null:
		if _storage.storage_changed.is_connected(_on_storage_changed):
			_storage.storage_changed.disconnect(_on_storage_changed)
	_player = player
	_inventory = _player.get_inventory() if _player != null else null
	_storage = _player.get_storage() if _player != null else null
	if _inventory != null:
		if not _inventory.inventory_changed.is_connected(_on_inventory_changed):
			_inventory.inventory_changed.connect(_on_inventory_changed)
		if not _inventory.item_selected.is_connected(_on_item_selected):
			_inventory.item_selected.connect(_on_item_selected)
	if _storage != null:
		if not _storage.storage_changed.is_connected(_on_storage_changed):
			_storage.storage_changed.connect(_on_storage_changed)
	_request_refresh()


func show_inventory() -> void:
	visible = true
	_request_refresh()


func hide_inventory() -> void:
	visible = false
	panel_closed.emit()


func toggle_inventory() -> void:
	if visible:
		hide_inventory()
	else:
		show_inventory()


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


func _process(_delta: float) -> void:
	if visible:
		_refresh_dynamic()


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


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.012, 0.01, 0.018, 0.92)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_full_rect(backdrop)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_add_full_rect(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	content.add_child(_build_header())
	content.add_child(_build_tab_row())

	# Character info and equipment stay fixed; only the item list scrolls.
	_character_section = _build_character_section()
	content.add_child(_character_section)

	_equipment_section = _build_equipment_section()
	content.add_child(_equipment_section)

	_inventory_section = _build_inventory_section()
	content.add_child(_inventory_section)

	# Modal item dialog sits on top of everything; hidden until an item click.
	_item_popup = ItemPopupScript.new()
	_item_popup.visible = false
	add_child(_item_popup)


func _add_full_rect(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(node)


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 92)
	header.add_theme_constant_override("separation", 10)

	# Portrait ring + avatar + level badge.
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(80, 92)
	header.add_child(portrait)

	var ring := TextureRect.new()
	ring.texture = _atlas(REGION_PORTRAIT_RING)
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	portrait.add_child(ring)

	var avatar := TextureRect.new()
	avatar.texture = PORTRAIT_TEXTURE
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.anchor_left = 0.5
	avatar.anchor_top = 0.42
	avatar.anchor_right = 0.5
	avatar.anchor_bottom = 0.42
	avatar.offset_left = -27
	avatar.offset_top = -30
	avatar.offset_right = 27
	avatar.offset_bottom = 26
	portrait.add_child(avatar)

	var badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("141018")
	badge_style.border_color = Color("c99b4a")
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(11)
	badge.add_theme_stylebox_override("panel", badge_style)
	badge.anchor_left = 0.5
	badge.anchor_top = 1.0
	badge.anchor_right = 0.5
	badge.anchor_bottom = 1.0
	badge.offset_left = -16
	badge.offset_top = -22
	badge.offset_right = 16
	badge.offset_bottom = 2
	portrait.add_child(badge)

	_header_level_label = Label.new()
	_header_level_label.text = "1"
	_header_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_level_label.add_theme_color_override("font_color", COLOR_GOLD_BRIGHT)
	_header_level_label.add_theme_font_size_override("font_size", 13)
	badge.add_child(_header_level_label)

	# Name + combat power block.
	var name_block := VBoxContainer.new()
	name_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_block.add_theme_constant_override("separation", 4)
	header.add_child(name_block)

	var class_label := Label.new()
	class_label.text = "战士"
	class_label.add_theme_color_override("font_color", COLOR_GOLD_BRIGHT)
	class_label.add_theme_font_size_override("font_size", 22)
	name_block.add_child(class_label)

	var power_row := HBoxContainer.new()
	power_row.add_theme_constant_override("separation", 5)
	name_block.add_child(power_row)

	var power_icon := TextureRect.new()
	power_icon.texture = _atlas(REGION_STAT_ATTACK)
	power_icon.custom_minimum_size = Vector2(20, 20)
	power_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	power_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	power_row.add_child(power_icon)

	_header_power_label = Label.new()
	_header_power_label.text = "0"
	_header_power_label.add_theme_color_override("font_color", COLOR_GOLD)
	_header_power_label.add_theme_font_size_override("font_size", 15)
	power_row.add_child(_header_power_label)

	# Gold block.
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	gold_row.alignment = BoxContainer.ALIGNMENT_END
	header.add_child(gold_row)

	var coin := TextureRect.new()
	coin.texture = _atlas(REGION_COIN)
	coin.custom_minimum_size = Vector2(30, 30)
	coin.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_row.add_child(coin)

	_header_gold_label = Label.new()
	_header_gold_label.text = "0"
	_header_gold_label.add_theme_color_override("font_color", COLOR_TEXT)
	_header_gold_label.add_theme_font_size_override("font_size", 16)
	gold_row.add_child(_header_gold_label)

	# Close button.
	var close_button := TextureButton.new()
	close_button.texture_normal = _atlas(REGION_CLOSE)
	close_button.custom_minimum_size = Vector2(46, 44)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(hide_inventory)
	header.add_child(close_button)

	return header


func _build_tab_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	var regions: Array[Rect2] = [REGION_TAB_CHARACTER, REGION_TAB_EQUIPMENT, REGION_TAB_ITEMS]
	for tab_index in regions.size():
		var button := TextureButton.new()
		button.texture_normal = _atlas(regions[tab_index])
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = Vector2(150, 52)
		button.pressed.connect(_set_tab.bind(tab_index))
		row.add_child(button)
		_tab_buttons.append(button)
	return row


func _set_tab(tab: int) -> void:
	_active_tab = tab
	if _character_section != null:
		_character_section.visible = tab == Tab.CHARACTER
	if _equipment_section != null:
		_equipment_section.visible = tab == Tab.EQUIPMENT
	if _inventory_section != null:
		_inventory_section.visible = tab != Tab.EQUIPMENT
	for index in _tab_buttons.size():
		var active: bool = index == tab
		_tab_buttons[index].modulate = Color(1.25, 1.1, 0.8) if active else Color(0.6, 0.57, 0.54)
	_request_refresh()


func _build_character_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	section.add_child(body)

	_left_slot_column = VBoxContainer.new()
	_left_slot_column.add_theme_constant_override("separation", 8)
	body.add_child(_left_slot_column)

	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(0, 330)
	body.add_child(stage)

	var pedestal := TextureRect.new()
	pedestal.texture = _atlas(REGION_PEDESTAL)
	pedestal.anchor_left = 0.5
	pedestal.anchor_right = 0.5
	pedestal.anchor_top = 1.0
	pedestal.anchor_bottom = 1.0
	pedestal.offset_left = -140
	pedestal.offset_right = 140
	pedestal.offset_top = -190
	pedestal.offset_bottom = 18
	stage.add_child(pedestal)

	var knight := TextureRect.new()
	knight.texture = KNIGHT_TEXTURE
	knight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	knight.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	knight.anchor_left = 0.5
	knight.anchor_top = 0.5
	knight.anchor_right = 0.5
	knight.anchor_bottom = 0.5
	knight.offset_left = -70
	knight.offset_top = -150
	knight.offset_right = 70
	knight.offset_bottom = 40
	stage.add_child(knight)

	_right_slot_column = VBoxContainer.new()
	_right_slot_column.add_theme_constant_override("separation", 8)
	body.add_child(_right_slot_column)

	# Primary stats row: attack / defense / life + detailed stats toggle.
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 14)
	section.add_child(stats_row)

	_attack_value_label = _build_stat_block(stats_row, REGION_STAT_ATTACK)
	_defense_value_label = _build_stat_block(stats_row, REGION_STAT_DEFENSE)
	_hp_value_label = _build_stat_block(stats_row, REGION_STAT_HP)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.add_child(spacer)

	_details_toggle = TextureButton.new()
	_details_toggle.texture_normal = _atlas(REGION_DETAILS_BUTTON)
	_details_toggle.custom_minimum_size = Vector2(150, 50)
	_details_toggle.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_details_toggle.size_flags_vertical = Control.SIZE_SHRINK_END
	_details_toggle.pressed.connect(_toggle_detailed_stats)
	stats_row.add_child(_details_toggle)

	_detailed_stats_box = _build_detailed_stats_box()
	_detailed_stats_box.visible = false
	section.add_child(_detailed_stats_box)

	return section


func _build_stat_block(parent: Control, region: Rect2) -> Label:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)

	var plate := TextureRect.new()
	plate.texture = _atlas(region)
	plate.custom_minimum_size = Vector2(132, 44)
	plate.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	block.add_child(plate)

	var value := Label.new()
	value.text = "0"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_color_override("font_color", COLOR_TEXT)
	value.add_theme_font_size_override("font_size", 17)
	block.add_child(value)
	return value


func _build_detailed_stats_box() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171320")
	style.border_color = Color("4a3a28")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(grid)

	var entries: Array[Array] = [
		["critical_chance", "暴击率"],
		["critical_damage", "暴击伤害"],
		["dodge", "闪避"],
		["life_steal", "吸血"],
		["movement", "移动"],
		["attack_range", "射程"],
	]
	for entry in entries:
		var label := Label.new()
		label.text = "%s 0" % entry[1]
		label.add_theme_color_override("font_color", COLOR_MUTED)
		label.add_theme_font_size_override("font_size", 13)
		grid.add_child(label)
		_detailed_stats_labels[entry[0]] = label
	return panel


func _build_equipment_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)

	var hint := Label.new()
	hint.text = "装备部位  •  点击已装备部位查看属性"
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	hint.add_theme_font_size_override("font_size", 12)
	section.add_child(hint)

	_equipment_grid = GridContainer.new()
	_equipment_grid.columns = 7
	_equipment_grid.add_theme_constant_override("h_separation", 6)
	_equipment_grid.add_theme_constant_override("v_separation", 6)
	section.add_child(_equipment_grid)
	return section


func _build_inventory_section() -> Control:
	var section := VBoxContainer.new()
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	section.add_child(header)

	var title := Label.new()
	title.text = "物品"
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 17)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_inventory_count_label = Label.new()
	_inventory_count_label.text = "0/0"
	_inventory_count_label.add_theme_color_override("font_color", COLOR_TEXT)
	_inventory_count_label.add_theme_font_size_override("font_size", 14)
	header.add_child(_inventory_count_label)

	_filter_row = _build_filter_row()
	section.add_child(_filter_row)

	# Only the item list scrolls; the character/equipment/details stay fixed.
	# The scroll body holds the bag grid followed by the separate warehouse grid.
	var item_scroll := ScrollContainer.new()
	item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(item_scroll)

	_inventory_body = VBoxContainer.new()
	_inventory_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_body.add_theme_constant_override("separation", 10)
	item_scroll.add_child(_inventory_body)

	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 6
	_inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_grid.add_theme_constant_override("h_separation", 8)
	_inventory_grid.add_theme_constant_override("v_separation", 8)
	_inventory_body.add_child(_inventory_grid)

	# Warehouse block: its own header, count, and grid — slots are separate
	# from the bag above.
	var storage_header := HBoxContainer.new()
	storage_header.add_theme_constant_override("separation", 8)
	_inventory_body.add_child(storage_header)

	var storage_title := Label.new()
	storage_title.text = "仓库"
	storage_title.add_theme_color_override("font_color", COLOR_GOLD)
	storage_title.add_theme_font_size_override("font_size", 17)
	storage_header.add_child(storage_title)

	var storage_spacer := Control.new()
	storage_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_header.add_child(storage_spacer)

	_storage_count_label = Label.new()
	_storage_count_label.text = "0/0"
	_storage_count_label.add_theme_color_override("font_color", COLOR_TEXT)
	_storage_count_label.add_theme_font_size_override("font_size", 14)
	storage_header.add_child(_storage_count_label)

	# Warehouse pagination: only shown when the storage spans multiple pages.
	_storage_pager_row = HBoxContainer.new()
	_storage_pager_row.add_theme_constant_override("separation", 8)
	_storage_pager_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_inventory_body.add_child(_storage_pager_row)

	_storage_prev_button = Button.new()
	_storage_prev_button.text = "◀ 上一页"
	_storage_prev_button.add_theme_font_size_override("font_size", 12)
	_storage_prev_button.add_theme_color_override("font_color", Color("c9bdb4"))
	_apply_button_style(_storage_prev_button, false)
	_storage_prev_button.pressed.connect(_on_storage_prev_pressed)
	_storage_pager_row.add_child(_storage_prev_button)

	_storage_page_label = Label.new()
	_storage_page_label.text = "第 1/1 页"
	_storage_page_label.custom_minimum_size = Vector2(80, 0)
	_storage_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storage_page_label.add_theme_color_override("font_color", COLOR_TEXT)
	_storage_page_label.add_theme_font_size_override("font_size", 12)
	_storage_pager_row.add_child(_storage_page_label)

	_storage_next_button = Button.new()
	_storage_next_button.text = "下一页 ▶"
	_storage_next_button.add_theme_font_size_override("font_size", 12)
	_storage_next_button.add_theme_color_override("font_color", Color("c9bdb4"))
	_apply_button_style(_storage_next_button, false)
	_storage_next_button.pressed.connect(_on_storage_next_pressed)
	_storage_pager_row.add_child(_storage_next_button)

	_storage_grid = GridContainer.new()
	_storage_grid.columns = 6
	_storage_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_grid.add_theme_constant_override("h_separation", 8)
	_storage_grid.add_theme_constant_override("v_separation", 8)
	_inventory_body.add_child(_storage_grid)
	return section


func _build_filter_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.visible = false

	_filter_label = Label.new()
	_filter_label.add_theme_color_override("font_color", COLOR_MUTED)
	_filter_label.add_theme_font_size_override("font_size", 12)
	row.add_child(_filter_label)

	var clear_button := Button.new()
	clear_button.text = "清除筛选"
	clear_button.add_theme_font_size_override("font_size", 11)
	clear_button.add_theme_color_override("font_color", Color("c9bdb4"))
	_apply_button_style(clear_button, false)
	clear_button.pressed.connect(_clear_filter)
	row.add_child(clear_button)
	return row


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if not is_node_ready():
		return
	_rebuild_slot_columns()
	_rebuild_equipment_grid()
	_rebuild_inventory_grid()
	_rebuild_storage_grid()
	_refresh_filter_row()
	_refresh_dynamic()


func _rebuild_slot_columns() -> void:
	_clear_grid(_left_slot_column)
	_clear_grid(_right_slot_column)
	for slot in LEFT_SLOTS:
		_left_slot_column.add_child(_create_slot_cell(slot, Vector2(80, 80)))
	for slot in RIGHT_SLOTS:
		_right_slot_column.add_child(_create_slot_cell(slot, Vector2(80, 80)))


func _rebuild_equipment_grid() -> void:
	_clear_grid(_equipment_grid)
	for slot in range(EquipmentSlot.WEAPON, EquipmentSlot.AMULET + 1):
		_equipment_grid.add_child(_create_slot_cell(slot, Vector2(88, 88)))


func _rebuild_inventory_grid() -> void:
	_clear_grid(_inventory_grid)
	if _inventory == null:
		_inventory_count_label.text = "0/0"
		return
	var filtering: bool = EquipmentSlot.is_valid(_filter_slot)
	var items: Array[EquipmentInstance] = (
		_inventory.get_items_for_slot(_filter_slot) if filtering else _inventory.get_bag_items()
	)
	_inventory_count_label.text = "%d/%d" % [items.size(), _inventory.capacity]
	if items.is_empty():
		var empty := Label.new()
		empty.custom_minimum_size = Vector2(0, 120)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.text = "该部位暂无可用装备" if filtering else "暂无战利品\n战斗掉落的装备会出现在这里"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("62596d"))
		empty.add_theme_font_size_override("font_size", 13)
		_inventory_grid.add_child(empty)
		return
	for item in items:
		_inventory_grid.add_child(_create_item_cell(item))


func _create_slot_cell(slot: int, cell_size: Vector2) -> InventoryCell:
	var item: EquipmentInstance = _inventory.get_equipped_item(slot) if _inventory != null else null
	var cell := InventoryCell.new()
	cell.custom_minimum_size = cell_size
	cell.item = item
	cell.icon = EQUIPMENT_ICON_BY_SLOT.get(slot) as Texture2D
	cell.has_content = item != null
	cell.selected = item != null and item == _selected_item
	if item != null:
		cell.frame_region = _frame_region_for(item.get_rarity())
		cell.frame_tint = _frame_tint_for(item.get_rarity())
		cell.corner_text = "+%d" % item.get_item_level()
		cell.tooltip_text = "%s  •  %s" % [item.get_display_name(), _format_item_details(item)]
	else:
		cell.frame_region = REGION_FRAME_BRONZE
		cell.tooltip_text = "空%s部位" % EquipmentSlot.get_display_name(slot)
	cell.slot = slot
	cell.filter_active = _filter_slot == slot
	cell.cell_pressed.connect(_on_slot_cell_pressed)
	return cell


func _create_item_cell(item: EquipmentInstance) -> InventoryCell:
	var cell := InventoryCell.new()
	cell.custom_minimum_size = Vector2(96, 96)
	cell.item = item
	cell.icon = EQUIPMENT_ICON_BY_SLOT.get(item.get_slot()) as Texture2D
	cell.has_content = true
	cell.selected = item == _selected_item
	cell.frame_region = _frame_region_for(item.get_rarity())
	cell.frame_tint = _frame_tint_for(item.get_rarity())
	cell.corner_text = "%d" % item.get_item_level()
	cell.corner_color = _get_rarity_color(item.get_rarity())
	cell.tooltip_text = "%s  •  %s" % [item.get_display_name(), _format_item_details(item)]
	cell.cell_pressed.connect(_on_item_cell_pressed)
	return cell


func _on_slot_cell_pressed(cell: InventoryCell) -> void:
	# Clicking a slot filters the item list to items equippable in it; clicking
	# the same slot again (or the clear button) removes the filter. A slot that
	# already holds an item also opens its popup so the equipped item can be
	# inspected.
	if cell.slot >= 0:
		_filter_slot = -1 if _filter_slot == cell.slot else cell.slot
	if cell.item != null:
		select_item(cell.item)
		_open_item_popup(cell.item)
	_request_refresh()


func _clear_filter() -> void:
	if _filter_slot >= 0:
		_filter_slot = -1
		_request_refresh()


func _refresh_filter_row() -> void:
	if _filter_row == null or _filter_label == null:
		return
	var filtering: bool = EquipmentSlot.is_valid(_filter_slot)
	_filter_row.visible = filtering
	if filtering:
		_filter_label.text = "筛选部位: %s   •  再次点击该部位或清除筛选以查看全部物品" % EquipmentSlot.get_display_name(_filter_slot)


func _on_item_cell_pressed(cell: InventoryCell) -> void:
	if cell.item != null:
		select_item(cell.item)
		_open_item_popup(cell.item)


func _rebuild_storage_grid() -> void:
	_clear_grid(_storage_grid)
	if _player == null:
		_storage_count_label.text = "0/0"
		_update_storage_pager(0)
		return
	var storage: StorageInventory = _player.get_storage()
	if _storage_selected_item != null and not storage.has_item(_storage_selected_item):
		_storage_selected_item = null
	var items: Array[EquipmentInstance] = storage.get_items()
	_storage_count_label.text = "%d/%d" % [items.size(), storage.capacity]
	var total_pages: int = maxi(ceili(float(items.size()) / float(STORAGE_PAGE_SIZE)), 1)
	_storage_page = clampi(_storage_page, 0, total_pages - 1)
	if items.is_empty():
		var empty := Label.new()
		empty.custom_minimum_size = Vector2(0, 60)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.text = "仓库是空的\n物品栏满时掉落的装备会自动存入这里"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("62596d"))
		empty.add_theme_font_size_override("font_size", 13)
		_storage_grid.add_child(empty)
		_update_storage_pager(1)
		return
	var start_index: int = _storage_page * STORAGE_PAGE_SIZE
	var end_index: int = mini(start_index + STORAGE_PAGE_SIZE, items.size())
	for index in range(start_index, end_index):
		_storage_grid.add_child(_create_storage_cell(items[index]))
	_update_storage_pager(total_pages)


## Shows/hides the warehouse pager and syncs the page label / button states.
func _update_storage_pager(total_pages: int) -> void:
	if _storage_pager_row == null:
		return
	var has_pages: bool = total_pages > 1
	_storage_pager_row.visible = has_pages
	if not has_pages:
		return
	_storage_page_label.text = "第 %d/%d 页" % [_storage_page + 1, total_pages]
	_storage_prev_button.disabled = _storage_page <= 0
	_storage_next_button.disabled = _storage_page >= total_pages - 1


func _on_storage_prev_pressed() -> void:
	if _storage_page <= 0:
		return
	_storage_page -= 1
	_request_refresh()


func _on_storage_next_pressed() -> void:
	_storage_page += 1
	_request_refresh()


func _create_storage_cell(item: EquipmentInstance) -> InventoryCell:
	var cell := InventoryCell.new()
	cell.custom_minimum_size = Vector2(96, 96)
	cell.item = item
	cell.icon = EQUIPMENT_ICON_BY_SLOT.get(item.get_slot()) as Texture2D
	cell.has_content = true
	cell.selected = item == _storage_selected_item
	cell.frame_region = _frame_region_for(item.get_rarity())
	cell.frame_tint = _frame_tint_for(item.get_rarity())
	cell.corner_text = "%d" % item.get_item_level()
	cell.corner_color = _get_rarity_color(item.get_rarity())
	cell.tooltip_text = "%s  •  %s" % [item.get_display_name(), _format_item_details(item)]
	cell.cell_pressed.connect(_on_storage_cell_pressed)
	return cell


func _on_storage_cell_pressed(cell: InventoryCell) -> void:
	if cell.item != null:
		_storage_selected_item = cell.item
		_open_item_popup(cell.item, true)


func _on_storage_changed() -> void:
	if _storage_selected_item != null and _player != null and not _player.get_storage().has_item(_storage_selected_item):
		_storage_selected_item = null
	_request_refresh()


func _open_item_popup(item: EquipmentInstance, from_storage: bool = false) -> void:
	if item == null or _player == null or _item_popup == null:
		return
	_item_popup.call("open_for", _player, item, from_storage)


func _toggle_detailed_stats() -> void:
	_detailed_stats_box.visible = not _detailed_stats_box.visible


func _refresh_dynamic() -> void:
	if _player == null:
		return
	var stats: PlayerStats = _player.player_stats
	var progression: PlayerProgression = _player.player_progression
	if progression != null:
		_header_gold_label.text = _format_number(progression.gold)
		_header_level_label.text = str(maxi(progression.level, 1))
	if stats == null:
		return
	_header_power_label.text = _format_number(_get_combat_power(stats))
	_attack_value_label.text = str(stats.attack)
	_defense_value_label.text = str(stats.defense)
	_hp_value_label.text = _format_number(stats.max_hp)
	_detailed_stats_labels["critical_chance"].text = "暴击率 %.0f%%" % (stats.critical_chance * 100.0)
	_detailed_stats_labels["critical_damage"].text = "暴击伤害 %.0f%%" % (stats.critical_damage * 100.0)
	_detailed_stats_labels["dodge"].text = "闪避 %.0f%%" % (stats.dodge * 100.0)
	_detailed_stats_labels["life_steal"].text = "吸血 %.0f%%" % (stats.life_steal * 100.0)
	_detailed_stats_labels["movement"].text = "移动 %d" % stats.movement_points
	_detailed_stats_labels["attack_range"].text = "射程 %d" % stats.attack_range


func _get_combat_power(stats: PlayerStats) -> int:
	return roundi(stats.attack * 2.0 + stats.defense * 2.0 + stats.max_hp * 0.5)


# ---------------------------------------------------------------------------
# Formatting & styling helpers
# ---------------------------------------------------------------------------

func _format_item_details(item: EquipmentInstance) -> String:
	if item.is_consumable():
		return "消耗品  •  物品等级 %d\n回复最大生命的 %.0f%%" % [item.get_item_level(), item.get_heal_ratio() * 100.0]
	var lines: Array[String] = [
		"%s  •  物品等级 %d" % [EquipmentSlot.get_display_name(item.get_slot()), item.get_item_level()],
	]
	for affix in item.affixes:
		if affix == null:
			continue
		var value_text: String = "%+.0f%%" % (affix.value * 100.0) if affix.is_percentage else "%+d" % roundi(affix.value)
		lines.append("%s  %s" % [affix.display_name, value_text])
	return "\n".join(lines)


func _format_number(value: int) -> String:
	var text_value: String = str(maxi(value, 0))
	var formatted: String = ""
	while text_value.length() > 3:
		formatted = "," + text_value.substr(text_value.length() - 3, 3) + formatted
		text_value = text_value.substr(0, text_value.length() - 3)
	return text_value + formatted


func _frame_region_for(rarity: int) -> Rect2:
	match rarity:
		EquipmentRarity.UNCOMMON:
			return REGION_FRAME_GREEN
		EquipmentRarity.RARE:
			return REGION_FRAME_BLUE
		EquipmentRarity.EPIC:
			return REGION_FRAME_PURPLE
		_:
			return REGION_FRAME_BRONZE


func _frame_tint_for(rarity: int) -> Color:
	match rarity:
		EquipmentRarity.LEGENDARY:
			return Color(1.3, 1.05, 0.55)
		EquipmentRarity.MYTHIC:
			return Color(1.25, 0.6, 0.95)
		_:
			return Color.WHITE


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


func _clear_grid(grid: Control) -> void:
	if grid == null:
		return
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()


func _atlas(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = HUD_TEXTURE
	texture.region = region
	return texture
