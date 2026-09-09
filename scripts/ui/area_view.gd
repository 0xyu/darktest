class_name AreaView
extends PanelContainer

## Phase 6 presentation of ONE authored area path ("WorldMap / AreaMap
## Integration"): the stage nodes are generated at runtime from the area's
## StageDatabase (stage_count + per-stage stage_type), never from a hard-coded
## "Stage 01 ... Stage 10" list, and never from `if stage == 6` type checks.
##
## Each node reads PlayerProgress to show LOCKED / AVAILABLE / COMPLETED /
## CURRENT. Clicking an unlocked node emits stage_enter_requested; the owner
## (grid_combat host) decides the actual gameplay via StageRouter. This view
## holds no static data and never writes progress.
##
## Presentation scale: small areas render as one page. Larger databases
## (> NODES_PER_WINDOW) are paginated in windows so a 10,000 stage area never
## materializes 10,000 Controls — the data architecture stays untouched
## (Coding Plan Phase 6 "10K 呈现问题").

signal stage_enter_requested(area_id: StringName, stage_number: int)

const StageDatabaseScript := preload("res://scripts/data/stage_database.gd")
const StageTypeScript := preload("res://scripts/data/stage_type.gd")

## Node presentation states (read from PlayerProgress, UI only).
enum NodeState {
	LOCKED,
	AVAILABLE,
	COMPLETED,
	CURRENT,
}

const NODE_STATE_NAMES := {
	NodeState.LOCKED: "LOCKED",
	NodeState.AVAILABLE: "READY",
	NodeState.COMPLETED: "DONE",
	NodeState.CURRENT: "HERE",
}

## One authored stage = one Control window; bigger areas page through windows.
const NODES_PER_WINDOW: int = 24

# Path geometry (fixed for the 720-wide portrait layout).
const NODE_W: float = 312.0
const NODE_H: float = 88.0
const NODE_STEP_Y: float = 118.0
const COL_LEFT_X: float = 8.0
const COL_RIGHT_X: float = 336.0
const PATH_TOP: float = 8.0
const PATH_PAD_BOTTOM: float = 12.0
const PATH_W: float = 664.0

const COLOR_TEXT := Color("e6dcc8")
const COLOR_GOLD := Color("e8c465")
const COLOR_BG := Color("0e0c14")
const COLOR_PANEL_BG := Color("120f1b")
const COLOR_BORDER := Color("4d465e")

## Accent per authored StageType (icon / node identity comes from stage_type).
const TYPE_COLORS := {
	StageTypeScript.COMBAT: Color("a8b4c8"),
	StageTypeScript.EVENT: Color("d9a866"),
	StageTypeScript.TOWN: Color("e8c465"),
	StageTypeScript.BOSS: Color("d46a78"),
}

## Compact one-letter icon shown inside each node's type medallion.
const TYPE_CODES := {
	StageTypeScript.COMBAT: "C",
	StageTypeScript.EVENT: "E",
	StageTypeScript.TOWN: "T",
	StageTypeScript.BOSS: "B",
}

const STATE_COLORS := {
	NodeState.LOCKED: Color("5b5670"),
	NodeState.AVAILABLE: COLOR_GOLD,
	NodeState.COMPLETED: Color("82d49b"),
	NodeState.CURRENT: Color("71a9ed"),
}

var _database: StageDatabase
var _progress: PlayerProgress
var _window_index: int = 0
var _window_count: int = 1
var _subtitle_label: Label
var _path_host: Control
var _path_canvas: PathCanvas
var _pager_label: Label
var _nodes: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Binds the static database and the live progress object, then builds the
## path. Pass null progress to render from a "fresh player" rule set.
func setup(database: StageDatabase, progress: PlayerProgress = null) -> void:
	_database = database
	_progress = progress
	_window_index = 0
	_window_count = maxi(1, ceili(int(database.stage_count) / float(NODES_PER_WINDOW)))
	_build_ui()
	_rebuild_path()


## Rebuilds every node so LOCKED / AVAILABLE / COMPLETED / CURRENT reflect the
## current PlayerProgress. Re-query nodes after a refresh.
func refresh() -> void:
	if _database == null:
		return
	_window_index = clampi(_window_index, 0, _window_count - 1)
	_rebuild_path()
	_update_header_progress()


func get_area_id() -> StringName:
	return _database.area_id if _database != null else &""


func get_database() -> StageDatabase:
	return _database


## Stage node Button for `stage_number` (only the current window is built;
## returns null when the number falls outside it).
func get_stage_node(stage_number: int) -> Button:
	return _nodes.get(stage_number) as Button


func get_window_start() -> int:
	return _window_index * NODES_PER_WINDOW + 1


func get_window_end() -> int:
	return mini(int(_database.stage_count), get_window_start() + NODES_PER_WINDOW - 1)


## Number of stage-number windows a database this size is split into.
func get_window_count() -> int:
	return _window_count


