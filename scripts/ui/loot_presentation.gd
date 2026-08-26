class_name LootPresentation
extends Control

## Presents dropped equipment without pausing combat or auto progression.
## Common drops are intentionally brief; Legendary/Mythic drops get a longer,
## brighter reveal and a pulse so the reward hierarchy is immediately clear.

@export_range(0.05, 2.0, 0.05) var presentation_speed_scale: float = 1.0

@onready var _panel: PanelContainer = %LootPanel
@onready var _burst_label: Label = %LootBurst
@onready var _title_label: Label = %LootTitle
@onready var _rarity_label: Label = %LootRarity
@onready var _item_label: Label = %LootItem
@onready var _details_label: Label = %LootDetails
@onready var _best_label: Label = %LootBest

var _pending_entries: Array[Dictionary] = []
var _is_presenting: bool = false
var _current_item: EquipmentInstance
var _current_is_new_best: bool = false
var _last_revealed_item: EquipmentInstance
var _last_revealed_was_new_best: bool = false
var _active_tween: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func present_loot(
	items: Array[EquipmentInstance],
	new_best_items: Array[EquipmentInstance] = [],
	_source_name: String = ""
) -> void:
	for item in items:
		if item == null:
			continue
		_pending_entries.append({
			"item": item,
			"is_new_best": new_best_items.has(item),
		})
	if not _is_presenting:
		_show_next()


func get_pending_count() -> int:
	return _pending_entries.size()


func is_presenting() -> bool:
	return _is_presenting


func get_current_item() -> EquipmentInstance:
	return _current_item


func get_last_revealed_item() -> EquipmentInstance:
	return _last_revealed_item


func was_last_revealed_new_best() -> bool:
	return _last_revealed_was_new_best


func _show_next() -> void:
	if _pending_entries.is_empty():
		_is_presenting = false
		_current_item = null
		visible = false
		return
	var entry: Dictionary = _pending_entries.pop_front()
	_current_item = entry.get("item") as EquipmentInstance
	_current_is_new_best = bool(entry.get("is_new_best", false))
	_is_presenting = true
	visible = true
	_populate_reveal_state()
	_play_reveal()


func _populate_reveal_state() -> void:
	if _current_item == null:
		return
	var rarity: int = _current_item.get_rarity()
	var rarity_name: String = EquipmentRarity.get_display_name(rarity).to_upper()
	var rarity_color: Color = _get_rarity_color(rarity)
	_title_label.text = "LOOT FOUND"
	_rarity_label.text = rarity_name
	_rarity_label.modulate = rarity_color
	_item_label.text = _current_item.get_display_name()
	_item_label.modulate = rarity_color.lightened(0.18)
	_details_label.text = _format_item_details(_current_item)
	_best_label.text = "NEW BEST ITEM" if _current_is_new_best else ""
	_best_label.visible = _current_is_new_best
	_best_label.modulate = Color("f2d27a")
	_burst_label.modulate = rarity_color
	_burst_label.text = "✦" if rarity < EquipmentRarity.LEGENDARY else "✦  ✦  ✦"
	_apply_panel_style(rarity, rarity_color)
	_panel.pivot_offset = _panel.size * 0.5


func _play_reveal() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_panel.scale = Vector2(0.82, 0.82)
	_burst_label.scale = Vector2(0.55, 0.55)
	_burst_label.modulate.a = 0.0
	_active_tween = create_tween().set_parallel(true)
	_active_tween.tween_property(_panel, "modulate:a", 1.0, _get_reveal_duration())
	_active_tween.tween_property(_panel, "scale", Vector2.ONE, _get_reveal_duration()).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_burst_label, "modulate:a", 1.0, _get_reveal_duration() * 0.75)
	_active_tween.tween_property(_burst_label, "scale", Vector2.ONE, _get_reveal_duration()).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _active_tween.finished
	if not is_inside_tree() or _current_item == null:
		return
	_last_revealed_item = _current_item
	_last_revealed_was_new_best = _current_is_new_best
	if _current_item.get_rarity() >= EquipmentRarity.LEGENDARY:
		_play_high_rarity_pulse()
	var hold_time: float = _get_hold_duration() * maxf(presentation_speed_scale, 0.05)
	await get_tree().create_timer(hold_time).timeout
	if not is_inside_tree():
		return
	_hide_current()


func _hide_current() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.tween_property(_panel, "modulate:a", 0.0, 0.12 * maxf(presentation_speed_scale, 0.05))
	_active_tween.tween_callback(_show_next)


func _play_high_rarity_pulse() -> void:
	var pulse := create_tween().set_loops(3)
	pulse.tween_property(_panel, "modulate", Color(1.18, 1.12, 0.92, 1.0), 0.22)
	pulse.tween_property(_panel, "modulate", Color.WHITE, 0.22)


func _apply_panel_style(rarity: int, rarity_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("100e1a", 0.98)
	style.border_color = rarity_color
	var border_width: int = 2 if rarity < EquipmentRarity.LEGENDARY else 3
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(rarity_color, 0.38 if rarity < EquipmentRarity.LEGENDARY else 0.72)
	style.shadow_size = 6 if rarity < EquipmentRarity.LEGENDARY else 14
	_panel.add_theme_stylebox_override("panel", style)


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


func _get_reveal_duration() -> float:
	if _current_item == null:
		return 0.12
	var rarity: int = _current_item.get_rarity()
	return 0.12 if rarity < EquipmentRarity.RARE else (0.22 if rarity < EquipmentRarity.LEGENDARY else 0.38)


func _get_hold_duration() -> float:
	if _current_item == null:
		return 0.5
	match _current_item.get_rarity():
		EquipmentRarity.COMMON:
			return 0.55
		EquipmentRarity.UNCOMMON:
			return 0.7
		EquipmentRarity.RARE:
			return 0.95
		EquipmentRarity.EPIC:
			return 1.2
		EquipmentRarity.LEGENDARY:
			return 1.8
		EquipmentRarity.MYTHIC:
			return 2.2
		_:
			return 0.7
