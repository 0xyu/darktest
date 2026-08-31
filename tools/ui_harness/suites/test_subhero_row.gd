extends "res://tools/ui_harness/ui_harness_suite.gd"

const InstanceScript = preload("res://scripts/sub_hero/sub_hero_instance.gd")
const SKELETON_DATA_PATH := "res://resources/sub_heroes/common/SkeletonArcher.tres"


func _mount_row() -> Node:
	return await mount_scene("res://scenes/ui/SubHeroRow.tscn")


func test_scene_loads() -> void:
	var row := await _mount_row()
	expect(row != null, "SubHeroRow should instantiate")
	expect_eq(row.get_slot_count(), 3, "SubHeroRow should expose three fixed slots")


func test_empty_slots_are_visible() -> void:
	var row := await _mount_row()
	var slots: Node = row.get_node("Margin/Content/Slots")
	for index in 3:
		var slot: Node = slots.get_child(index)
		expect_eq(slot.get_node("Margin/Content/Details/NameLabel").text, "EMPTY SLOT", "empty slot %d label" % index)
		expect_eq(slot.get_node("Margin/Content/Details/QualityLabel").text, "UNASSIGNED", "empty slot %d quality" % index)


func test_data_binding() -> void:
	var row := await _mount_row()
	var data: Resource = load(SKELETON_DATA_PATH)
	var instance: Resource = InstanceScript.new(&"skeleton_archer", 3)
	expect(bool(row.call("set_slot", 1, data, instance)), "slot index should bind data")
	await flush_frames(1)
	var slot: Node = row.get_node("Margin/Content/Slots").get_child(1)
	expect_eq(slot.get_node("Margin/Content/Details/NameLabel").text, "Skeleton Archer", "slot displays hero name")
	expect_eq(slot.get_node("Margin/Content/Details/QualityLabel").text, "COMMON", "slot displays quality")
	expect_contains(slot.get_node("Margin/Content/Details/LevelLabel").text, "LV 3", "slot displays level")
	expect_eq(slot.get_bound_hero_id(), &"skeleton_archer", "slot keeps hero id for feedback")


func test_attack_feedback_routes_to_matching_slot() -> void:
	var row := await _mount_row()
	var data: Resource = load(SKELETON_DATA_PATH)
	var instance: Resource = InstanceScript.new(&"skeleton_archer", 1)
	row.call("set_slot", 0, data, instance)
	expect(bool(row.call("show_attack_feedback", &"skeleton_archer", 8)), "feedback should route by hero id")
	var feedback: Label = row.get_node("Margin/Content/Slots/SlotA/Margin/Content/Details/FeedbackLabel")
	expect_eq(feedback.text, "HIT  -8", "slot shows recent damage feedback")
	expect(not bool(row.call("show_attack_feedback", &"unknown", 5)), "unknown hero should not alter a slot")