## Jumps to an absolute window index (0-based) and rebuilds its nodes.
func show_window(index: int) -> void:
	_window_index = clampi(index, 0, _window_count - 1)
	_rebuild_path()


## Player-side presentation state of one authored stage. Pure function of the
## live PlayerProgress (static data is never consulted for progress).
static func compute_state(progress: PlayerProgress, area_id: StringName, stage_number: int) -> int:
	var unlocked: bool = false
	if progress == null:
		unlocked = stage_number == 1
	else:
		unlocked = progress.is_stage_unlocked(area_id, stage_number)
	if not unlocked:
		return NodeState.LOCKED
	if progress != null and progress.is_stage_completed(area_id, stage_number):
		return NodeState.COMPLETED
	if (
		progress != null
		and String(progress.current_area_id) == String(area_id)
		and progress.current_stage_number == stage_number
	):
		return NodeState.CURRENT
	return NodeState.AVAILABLE


static func get_state_name(state: int) -> String:
	return NODE_STATE_NAMES.get(state, "UNKNOWN")


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", _panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	content.add_child(_build_header())
	if _window_count > 1:
		content.add_child(_build_pager())

	# Nodes + connector lines live on one fixed-size Control so the outer
	# ScrollContainer can give this area its natural (possibly tall) height.
	# Height is recomputed per window in _rebuild_path().
	_path_host = Control.new()
	_path_host.custom_minimum_size = Vector2(PATH_W, 0)
	_path_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_path_host)

	_path_canvas = PathCanvas.new()
	_path_canvas.anchor_right = 1.0
	_path_canvas.anchor_bottom = 1.0
	_path_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path_host.add_child(_path_canvas)

	_update_header_progress()


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.add_theme_constant_override("separation", 0)
	header.add_child(title_block)

	var title := Label.new()
	title.text = String(_database.display_name).to_upper()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 20)
	title_block.add_child(title)

	_subtitle_label = Label.new()
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_label.add_theme_color_override("font_color", Color("9a90ad"))
	_subtitle_label.add_theme_font_size_override("font_size", 11)
	title_block.add_child(_subtitle_label)

	var count := Label.new()
	count.text = "%d STAGES" % _database.stage_count
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.add_theme_color_override("font_color", Color("9a90ad"))
	count.add_theme_font_size_override("font_size", 12)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(count)
	return header


func _update_header_progress() -> void:
	if _subtitle_label == null or _database == null:
		return
	var current_text := "no current position"
	if _progress != null and String(_progress.current_area_id) == String(_database.area_id):
		current_text = "at stage %d" % _progress.current_stage_number
	_subtitle_label.text = "%s · %s" % [String(_database.area_id).to_upper(), current_text]


func _build_pager() -> HBoxContainer:
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", 8)

	var previous := Button.new()
	previous.text = "◀ PREV"
	previous.focus_mode = Control.FOCUS_NONE
	previous.disabled = _window_index == 0
	previous.add_theme_color_override("font_color", Color("9a90ad"))
	previous.add_theme_font_size_override("font_size", 11)
	previous.pressed.connect(func() -> void: _change_window(-1))
	pager.add_child(previous)

	_pager_label = Label.new()
	_pager_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pager_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pager_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pager_label.add_theme_color_override("font_color", COLOR_GOLD)
	_pager_label.add_theme_font_size_override("font_size", 11)
	pager.add_child(_pager_label)

	var next := Button.new()
	next.text = "NEXT ▶"
	next.focus_mode = Control.FOCUS_NONE
	next.disabled = _window_index >= _window_count - 1
	next.add_theme_color_override("font_color", Color("9a90ad"))
	next.add_theme_font_size_override("font_size", 11)
	next.pressed.connect(func() -> void: _change_window(1))
	pager.add_child(next)

	_update_pager_label()
	return pager


func _update_pager_label() -> void:
	if _pager_label == null:
		return
	_pager_label.text = "STAGES %d–%d of %d  ·  page %d/%d" % [
		get_window_start(),
		get_window_end(),
		_database.stage_count,
		_window_index + 1,
		_window_count,
	]


func _change_window(offset: int) -> void:
	_window_index = clampi(_window_index + offset, 0, _window_count - 1)
	_rebuild_path()


## Path area height for the nodes actually present in the current window.
func _window_path_height() -> float:
	var count_in_window: int = get_window_end() - get_window_start() + 1
	var rows: int = ceili(count_in_window / 2.0)
	return PATH_TOP + rows * NODE_STEP_Y + PATH_PAD_BOTTOM


