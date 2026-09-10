class_name WorldMapView
extends Control

## Phase 6 "WorldMap / AreaMap Integration" view (Coding Plan Rev 2, Phase 6).
##
## This is the full-screen world map shown inside the HUD's ViewContainer:
## it lists every authored area (from resources/stage_databases/) and lets the
## player enter unlocked stages. Area stage nodes are NOT hard-coded — each
## AreaView is built from its StageDatabase (its stage-number range +
## stage_type), and LOCKED / AVAILABLE / COMPLETED / CURRENT state comes from
## PlayerProgress.
##
## Stage numbers are GLOBAL (Phase 7.6), so the areas are listed in progression
## order and a click carries only the stage number: the host derives the area.
## When the map opens it follows the player — the area holding the current
## position jumps to the window containing it — and when the position is past
## every authored area (the endless tail) the map says so instead of pretending
## the player is nowhere.
##
## The view stays a dumb presenter: it never routes, never starts combat, never
## writes progress. Clicking a stage emits stage_enter_requested(number) and the
## grid_combat host decides what happens next (StageRouter). Closing the map
## emits close_requested and the HUD restores the previous view.

signal close_requested
signal stage_enter_requested(stage_number: int)

const StageDatabaseScript := preload("res://scripts/data/stage_database.gd")
const AreaViewScript := preload("res://scripts/ui/area_view.gd")
const PlayerProgressScript := preload("res://scripts/progress/player_progress.gd")

const COLOR_TEXT := Color("d8cfdf")
const COLOR_MUTED := Color("8f879d")
const COLOR_GOLD := Color("e8c465")
const COLOR_GOLD_BRIGHT := Color("f4d28b")
const COLOR_PANEL_BG := Color("120f1b")
const COLOR_BORDER := Color("604a2b")
const COLOR_BG := Color("0a0812")

const STATE_LEGEND := [
	[AreaViewScript.NodeState.LOCKED, "LOCKED", Color("5b5670")],
	[AreaViewScript.NodeState.AVAILABLE, "AVAILABLE", Color("e8c465")],
	[AreaViewScript.NodeState.COMPLETED, "COMPLETED", Color("82d49b")],
	[AreaViewScript.NodeState.CURRENT, "CURRENT", Color("71a9ed")],
]

var _progress: PlayerProgress
var _area_views: Array = []
var _areas_box: VBoxContainer
var _summary_label: Label
var _endless_label: Label


func _ready() -> void:
	_build_ui()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Binds the live PlayerProgress used to color stage states.
func set_progress(progress: PlayerProgress) -> void:
	_progress = progress


func get_progress() -> PlayerProgress:
	return _progress


## (Re)builds one AreaView per authored StageDatabase so the map always mirrors
## the current data + progress. Safe to call repeatedly (e.g. every open).
##
## The current position is used twice: to color the nodes, and to open the area
## that holds it on the window containing it, so the map never shows an area
## whose HERE marker is a page away.
func refresh() -> void:
	if _areas_box == null:
		return
	for child in _areas_box.get_children():
		_areas_box.remove_child(child)
		child.queue_free()
	_area_views.clear()
	var databases := StageDatabaseScript.discovered_databases()
	var live_progress: PlayerProgress = _progress if _progress != null else PlayerProgressScript.new()
	var current_stage: int = int(live_progress.current_stage_number)
	var current_area: StringName = live_progress.get_current_area_id()
	var total_stages: int = 0
	for database in databases:
		var view = AreaViewScript.new()
		view.setup(database, live_progress)
		view.stage_enter_requested.connect(_on_area_stage_enter_requested)
		_areas_box.add_child(view)
		_area_views.append(view)
		total_stages += int(database.stage_count)
		if not current_area.is_empty() and database.area_id == current_area:
			view.call("show_window_for_stage", current_stage)
	if _summary_label != null:
		var area_count := databases.size()
		_summary_label.text = "%d AREA%s · %d STAGES — from StageDatabase" % [
			area_count,
			"" if area_count == 1 else "S",
			total_stages,
		]
	if _endless_label != null:
		# Past the last authored area there is no range to mark: say so plainly
		# rather than showing a HERE marker the data cannot justify.
		_endless_label.visible = current_area.is_empty()
		_endless_label.text = "ENDLESS — stage %d (no area authored)" % current_stage
	if databases.is_empty():
		var empty := Label.new()
		empty.text = "No area authored yet (resources/stage_databases/)."
		empty.add_theme_color_override("font_color", COLOR_MUTED)
		empty.add_theme_font_size_override("font_size", 12)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_areas_box.add_child(empty)


