class_name EnemyBestiaryPanel
extends Control

## Browsable atlas viewer for the creature sheet supplied with the project.
@onready var _count_label: Label = %CountLabel
@onready var _selected_preview: TextureRect = %SelectedPreview
@onready var _selected_name: Label = %SelectedName
@onready var _selected_meta: Label = %SelectedMeta
@onready var _selected_description: Label = %SelectedDescription
@onready var _specimen_grid: GridContainer = %SpecimenGrid
@onready var _close_button: Button = %CloseButton

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
	_specimen_count = 0
	for child in _specimen_grid.get_children():
		child.queue_free()

	var first_id: StringName = &""
	for character_id: StringName in CharacterSpriteCatalog.get_discovered_ids():
		var atlas_texture := CharacterSpriteCatalog.get_texture(character_id)
		if atlas_texture == null:
			continue
		_specimen_count += 1
		if first_id == &"":
			first_id = character_id
		var card := _create_specimen_card(atlas_texture, _specimen_count)
		_specimen_grid.add_child(card)
		card.pressed.connect(_on_specimen_pressed.bind(character_id, _specimen_count))

	_count_label.text = "%d SPECIMENS  •  24 PX ATLAS CELLS" % _specimen_count
	if first_id != &"":
		_select_specimen(first_id, 1)


func _create_specimen_card(atlas_texture: AtlasTexture, index: int) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(68.0, 78.0)
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("normal", _make_card_style(Color("151321"), Color("393149"), 1))
	card.add_theme_stylebox_override("hover", _make_card_style(Color("29213a"), Color("b38a4c"), 2))
	card.add_theme_stylebox_override("pressed", _make_card_style(Color("3a2a25"), Color("e0b967"), 2))

	var preview := TextureRect.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 6)
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
	index_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 4)
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


func _on_specimen_pressed(character_id: StringName, index: int) -> void:
	_select_specimen(character_id, index)


func _select_specimen(character_id: StringName, _index: int) -> void:
	var atlas_texture := CharacterSpriteCatalog.get_texture(character_id)
	var cell: Vector2i = CharacterSpriteCatalog.get_cell(character_id)
	if atlas_texture == null or cell.x < 0:
		return
	_selected_preview.texture = atlas_texture
	_selected_name.text = str(character_id).to_upper()
	_selected_meta.text = "CHARACTER SPRITE  //  ID %s  •  COLUMN %02d  •  ROW %02d" % [character_id, cell.x + 1, cell.y + 1]
	_selected_description.text = "A discovered character slice from the Oryx 16-bit fantasy atlas.\nTap another ID below to inspect it."


func _make_card_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	return style
