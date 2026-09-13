class_name EquipmentInventory
extends Resource

## Owns the player's equipment collection and the item assigned to each slot.
## Equipped items remain in `items`, so unequipping never destroys ownership,
## but they do NOT occupy bag slots: bag capacity, bag listings, and slot
## filtering all count only non-equipped items (see [method get_bag_items]).
signal item_added(item: EquipmentInstance)
signal item_removed(item: EquipmentInstance)
signal item_selected(item: EquipmentInstance)
signal equipment_changed(slot: int, equipped_item: EquipmentInstance, previous_item: EquipmentInstance)
signal inventory_changed

const DEFAULT_CAPACITY: int = 10

@export_range(1, 999, 1) var capacity: int = DEFAULT_CAPACITY
@export var items: Array[EquipmentInstance] = []

var selected_item: EquipmentInstance
var _equipped_items: Dictionary = {}


func add_item(item: EquipmentInstance) -> bool:
	if item == null or has_item(item):
		return false
	if get_item_count() >= maxi(capacity, 1):
		return false
	item.is_equipped = false
	items.append(item)
	item_added.emit(item)
	inventory_changed.emit()
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
	if item == null or item.is_equipped:
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
	inventory_changed.emit()
	return true


func discard_item(item: EquipmentInstance) -> bool:
	return remove_item(item)


## Replaces the whole collection with a restored one (see StageProgressSave).
##
## Deliberately not add_item() in a loop: add_item() is an ACQUISITION — it
## enforces bag capacity and clears `is_equipped`, which would strip the loadout
## off every restored item. A restored collection is not a fresh pickup.
##
## Repair, not trust: only the first item per valid slot keeps `is_equipped`, so a
## hand-damaged payload can never leave two weapons equipped at once or mark a
## slot-less consumable as equipped. The equipped-slot cache is rebuilt from the
## restored flags, and one inventory_changed announces the new contents to every
## panel. Equipment stat bonuses are re-applied by the host through
## `PlayerController.set_equipment_inventory()`.
func restore_items(restored_items: Array[EquipmentInstance]) -> void:
	items.clear()
	_equipped_items.clear()
	selected_item = null
	var equipped_slots: Dictionary = {}
	for item in restored_items:
		if item == null:
			continue
		var slot: int = item.get_slot()
		if item.is_equipped and EquipmentSlot.is_valid(slot) and not equipped_slots.has(slot):
			equipped_slots[slot] = true
		else:
			item.is_equipped = false
		items.append(item)
	inventory_changed.emit()


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


## All owned items, including equipped ones (the ownership list). Equipped
## items still live here so unequipping never destroys ownership; use
## [method get_bag_items] for what the bag actually shows.
func get_items() -> Array[EquipmentInstance]:
	return items.duplicate()


## Items currently in the bag (everything except equipped items). The bag grid
## and bag capacity are based on this list.
func get_bag_items() -> Array[EquipmentInstance]:
	var result: Array[EquipmentInstance] = []
	for item in items:
		if item != null and not item.is_equipped:
			result.append(item)
	return result


## Number of bag slots in use. Equipped items live in equipment slots and do
## not count toward bag capacity.
func get_item_count() -> int:
	return get_bag_items().size()


func get_remaining_capacity() -> int:
	return maxi(capacity, 1) - get_item_count()


func get_items_for_slot(slot: int) -> Array[EquipmentInstance]:
	var result: Array[EquipmentInstance] = []
	if not EquipmentSlot.is_valid(slot):
		return result
	for item in items:
		if item != null and not item.is_equipped and item.get_slot() == slot:
			result.append(item)
	return result


func equip_item(item: EquipmentInstance) -> bool:
	if item == null or not has_item(item) or not EquipmentSlot.is_valid(item.get_slot()):
		return false
	var owned_item: EquipmentInstance = items[_find_item_index(item)]
	item = owned_item
	var slot: int = item.get_slot()
	var previous_item: EquipmentInstance = get_equipped_item(slot)
	if previous_item == item:
		return true
	if previous_item != null:
		previous_item.is_equipped = false
	item.is_equipped = true
	_equipped_items[slot] = item
	equipment_changed.emit(slot, item, previous_item)
	inventory_changed.emit()
	return true


func unequip_item(slot: int) -> EquipmentInstance:
	if not EquipmentSlot.is_valid(slot):
		return null
	var previous_item: EquipmentInstance = get_equipped_item(slot)
	if previous_item == null:
		return null
	previous_item.is_equipped = false
	_equipped_items.erase(slot)
	equipment_changed.emit(slot, null, previous_item)
	inventory_changed.emit()
	return previous_item


func unequip_item_instance(item: EquipmentInstance) -> bool:
	if item == null or not item.is_equipped:
		return false
	return unequip_item(item.get_slot()) == item


func get_equipped_item(slot: int) -> EquipmentInstance:
	if not EquipmentSlot.is_valid(slot):
		return null
	var equipped_variant: Variant = _equipped_items.get(slot)
	if equipped_variant is EquipmentInstance and has_item(equipped_variant as EquipmentInstance):
		return equipped_variant as EquipmentInstance
	for item in items:
		if item != null and item.is_equipped and item.get_slot() == slot:
			_equipped_items[slot] = item
			return item
	return null


func get_equipped_items() -> Array[EquipmentInstance]:
	var result: Array[EquipmentInstance] = []
	for slot in range(EquipmentSlot.WEAPON, EquipmentSlot.AMULET + 1):
		var item: EquipmentInstance = get_equipped_item(slot)
		if item != null:
			result.append(item)
	return result


func get_equipped_effects() -> Array[EquipmentEffect]:
	var result: Array[EquipmentEffect] = []
	for item in get_equipped_items():
		if item.definition == null or item.definition.unique_effect_id == &"":
			continue
		var effect: EquipmentEffect = EquipmentEffect.create_for_id(item.definition.unique_effect_id)
		if effect != null:
			result.append(effect)
	return result


func get_equipped_effect_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for effect in get_equipped_effects():
		result.append(effect.effect_id)
	return result


## Returns actual per-stat differences for a candidate and its slot's current item.
## This is the data foundation for the full comparison panel in a later phase.
func compare_item(item: EquipmentInstance, slot_override: int = -1) -> Dictionary:
	var comparison: EquipmentComparison = create_comparison(item, slot_override)
	if comparison == null:
		return {}
	return comparison.to_dictionary()


func get_item_comparison(item: EquipmentInstance) -> Dictionary:
	return compare_item(item)


func create_comparison(item: EquipmentInstance, slot_override: int = -1) -> EquipmentComparison:
	if item == null:
		return null
	var slot: int = item.get_slot() if slot_override < 0 else slot_override
	if not EquipmentSlot.is_valid(slot):
		return null
	return EquipmentComparison.new(item, get_equipped_item(slot), slot)


func get_stat_deltas(item: EquipmentInstance, current_item: EquipmentInstance) -> Dictionary:
	var comparison := EquipmentComparison.new(item, current_item, item.get_slot() if item != null else -1)
	return comparison.stat_deltas.duplicate()


func _find_item_index(item: EquipmentInstance) -> int:
	if item == null:
		return -1
	for index in items.size():
		var candidate: EquipmentInstance = items[index]
		if candidate == item or (candidate != null and candidate.instance_id != &"" and candidate.instance_id == item.instance_id):
			return index
	return -1
