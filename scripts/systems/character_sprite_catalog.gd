class_name CharacterSpriteCatalog
extends RefCounted

## Single source of truth for the character sprite sheet and its slice IDs.
## Consumers should store only a character ID and resolve the AtlasTexture here.

const SPRITE_SHEET: Texture2D = preload("res://assets/enemies/oryx_16bit_fantasy_creatures_trans.png")
const CELL_SIZE: int = 24
const ATLAS_COLUMNS: int = 18
const CREATURE_ROWS: int = 20

## Named character slices used by gameplay. Every entry has a unique ID.
const CHARACTER_CELLS: Dictionary = {
	&"character_training_wraith": Vector2i(1, 1),
	&"character_gravecaller": Vector2i(5, 10),
	&"character_bloodbound_warlord": Vector2i(7, 3),
	&"character_ashen_oracle": Vector2i(12, 9),
}

static var _atlas_image: Image
static var _discovered_ids: Array[StringName] = []
static var _cells_by_id: Dictionary = {}
static var _catalog_initialized: bool = false


static func get_texture(character_id: StringName) -> AtlasTexture:
	_ensure_catalog()
	var cell: Vector2i = get_cell(character_id)
	if cell.x < 0 or cell.y < 0:
		return null
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = SPRITE_SHEET
	atlas_texture.region = Rect2(
		Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE),
		Vector2(CELL_SIZE, CELL_SIZE)
	)
	return atlas_texture


static func get_cell(character_id: StringName) -> Vector2i:
	_ensure_catalog()
	return _cells_by_id.get(character_id, Vector2i(-1, -1))


static func get_discovered_ids() -> Array[StringName]:
	_ensure_catalog()
	return _discovered_ids.duplicate()


static func _ensure_catalog() -> void:
	if _catalog_initialized:
		return
	_atlas_image = SPRITE_SHEET.get_image()
	_discovered_ids.clear()
	_cells_by_id.clear()

	var preferred_ids_by_cell: Dictionary = {}
	for character_id: StringName in CHARACTER_CELLS.keys():
		preferred_ids_by_cell[CHARACTER_CELLS[character_id]] = character_id

	for row in range(CREATURE_ROWS):
		for column in range(ATLAS_COLUMNS):
			if not _cell_contains_sprite(column, row):
				continue
			var cell := Vector2i(column, row)
			var generic_id := StringName("character_atlas_%02d_%02d" % [column, row])
			var character_id: StringName = preferred_ids_by_cell.get(cell, generic_id)
			_discovered_ids.append(character_id)
			_cells_by_id[character_id] = cell

	_catalog_initialized = true


static func _cell_contains_sprite(column: int, row: int) -> bool:
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
