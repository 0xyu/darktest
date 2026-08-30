class_name CombatLogPanel
extends PanelContainer

## Bottom-left combat event log.
##
## Shows localized event messages in yellow with the highlighted enemy name in
## white inside 【】. Keeps a 50-entry history and renders the newest 5. Mouse
## input is ignored so the panel never blocks taps on the grid behind it.
##
## The headless test suite lives in
## res://tools/ui_harness/suites/test_combat_log_panel.gd.

const GameLocaleScript = preload("res://scripts/systems/game_locale.gd")

const MAX_ENTRIES := 50
const MAX_VISIBLE := 5
const LOG_COLOR := Color("e8c15a")
const NAME_COLOR := Color("ffffff")
const CJK_FONT_NAMES := [
	"Microsoft JhengHei",
	"Noto Sans CJK TC",
	"Noto Sans TC",
	"PingFang TC",
	"Source Han Sans TC",
]

@onready var _header: Label = %LogHeader
@onready var _entry_list: VBoxContainer = %LogEntryList

var _locale: GameLocale = GameLocaleScript.new()
var _entries: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font_for_locale()
	_refresh_header()


func set_locale(locale: String) -> void:
	_locale.set_locale(locale)
	_apply_font_for_locale()
	_refresh_header()
	_rebuild()


func get_locale() -> String:
	return _locale.get_locale()


## Appends a localized event. When `values` contains a `"name"` key, that value
## is rendered in white inside 【】 (e.g. the defeated enemy).
func append(key: String, values: Dictionary = {}) -> void:
	_entries.append({"key": key, "values": values.duplicate()})
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	_rebuild()


func clear() -> void:
	_entries.clear()
	_rebuild()


func get_entry_count() -> int:
	return _entries.size()


## BBCode of the newest entry; empty when the log has no entries.
func get_latest_text() -> String:
	if _entries.is_empty():
		return ""
	return _render(_entries[_entries.size() - 1])


## BBCode of the entries currently visible in the panel.
func get_visible_entries() -> Array[String]:
	var result: Array[String] = []
	for entry in _entries.slice(maxi(_entries.size() - MAX_VISIBLE, 0)):
		result.append(_render(entry))
	return result


func _refresh_header() -> void:
	if _header != null:
		_header.text = _locale.translate("log.title")


func _apply_font_for_locale() -> void:
	# The default theme font ships no CJK glyphs; for Traditional Chinese use a
	# system CJK font (Windows: Microsoft JhengHei) so the log renders instead
	# of showing tofu boxes. English keeps the default theme font.
	if _locale.get_locale() == "zh_Hant":
		var cjk_font := SystemFont.new()
		cjk_font.font_names = PackedStringArray(CJK_FONT_NAMES)
		cjk_font.allow_system_fallback = true
		add_theme_font_override("font", cjk_font)
	else:
		remove_theme_font_override("font")


func _render(entry: Dictionary) -> String:
	var values: Dictionary = entry.get("values", {})
	if values.has("name"):
		values = values.duplicate()
		values["name"] = _highlight_name(str(values["name"]))
	return _locale.translate(str(entry.get("key", "")), values)


func _highlight_name(display_name: String) -> String:
	return "[color=#%s]【%s】[/color]" % [NAME_COLOR.to_html(false), _locale.localize_enemy_name(display_name)]


func _rebuild() -> void:
	if _entry_list == null:
		return
	for child in _entry_list.get_children():
		child.free()
	for entry in _entries.slice(maxi(_entries.size() - MAX_VISIBLE, 0)):
		_entry_list.add_child(_create_entry_label(_render(entry)))


func _create_entry_label(text: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("default_color", LOG_COLOR)
	label.add_theme_font_size_override("font_size", 12)
	label.text = text
	return label