func _rebuild_path() -> void:
	if _path_host == null:
		return
	_path_host.custom_minimum_size = Vector2(PATH_W, _window_path_height())
	# Drop previous canvas + node buttons (all children of the path host).
	for child in _path_host.get_children():
		_path_host.remove_child(child)
		child.queue_free()
	_nodes.clear()
	_path_canvas = PathCanvas.new()
	_path_canvas.anchor_right = 1.0
	_path_canvas.anchor_bottom = 1.0
	_path_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path_host.add_child(_path_canvas)

	var points := PackedVector2Array()
	for number in range(get_window_start(), get_window_end() + 1):
		var stage := _database.get_stage(number)
		if stage == null:
			continue
		var node := _make_stage_node(stage, number)
		points.append(Vector2(node.position.x + NODE_W * 0.5, node.position.y + NODE_H * 0.5))
		_path_host.add_child(node)
		_nodes[number] = node
	_path_canvas.set_points(points)
	_update_pager_label()


func _stage_position(number: int) -> Vector2:
	var index: int = number - 1 - _window_index * NODES_PER_WINDOW
	var row: int = index / 2
	var column: int = index % 2
	return Vector2(COL_LEFT_X if column == 0 else COL_RIGHT_X, PATH_TOP + row * NODE_STEP_Y)


func _make_stage_node(stage: StageData, number: int) -> Button:
	var state := compute_state(_progress, _database.area_id, number)
	var stage_type: int = stage.stage_type
	var type_color: Color = TYPE_COLORS.get(stage_type, COLOR_TEXT)
	var state_color: Color = STATE_COLORS.get(state, Color("9a90ad"))
	var locked: bool = state == NodeState.LOCKED

	var button := Button.new()
	button.name = "StageNode_%d" % number
	button.size = Vector2(NODE_W, NODE_H)
	button.position = _stage_position(number)
	button.disabled = locked
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("area_id", _database.area_id)
	button.set_meta("stage_number", number)
	button.set_meta("stage_type", stage_type)
	button.set_meta("stage_state", state)
	var base_border := state_color if not locked else Color("3b3850")
	button.add_theme_stylebox_override("normal", _node_style(COLOR_BG, base_border, 1, 6))
	button.add_theme_stylebox_override("hover", _node_style(Color("171224"), state_color, 2, 6))
	button.add_theme_stylebox_override("pressed", _node_style(Color("443022"), state_color.lightened(0.2), 2, 6))
	button.add_theme_stylebox_override("disabled", _node_style(Color("0e0c14"), Color("332f45"), 1, 6))
	button.pressed.connect(_on_node_pressed.bind(_database.area_id, number))

	var row := HBoxContainer.new()
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = 10.0
	row.offset_top = 6.0
	row.offset_right = -10.0
	row.offset_bottom = -6.0
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	row.add_child(_make_medallion(stage_type, type_color, locked))

	var text_block := VBoxContainer.new()
	text_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_block.alignment = BoxContainer.ALIGNMENT_CENTER
	text_block.add_theme_constant_override("separation", 2)
	text_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_block)

	var title_label := Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.text = "%s  ·  %s" % [str(number).pad_zeros(3), stage.display_name]
	title_label.add_theme_color_override("font_color", COLOR_TEXT if not locked else Color("6c6880"))
	title_label.add_theme_font_size_override("font_size", 15)
	text_block.add_child(title_label)

	var info_label := Label.new()
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.text = StageTypeScript.get_display_name(stage_type).to_upper()
	info_label.add_theme_color_override("font_color", type_color if not locked else Color("6c6880"))
	info_label.add_theme_font_size_override("font_size", 10)
	text_block.add_child(info_label)

	var state_label := Label.new()
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_label.text = NODE_STATE_NAMES.get(state, "?")
	state_label.custom_minimum_size = Vector2(58, 0)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state_label.add_theme_color_override("font_color", state_color)
	state_label.add_theme_font_size_override("font_size", 11)
	row.add_child(state_label)
	return button


## Round colored medallion carrying the one-letter stage type icon.
func _make_medallion(stage_type: int, type_color: Color, locked: bool) -> PanelContainer:
	var medallion := PanelContainer.new()
	medallion.custom_minimum_size = Vector2(46, 46)
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint := type_color.darkened(0.45) if not locked else Color("2b2936")
	var rim := type_color if not locked else Color("4a4656")
	medallion.add_theme_stylebox_override("panel", _node_style(tint, rim, 2, 23))
	var letter := Label.new()
	letter.text = TYPE_CODES.get(stage_type, "?")
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_color_override("font_color", type_color.lightened(0.35) if not locked else Color("6c6880"))
	letter.add_theme_font_size_override("font_size", 22)
	medallion.add_child(letter)
	return medallion


func _on_node_pressed(area_id: StringName, stage_number: int) -> void:
	stage_enter_requested.emit(area_id, stage_number)


func _node_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


# ---------------------------------------------------------------------------
# Path connector canvas (draws the winding line behind the stage nodes)
# ---------------------------------------------------------------------------

class PathCanvas:
	extends Control

	var _points := PackedVector2Array()

	func set_points(points: PackedVector2Array) -> void:
		_points = points
		queue_redraw()

	func _draw() -> void:
		if _points.size() < 2:
			return
		draw_polyline(_points, Color("604a2b", 0.9), 2.0, true)
		for point in _points:
			draw_circle(point, 4.0, Color("8c5e26"))
