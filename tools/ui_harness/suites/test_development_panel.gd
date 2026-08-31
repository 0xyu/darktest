extends "res://tools/ui_harness/ui_harness_suite.gd"

const UIFixtureScript := preload("res://tests/fixtures/ui_fixture.gd")

var _player: PlayerController
var _panel: Control


func _mount_panel() -> void:
	_player = PlayerController.new()
	track_node(_player)
	_player.player_progression = UIFixtureScript.create_player_progression(1, 0, 1)
	_panel = await mount_scene("res://scenes/ui/DevelopmentPanel.tscn")
	_panel.call("set_player", _player)
	await flush_frames(1)


func test_direct_subhero_summon_api() -> void:
	await _mount_panel()
	expect(_panel.has_method("dev_summon_sub_hero"), "DEV panel exposes direct Sub Hero summon API")
	var result: Dictionary = _panel.call("dev_summon_sub_hero", &"skeleton_archer")
	expect(bool(result.get("success")), "direct DEV summon should succeed")
	expect(bool(result.get("is_new")), "first direct DEV summon should be new")
	expect_eq(_player.player_progression.gold, 0, "direct DEV summon should not spend Gold")
	expect_eq(_player.get_sub_hero_progression().get_owned_count(), 1, "direct DEV summon should add ownership")

	var duplicate: Dictionary = _panel.call("dev_summon_sub_hero", &"skeleton_archer")
	expect(not bool(duplicate.get("is_new")), "repeated direct DEV summon should be a duplicate")
	expect_eq(int(duplicate.get("duplicate_count")), 1, "duplicate should use normal progression conversion")