## Current AreaView children (one per authored area), in area-id order.
func get_area_views() -> Array:
	return _area_views


func get_area_view(area_id: StringName) -> Node:
	for view in _area_views:
		if String(view.get_area_id()) == String(area_id):
			return view
	return null


## Direct lookup of one stage node Button for harness tests / callers.
func get_stage_node_button(area_id: StringName, stage_number: int) -> Button:
	var view := get_area_view(area_id) as Control
	if view == null:
		return null
	if not view.has_method("get_stage_node"):
		return null
	return view.call("get_stage_node", stage_number) as Button


## The footer line shown when the current position is past every authored area,
## or "" while an authored area covers it. Public so callers (and tests) can ask
## "is the player past the authored content?" without poking private labels.
func get_endless_text() -> String:
	if _endless_label == null or not _endless_label.visible:
		return ""
	return _endless_label.text


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = COLOR_BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	panel.offset_right = -8.0
	panel.offset_bottom = -8.0
	panel.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL_BG, COLOR_BORDER, 2, 10))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	content.add_child(_build_header())

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color("8c5e26")
	content.add_child(rule)

	var legend := _build_legend()
	if legend != null:
		content.add_child(legend)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_areas_box = VBoxContainer.new()
	_areas_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_areas_box.add_theme_constant_override("separation", 12)
	scroll.add_child(_areas_box)

	# Footer: where the player stands when no authored area covers the position.
	_endless_label = Label.new()
	_endless_label.visible = false
	_endless_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_endless_label.add_theme_color_override("font_color", COLOR_MUTED)
	_endless_label.add_theme_font_size_override("font_size", 11)
	content.add_child(_endless_label)


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 46)
	header.add_theme_constant_override("separation", 8)

	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.add_theme_constant_override("separation", 0)
	header.add_child(title_block)

	var title := Label.new()
	title.text = "WORLD MAP"
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 24)
	title_block.add_child(title)

	_summary_label = Label.new()
	_summary_label.add_theme_color_override("font_color", COLOR_MUTED)
	_summary_label.add_theme_font_size_override("font_size", 10)
	title_block.add_child(_summary_label)

	var close_button := Button.new()
	close_button.custom_minimum_size = Vector2(64, 44)
	close_button.text = "✕"
	close_button.add_theme_color_override("font_color", COLOR_TEXT)
	close_button.add_theme_font_size_override("font_size", 15)
	close_button.add_theme_stylebox_override("normal", _make_style(Color("0e0c14"), Color("3f344c"), 1, 6))
	close_button.add_theme_stylebox_override("hover", _make_style(Color("1c1720"), COLOR_GOLD, 2, 6))
	close_button.add_theme_stylebox_override("pressed", _make_style(Color("443022"), COLOR_GOLD_BRIGHT, 2, 6))
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_button)
	return header


## Tiny color-dot legend: LOCKED / AVAILABLE / COMPLETED / CURRENT.
func _build_legend() -> HBoxContainer:
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in STATE_LEGEND:
		var state_name := str(entry[1])
		var color: Color = entry[2]
		var dot := Label.new()
		dot.text = "● %s" % state_name
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_color_override("font_color", color)
		dot.add_theme_font_size_override("font_size", 10)
		legend.add_child(dot)
	return legend


func _on_area_stage_enter_requested(stage_number: int) -> void:
	stage_enter_requested.emit(stage_number)


# ---------------------------------------------------------------------------
# Area discovery
# ---------------------------------------------------------------------------

## The authored StageDatabases, taken from StageDatabase's cached range table so
## the map and the "which area covers this stage number" lookup can never
## disagree about which areas exist. Adding a new area = dropping a new .tres in
## resources/stage_databases/; no view / core change is needed.
static func _discover_databases() -> Array[StageDatabase]:
	return StageDatabaseScript.discovered_databases()


func _make_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
