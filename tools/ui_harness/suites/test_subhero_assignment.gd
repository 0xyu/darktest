extends "res://tools/ui_harness/ui_harness_suite.gd"

const InstanceScript := preload("res://scripts/sub_hero/sub_hero_instance.gd")

var _player: PlayerController
var _panel: Control


func _mount_panel() -> void:
	_player = PlayerController.new()
	track_node(_player)
	_player.add_sub_hero(InstanceScript.new(&"skeleton_archer", 1))
	_panel = await mount_scene("res://scenes/ui/SubHeroAssignmentPanel.tscn")
	_panel.call("set_player", _player)
	_panel.call("show_for_slot", 0)
	await flush_frames(1)


func test_owned_subhero_can_be_assigned() -> void:
	await _mount_panel()
	var list: VBoxContainer = _panel.get("_list")
	expect(list.get_child_count() == 1, "assignment panel should list the owned Sub Hero")
	if list.get_child_count() == 0:
		return
	var hero_button: Button = list.get_child(0) as Button
	expect(hero_button != null, "owned Sub Hero entry should be a button")
	if hero_button == null:
		return
	hero_button.pressed.emit()
	await flush_frames(1)
	expect_eq(_player.get_sub_hero_progression().active_slot_ids[0], &"skeleton_archer", "selecting an owned hero assigns the requested slot")
	expect(not _panel.visible, "assignment panel closes after assignment")
