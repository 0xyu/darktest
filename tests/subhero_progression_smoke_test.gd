extends SceneTree

const ServiceScript = preload("res://scripts/sub_hero/sub_hero_progression_service.gd")
const InstanceScript = preload("res://scripts/sub_hero/sub_hero_instance.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = ServiceScript.new()
	var first_result: Dictionary = service.add_instance(InstanceScript.new(&"skeleton_archer", 1))
	_expect(bool(first_result.get("is_new")), "first summon should create an owned Sub Hero")
	_expect(service.get_owned_count() == 1, "owned collection should contain one hero")

	for _duplicate_index in 3:
		service.add_instance(InstanceScript.new(&"skeleton_archer", 1))
	var skeleton = service.get_owned_instance(&"skeleton_archer")
	_expect(skeleton.level == 2, "three duplicates should raise the hero to level two")
	_expect(skeleton.duplicate_count == 0, "consumed duplicates should reset progression count")

	service.add_instance(InstanceScript.new(&"goblin_gunner", 1))
	_expect(service.assign_active_slot(0, &"skeleton_archer"), "owned hero should assign to slot zero")
	_expect(service.assign_active_slot(1, &"goblin_gunner"), "second owned hero should assign to slot one")
	_expect(not service.assign_active_slot(2, &"skeleton_archer"), "one hero cannot occupy two active slots")
	_expect(not service.assign_active_slot(2, &"unknown"), "unknown hero cannot be assigned")
	_expect(service.remove_active_slot(1), "assigned slot should be removable")
	_expect(service.active_slot_ids[1].is_empty(), "removed slot should be empty")

	var restored = ServiceScript.new()
	restored.load_save_data(service.to_save_data())
	_expect(restored.get_owned_count() == 2, "owned collection should round-trip through save data")
	_expect(restored.get_owned_instance(&"skeleton_archer").level == 2, "hero level should round-trip")
	_expect(restored.active_slot_ids[0] == &"skeleton_archer", "active slot should round-trip")
	_expect(restored.active_slot_ids[1].is_empty(), "empty active slot should round-trip")
	_expect(restored.get_active_entries()[0].get("data") != null, "active entry should resolve its static data")

	if _failures.is_empty():
		print("Sub Hero progression smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
