extends "res://tools/ui_harness/ui_harness_suite.gd"

const UIFixtureScript := preload("res://tests/fixtures/ui_fixture.gd")

var _player: PlayerController
var _panel: Control


func _mount_panel() -> void:
	_player = PlayerController.new()
	track_node(_player)
	_player.player_progression = UIFixtureScript.create_player_progression(1, 0)
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


## RESET SAVE is destructive, so it is checked against the harness's redirected
## save path — a run never reads or writes a real player save in user://.
func test_reset_save_clears_persisted_data() -> void:
	await _mount_panel()
	var labels: Array[String] = []
	for button in _panel.find_children("*", "Button", true, false):
		labels.append((button as Button).text)
	expect(labels.has("RESET SAVE"), "DEV panel exposes a RESET SAVE button")

	var path: String = StageProgressSaveScript.default_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"version\": 1, \"current_stage_number\": 7}")
	file.close()
	expect(StageProgressSaveScript.save_exists_at(path), "precondition: a save file exists before the reset")

	expect(bool(_panel.call("dev_reset_save")), "DEV reset save should report the saved data was cleared")
	expect(not StageProgressSaveScript.save_exists_at(path), "DEV reset save should delete the save file")
