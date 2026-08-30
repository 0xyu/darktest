extends "res://tools/ui_harness/ui_harness_suite.gd"

## Headless suite for GameLocale (res://scripts/systems/game_locale.gd).
##
## Verifies the en / zh_Hant translation table, named-placeholder formatting,
## and fallbacks. Pure data — no scene or frames required.
##
## Lives in the UI harness (not res://tests/) so it runs reliably headless;
## new res://tests/ suites are not discoverable by test_run until the editor
## restarts (addon issue #882).

const GameLocaleScript := preload("res://scripts/systems/game_locale.gd")


func suite_name() -> String:
	return "test_game_locale"


func test_default_locale_is_english() -> void:
	var locale = GameLocaleScript.new()
	expect_eq(locale.get_locale(), "en", "default locale is en")


func test_supported_locales_resolve() -> void:
	var locale = GameLocaleScript.new()
	locale.set_locale("zh_Hant")
	expect_eq(locale.get_locale(), "zh_Hant", "zh_Hant is supported")
	locale.set_locale("fr")
	expect_eq(locale.get_locale(), "en", "unsupported locale falls back to en")


func test_kill_exp_translates_en() -> void:
	var locale = GameLocaleScript.new()
	var text: String = locale.translate("log.kill_exp", {"name": "Zombie", "amount": 200})
	expect_eq(text, "Killed Zombie, EXP +200", "en kill_exp template formats")


func test_kill_exp_translates_zh() -> void:
	var locale = GameLocaleScript.new()
	locale.set_locale("zh_Hant")
	var text: String = locale.translate("log.kill_exp", {"name": "殭屍", "amount": 200})
	expect_eq(text, "擊殺了殭屍，經驗值 +200", "zh_Hant kill_exp template formats")


func test_missing_key_returns_key() -> void:
	var locale = GameLocaleScript.new()
	expect_eq(locale.translate("log.does_not_exist"), "log.does_not_exist", "unknown key echoes the key")


func test_invalid_locale_falls_back_to_english() -> void:
	var locale = GameLocaleScript.new()
	# Bypass set_locale to force an invalid value directly.
	locale.locale = "xx"
	var text: String = locale.translate("log.kill_exp", {"name": "Zombie", "amount": 1})
	expect_eq(text, "Killed Zombie, EXP +1", "invalid locale falls back to English template")


func test_enemy_name_localized_in_zh() -> void:
	var locale = GameLocaleScript.new()
	locale.set_locale("zh_Hant")
	expect_eq(locale.localize_enemy_name("Training Wraith"), "訓練幽魂", "Training Wraith localizes")
	expect_eq(locale.localize_enemy_name("Bloodbound Warlord"), "血縛戰帥", "Bloodbound Warlord localizes")


func test_enemy_name_kept_in_en() -> void:
	var locale = GameLocaleScript.new()
	expect_eq(locale.localize_enemy_name("Training Wraith"), "Training Wraith", "en keeps source name")


func test_unknown_enemy_name_falls_back() -> void:
	var locale = GameLocaleScript.new()
	locale.set_locale("zh_Hant")
	expect_eq(locale.localize_enemy_name("Mystery Beast"), "Mystery Beast", "unknown enemy keeps source name")
