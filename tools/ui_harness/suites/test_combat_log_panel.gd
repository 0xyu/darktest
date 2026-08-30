extends "res://tools/ui_harness/ui_harness_suite.gd"

## Headless suite for the CombatLogPanel (res://scenes/ui/CombatLogPanel.tscn).
##
## Verifies scene loading, yellow/white highlight rendering, the visible-entry
## cap, locale switching, and clear().

const PANEL_SCENE := preload("res://scenes/ui/CombatLogPanel.tscn")
const PANEL_SCRIPT := preload("res://scripts/ui/combat_log_panel.gd")

var _panel: Control


func suite_name() -> String:
	return "test_combat_log_panel"


func _mount_panel() -> void:
	var mounted: Node = await mount_scene("res://scenes/ui/CombatLogPanel.tscn")
	_panel = mounted as Control


func test_scene_loads() -> void:
	expect(PANEL_SCENE != null, "combat log panel scene loads")
	if PANEL_SCENE == null:
		return
	var instance := PANEL_SCENE.instantiate()
	expect(instance is PanelContainer, "panel root is a PanelContainer")
	expect(instance.get_script() == PANEL_SCRIPT, "panel root uses combat_log_panel.gd")
	instance.free()


func test_append_increases_count() -> void:
	await _mount_panel()
	_panel.call("append", "log.stage_start", {"stage": 1})
	expect_eq(_panel.call("get_entry_count"), 1, "one entry after append")
	_panel.call("append", "log.gold_gained", {"amount": 50})
	expect_eq(_panel.call("get_entry_count"), 2, "two entries after two appends")


func test_name_highlighted_white() -> void:
	await _mount_panel()
	_panel.call("append", "log.kill_exp", {"name": "Training Wraith", "amount": 200})
	var latest: String = _panel.call("get_latest_text")
	expect_contains(latest, "[color=#ffffff]", "name wrapped in white color tag")
	expect_contains(latest, "【", "name wrapped in full-width brackets")
	expect_contains(latest, "Killed", "english template rendered")
	expect_contains(latest, "EXP +200", "exp amount rendered")


func test_visible_entries_capped() -> void:
	await _mount_panel()
	for i in range(10):
		_panel.call("append", "log.gold_gained", {"amount": i})
	expect_eq(_panel.call("get_entry_count"), 10, "history keeps all 10")
	var visible: Array = _panel.call("get_visible_entries")
	expect_eq(visible.size(), 5, "only 5 visible entries")
	expect_contains(visible[visible.size() - 1], "Gold +9", "newest entry is visible")


func test_locale_switch_changes_language() -> void:
	await _mount_panel()
	_panel.call("append", "log.kill_exp", {"name": "Training Wraith", "amount": 200})
	_panel.call("set_locale", "zh_Hant")
	var latest: String = _panel.call("get_latest_text")
	expect_contains(latest, "擊殺了", "zh_Hant kill verb rendered")
	expect_contains(latest, "經驗值", "zh_Hant exp label rendered")
	expect_contains(latest, "訓練幽魂", "enemy name localized to zh_Hant")
	expect_eq(_panel.call("get_locale"), "zh_Hant", "locale stored")


func test_clear_empties_log() -> void:
	await _mount_panel()
	_panel.call("append", "log.gold_gained", {"amount": 5})
	_panel.call("clear")
	expect_eq(_panel.call("get_entry_count"), 0, "clear empties history")
	expect_eq(_panel.call("get_visible_entries").size(), 0, "no visible entries after clear")


func test_unknown_key_does_not_crash() -> void:
	await _mount_panel()
	_panel.call("append", "log.missing_key", {})
	expect_eq(_panel.call("get_entry_count"), 1, "unknown key still creates an entry")
	expect_eq(_panel.call("get_latest_text"), "log.missing_key", "unknown key echoes the key as text")
