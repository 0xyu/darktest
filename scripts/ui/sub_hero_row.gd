extends PanelContainer

const MAX_SLOTS: int = 3

signal slot_selected(slot_index: int)

@onready var _slots: HBoxContainer = $Margin/Content/Slots


func _ready() -> void:
	for index in _slots.get_child_count():
		var slot: Node = _slots.get_child(index)
		if slot.has_signal("pressed"):
			slot.pressed.connect(_on_slot_pressed.bind(index))


func _on_slot_pressed(slot_index: int) -> void:
	slot_selected.emit(slot_index)


func set_slots(entries: Array[Dictionary]) -> void:
	for index in MAX_SLOTS:
		var slot: Node = _slots.get_child(index)
		var entry: Dictionary = entries[index] if index < entries.size() else {}
		slot.call("set_slot", entry.get("data") as Resource, entry.get("instance") as Resource)


func set_slot(index: int, data: Resource, instance: Resource) -> bool:
	if index < 0 or index >= _slots.get_child_count():
		return false
	_slots.get_child(index).call("set_slot", data, instance)
	return true


func clear_slots() -> void:
	for slot in _slots.get_children():
		slot.call("clear_slot")


func show_attack_feedback(hero_id: StringName, damage: int) -> bool:
	for slot in _slots.get_children():
		if slot.call("get_bound_hero_id") == hero_id:
			slot.call("show_attack_feedback", damage)
			return true
	return false


func start_cooldown(hero_id: StringName, duration: float) -> bool:
	for slot in _slots.get_children():
		if slot.call("get_bound_hero_id") == hero_id:
			slot.call("start_cooldown", duration)
			return true
	return false


func reset_cooldowns() -> void:
	for slot in _slots.get_children():
		slot.call("reset_cooldown")


func get_slot_center(hero_id: StringName) -> Vector2:
	for slot in _slots.get_children():
		if slot.call("get_bound_hero_id") == hero_id:
			return (slot as Control).get_global_rect().get_center()
	return Vector2.ZERO


func get_slot_count() -> int:
	return _slots.get_child_count()
