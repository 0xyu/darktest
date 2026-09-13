class_name StorageInventory
extends Resource

## Player's warehouse / overflow storage. Slots are completely separate from
## the bag (EquipmentInventory): items can be parked here when the bag is full
## and withdrawn back into the bag later. Storage never equips items.

signal item_added(item: EquipmentInstance)
signal item_removed(item: EquipmentInstance)
signal item_selected(item: EquipmentInstance)
signal storage_changed

const DEFAULT_CAPACITY: int = 99999

@export_range(1, 999999, 1) var capacity: int = DEFAULT_CAPACITY
@export var items: Array[EquipmentInstance] = []

var selected_item: EquipmentInstance


func add_item(item: EquipmentInstance) -> bool:
	if item == null or has_item(item):
		return false
	if items.size() >= maxi(capacity, 1):
		return false
	item.is_equipped = false
	items.append(item)
	item_added.emit(item)
	storage_changed.emit()
	return true


func add_items(new_items: Array[EquipmentInstance]) -> int:
	var added_count: int = 0
	for item in new_items:
		if add_item(item):
			added_count += 1
	return added_count


func has_item(item: EquipmentInstance) -> bool:
	return _find_item_index(item) >= 0


func remove_item(item: EquipmentInstance) -> bool:
	if item == null:
		return false
	var item_index: int = _find_item_index(item)
	if item_index < 0:
		return false
	var owned_item: EquipmentInstance = items[item_index]
	items.remove_at(item_index)
	if selected_item == owned_item:
		selected_item = null
		item_selected.emit(null)
	item_removed.emit(owned_item)
	storage_changed.emit()
	return true


## Replaces the whole warehouse with a restored one (see StageProgressSave).
##
## Storage never equips items, so every restored item lands unequipped whatever
## the payload claimed, and capacity is not enforced: a restored collection is
## not a fresh acquisition.
func restore_items(restored_items: Array[EquipmentInstance]) -> void:
	items.clear()
	selected_item = null
	for item in restored_items:
		if item == null:
			continue
		item.is_equipped = false
		items.append(item)
	storage_changed.emit()


func select_item(item: EquipmentInstance) -> bool:
	if item != null and not has_item(item):
		return false
	if item != null:
		item = items[_find_item_index(item)]
	if selected_item == item:
		return true
	selected_item = item
	item_selected.emit(selected_item)
	return true


func clear_selection() -> void:
	select_item(null)


func get_selected_item() -> EquipmentInstance:
	return selected_item


func get_items() -> Array[EquipmentInstance]:
	return items.duplicate()


func get_item_count() -> int:
	return items.size()


func get_remaining_capacity() -> int:
	return maxi(capacity, 1) - items.size()


func _find_item_index(item: EquipmentInstance) -> int:
	if item == null:
		return -1
	for index in items.size():
		var candidate: EquipmentInstance = items[index]
		if candidate == item or (candidate != null and candidate.instance_id != &"" and candidate.instance_id == item.instance_id):
			return index
	return -1
