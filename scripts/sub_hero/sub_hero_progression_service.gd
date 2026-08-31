class_name SubHeroProgressionService
extends Resource

const MAX_ACTIVE_SLOTS: int = 3
const SubHeroCatalogResource = preload("res://scripts/sub_hero/sub_hero_catalog.gd")

signal collection_changed
signal active_slots_changed
signal sub_hero_updated(hero_id: StringName)
signal sub_hero_level_up(hero_id: StringName, new_level: int)

## Duplicate progression is intentionally modest so Equipment remains the
## primary early-game power source.
@export_range(1, 999, 1) var duplicates_per_level: int = 3
@export var owned_sub_heroes: Array[SubHeroInstance] = []
@export var active_slot_ids: Array[StringName] = [&"", &"", &""]


func _init() -> void:
	_normalize_active_slots()


## Adds a new owned instance or converts a duplicate into progression.
## Returns {is_new, hero_id, level, duplicate_count} for Shop/UI callers.
func add_instance(instance: SubHeroInstance) -> Dictionary:
	if instance == null or instance.hero_id.is_empty() or SubHeroCatalogResource.get_data(instance.hero_id) == null:
		return {"is_new": false, "hero_id": &"", "level": 0, "duplicate_count": 0}
	var existing := get_owned_instance(instance.hero_id)
	if existing == null:
		owned_sub_heroes.append(instance)
		collection_changed.emit()
		sub_hero_updated.emit(instance.hero_id)
		return {
			"is_new": true,
			"hero_id": instance.hero_id,
			"level": instance.level,
			"duplicate_count": instance.duplicate_count,
		}

	existing.add_duplicate(1)
	_consume_level_progression(existing)
	sub_hero_updated.emit(existing.hero_id)
	collection_changed.emit()
	return {
		"is_new": false,
		"hero_id": existing.hero_id,
		"level": existing.level,
		"duplicate_count": existing.duplicate_count,
	}


func get_owned_instance(hero_id: StringName) -> SubHeroInstance:
	for instance in owned_sub_heroes:
		if instance != null and instance.hero_id == hero_id:
			return instance
	return null


func get_owned_hero_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for instance in owned_sub_heroes:
		if instance != null and not instance.hero_id.is_empty():
			result.append(instance.hero_id)
	return result


func get_owned_count() -> int:
	return get_owned_hero_ids().size()


func assign_active_slot(slot_index: int, hero_id: StringName) -> bool:
	_normalize_active_slots()
	if slot_index < 0 or slot_index >= MAX_ACTIVE_SLOTS:
		return false
	if get_owned_instance(hero_id) == null:
		return false
	for index in MAX_ACTIVE_SLOTS:
		if index != slot_index and active_slot_ids[index] == hero_id:
			return false
	if active_slot_ids[slot_index] == hero_id:
		return true
	active_slot_ids[slot_index] = hero_id
	active_slots_changed.emit()
	return true


func remove_active_slot(slot_index: int) -> bool:
	_normalize_active_slots()
	if slot_index < 0 or slot_index >= MAX_ACTIVE_SLOTS or active_slot_ids[slot_index].is_empty():
		return false
	active_slot_ids[slot_index] = &""
	active_slots_changed.emit()
	return true


func get_active_instances() -> Array[SubHeroInstance]:
	_normalize_active_slots()
	var result: Array[SubHeroInstance] = []
	for hero_id in active_slot_ids:
		result.append(get_owned_instance(hero_id))
	return result


func get_active_entries() -> Array[Dictionary]:
	_normalize_active_slots()
	var result: Array[Dictionary] = []
	for hero_id in active_slot_ids:
		var instance := get_owned_instance(hero_id)
		result.append({
			"data": SubHeroCatalogResource.get_data(hero_id) if instance != null else null,
			"instance": instance,
		})
	return result


func get_duplicate_requirement(hero_id: StringName) -> int:
	var instance := get_owned_instance(hero_id)
	if instance == null:
		return 0
	return maxi(duplicates_per_level, 1)


func to_save_data() -> Dictionary:
	var owned_data: Array[Dictionary] = []
	for instance in owned_sub_heroes:
		if instance != null:
			owned_data.append(instance.to_save_data())
	var active_data: Array[String] = []
	for hero_id in active_slot_ids:
		active_data.append(String(hero_id))
	return {
		"owned_sub_heroes": owned_data,
		"active_slot_ids": active_data,
	}


## Restores ownership and active slots from the host save system's dictionary.
## Runtime combat timers are intentionally not part of this payload.
func load_save_data(save_data: Dictionary) -> void:
	owned_sub_heroes.clear()
	active_slot_ids.clear()
	for raw_instance in save_data.get("owned_sub_heroes", []):
		if raw_instance is Dictionary:
			var instance := SubHeroInstance.from_save_data(raw_instance)
			if instance != null and not instance.hero_id.is_empty() \
				and SubHeroCatalogResource.get_data(instance.hero_id) != null \
				and get_owned_instance(instance.hero_id) == null:
				owned_sub_heroes.append(instance)
	for raw_hero_id in save_data.get("active_slot_ids", []):
		active_slot_ids.append(StringName(str(raw_hero_id)))
	_normalize_active_slots()
	collection_changed.emit()
	active_slots_changed.emit()


func _consume_level_progression(instance: SubHeroInstance) -> void:
	var requirement: int = maxi(duplicates_per_level, 1)
	while instance.duplicate_count >= requirement:
		instance.duplicate_count -= requirement
		instance.level += 1
		sub_hero_level_up.emit(instance.hero_id, instance.level)


func _normalize_active_slots() -> void:
	while active_slot_ids.size() < MAX_ACTIVE_SLOTS:
		active_slot_ids.append(&"")
	if active_slot_ids.size() > MAX_ACTIVE_SLOTS:
		active_slot_ids.resize(MAX_ACTIVE_SLOTS)
	for index in MAX_ACTIVE_SLOTS:
		var hero_id: StringName = active_slot_ids[index]
		if hero_id.is_empty() or get_owned_instance(hero_id) == null:
			active_slot_ids[index] = &""
