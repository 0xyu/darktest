extends PanelContainer

const MAX_SLOTS: int = 3

@onready var _slots: HBoxContainer = $Margin/Content/Slots


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


func get_slot_count() -> int:
	return _slots.get_child_count()
