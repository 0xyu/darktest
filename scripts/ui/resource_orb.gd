class_name ResourceOrb
extends Control

## Texture-backed circular resource fill used inside the transparent openings
## of the hp-mana frame. The texture remains a full sphere and is clipped from
## the bottom up, so lowering HP never distorts the artwork.
const FILL_TEXTURE: Texture2D = preload("res://assets/ui/hud/hp-fill.png")

var fill_ratio: float = 1.0
var fill_color: Color = Color("b83b35")
var _fill_texture_rect: TextureRect


func _ready() -> void:
	_fill_texture_rect = TextureRect.new()
	_fill_texture_rect.name = "FillTexture"
	_fill_texture_rect.texture = FILL_TEXTURE
	_fill_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fill_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_fill_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_texture_rect.material = _create_fill_material()
	add_child(_fill_texture_rect)
	_layout_fill_texture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(_fill_texture_rect):
		_layout_fill_texture()


func _layout_fill_texture() -> void:
	# The source is square. Keep it square and centered inside the opening even
	# if the surrounding HUD is resized or the frame has a different aspect.
	var diameter := maxf(minf(size.x, size.y) - 50.0, 0.0)
	_fill_texture_rect.size = Vector2.ONE * diameter
	_fill_texture_rect.position = (size - _fill_texture_rect.size) * 0.5


func _create_fill_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float fill_ratio = 1.0;

void fragment() {
	if (UV.y < 1.0 - fill_ratio) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
"""
	var fill_material := ShaderMaterial.new()
	fill_material.shader = shader
	fill_material.set_shader_parameter("fill_ratio", fill_ratio)
	return fill_material


func set_fill_ratio(value: float) -> void:
	fill_ratio = clampf(value, 0.0, 1.0)
	if is_instance_valid(_fill_texture_rect) and _fill_texture_rect.material is ShaderMaterial:
		(_fill_texture_rect.material as ShaderMaterial).set_shader_parameter("fill_ratio", fill_ratio)
