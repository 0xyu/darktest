class_name GameLocale
extends RefCounted

## Lightweight in-code localization for game UI strings.
##
## Supports English ("en") and Traditional Chinese ("zh_Hant"). Kept outside
## Godot's TranslationServer / CSV import pipeline so it works deterministically
## in headless tests without an editor import pass.
##
## Templates use named `{placeholder}` tokens and are formatted with
## `String.format()`. The combat log panel feeds the highlighted enemy name in
## through the `{name}` placeholder.

const DEFAULT_LOCALE := "en"
const FALLBACK_LOCALE := "en"
const SUPPORTED_LOCALES: Array[String] = ["en", "zh_Hant"]

var locale: String = DEFAULT_LOCALE

const _STRINGS := {
	"log.title": {"en": "COMBAT LOG", "zh_Hant": "戰鬥日誌"},
	"log.kill_exp": {"en": "Killed {name}, EXP +{amount}", "zh_Hant": "擊殺了{name}，經驗值 +{amount}"},
	"log.gold_gained": {"en": "Gold +{amount}", "zh_Hant": "獲得金幣 +{amount}"},
	"log.loot_found": {"en": "Loot: {items}", "zh_Hant": "獲得戰利品：{items}"},
	"log.level_up": {"en": "Level Up! Lv.{level}", "zh_Hant": "升級！達到 Lv.{level}"},
	"log.stage_start": {"en": "Stage {stage} started", "zh_Hant": "第 {stage} 關 開始"},
	"log.stage_clear": {"en": "Stage {stage} cleared", "zh_Hant": "第 {stage} 關 通關"},
	"log.player_defeated": {"en": "Player defeated", "zh_Hant": "玩家被擊敗"},
	"log.enemy_summoned": {"en": "{name} summoned reinforcements", "zh_Hant": "{name} 召喚了援軍"},
}

## Localized display names for the enemy resources shipped with the project.
## Names not listed here fall back to the source `EnemyData.name`.
const _ENEMY_NAMES := {
	"en": {},
	"zh_Hant": {
		"Training Wraith": "訓練幽魂",
		"Ashen Oracle": "灰燼先知",
		"Bloodbound Warlord": "血縛戰帥",
		"Gravecaller": "喚墓者",
	},
}


func set_locale(value: String) -> void:
	locale = value if SUPPORTED_LOCALES.has(value) else DEFAULT_LOCALE


func get_locale() -> String:
	return locale


## Returns the localized template for `key` with `values` substituted.
## Missing keys and unsupported locales fall back to the English template.
func translate(key: String, values: Dictionary = {}) -> String:
	var strings_for_key: Variant = _STRINGS.get(key)
	if strings_for_key is not Dictionary:
		return key
	var template: Variant = strings_for_key.get(locale, strings_for_key.get(FALLBACK_LOCALE, key))
	if not template is String:
		return key
	if values.is_empty():
		return template
	return (template as String).format(values)


## Localized display name for an enemy, falling back to the source name.
func localize_enemy_name(name: String) -> String:
	if name.is_empty():
		return name
	var localized: Variant = (_ENEMY_NAMES.get(locale, {}) as Dictionary).get(name)
	if localized is String and not (localized as String).is_empty():
		return localized
	return name
