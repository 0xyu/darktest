class_name EnemyBestiaryPanel
extends Control

## Browsable atlas viewer for the creature sheet supplied with the project.
## The sheet uses a 16 x 16 pixel grid; the first 36 rows contain the
## creature sprites while the lower rows contain miscellaneous icons.

const ATLAS_SHEET: Texture2D = preload("res://assets/enemies/oryx_16bit_fantasy_creatures_trans.png")
const CELL_SIZE: int = 24
const ATLAS_COLUMNS: int = 18
const CREATURE_ROWS: int = 20

@onready var _count_label: Label = %CountLabel
@onready var _selected_preview: TextureRect = %SelectedPreview
@onready var _selected_name: Label = %SelectedName
@onready var _selected_meta: Label = %SelectedMeta
@onready var _selected_description: Label = %SelectedDescription
@onready var _specimen_grid: GridContainer = %SpecimenGrid
@onready var _close_button: Button = %CloseButton

var _atlas_image: Image
var _specimen_count: int = 0


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(hide_bestiary)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_build_specimen_grid()
	_update_grid_columns()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide_bestiary()
		get_viewport().set_input_as_handled()


func toggle_bestiary() -> void:
	visible = not visible
	if visible:
		_close_button.grab_focus()


func show_bestiary() -> void:
	visible = true


func hide_bestiary() -> void:
	visible = false


func _on_viewport_size_changed() -> void:
	_update_grid_columns()


func _update_grid_columns() -> void:
	var available_width: float = maxf(get_viewport_rect().size.x - 60.0, 1.0)
	_specimen_grid.columns = maxi(floori(available_width / 73.0), 4)


func _build_specimen_grid() -> void:
	_atlas_image = ATLAS_SHEET.get_image()
	_specimen_count = 0
	var first_texture: AtlasTexture
	var first_column: int = 0
	var first_row: int = 0
	for child in _specimen_grid.get_children():
		child.queue_free()

	for row in range(CREATURE_ROWS):
		for column in range(ATLAS_COLUMNS):
			if not _cell_contains_sprite(column, row):
				continue
			_specimen_count += 1
			var atlas_texture := _create_atlas_texture(column, row)
			if first_texture == null:
				first_texture = atlas_texture
				first_column = column
				first_row = row
			var card := _create_specimen_card(atlas_texture, _specimen_count)
			_specimen_grid.add_child(card)
			card.pressed.connect(_on_specimen_pressed.bind(atlas_texture, _specimen_count, column, row))

	_count_label.text = "%d SPECIMENS  •  16 PX ATLAS CELLS" % _specimen_count
	if first_texture != null:
		_select_specimen(first_texture, 1, first_column, first_row)


func _cell_contains_sprite(column: int, row: int) -> bool:
	if _atlas_image == null:
		return false
	var origin := Vector2i(column * CELL_SIZE, row * CELL_SIZE)
	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			var pixel_position := origin + Vector2i(x, y)
			if pixel_position.x >= _atlas_image.get_width() or pixel_position.y >= _atlas_image.get_height():
				continue
			if _atlas_image.get_pixelv(pixel_position).a > 0.05:
				return true
	return false


func _create_atlas_texture(column: int, row: int) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = ATLAS_SHEET
	atlas_texture.region = Rect2(column * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)
	return atlas_texture


func _create_specimen_card(atlas_texture: AtlasTexture, index: int) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(68.0, 78.0)
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("normal", _make_card_style(Color("151321"), Color("393149"), 1))
	card.add_theme_stylebox_override("hover", _make_card_style(Color("29213a"), Color("b38a4c"), 2))
	card.add_theme_stylebox_override("pressed", _make_card_style(Color("3a2a25"), Color("e0b967"), 2))

	var preview := TextureRect.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 6.0)
	preview.offset_left = 8.0
	preview.offset_top = 5.0
	preview.offset_right = -8.0
	preview.offset_bottom = 59.0
	preview.texture = atlas_texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(preview)

	var index_label := Label.new()
	index_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 4.0)
	index_label.offset_left = 4.0
	index_label.offset_top = -18.0
	index_label.offset_right = -4.0
	index_label.offset_bottom = -3.0
	index_label.text = "%03d" % index
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	index_label.add_theme_color_override("font_color", Color("9d93ae"))
	index_label.add_theme_font_size_override("font_size", 10)
	index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(index_label)
	return card


func _on_specimen_pressed(atlas_texture: AtlasTexture, index: int, column: int, row: int) -> void:
	_select_specimen(atlas_texture, index, column, row)


func _select_specimen(atlas_texture: Texture2D, index: int, column: int, row: int) -> void:
	_selected_preview.texture = atlas_texture
	_selected_name.text = "ATLAS SPECIMEN %03d" % index
	_selected_meta.text = "CREATURE ARCHIVE  //  COLUMN %02d  •  ROW %02d" % [column + 1, row + 1]
	_selected_description.text = "A discovered creature sprite from the Oryx 16-bit fantasy atlas.\nTap another specimen below to inspect it."


func _make_card_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	return style
