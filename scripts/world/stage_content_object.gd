class_name StageContentObject
extends Node2D

## Visual + positional wrapper for ONE StageContent placed on a grid cell.
##
## This node knows only WHERE it is and how to draw itself. All rules — when
## content appears, whether it is consumed, what it grants — belong to
## StageContentController, so the objects stay dumb and replaceable.

const CHEST_FILL := Color("6b4f24")
const CHEST_EDGE := Color("e0b968")
const POOL_FILL := Color("1d4a5c")
const POOL_EDGE := Color("7fd7e8")

var content: StageContent
var cell: Vector2i = Vector2i.ZERO
var cell_size: int = 64


## Places this object on `cell` in the parent grid's coordinate space.
func place_on_cell(target_cell: Vector2i, target_cell_size: int) -> void:
	cell = target_cell
	cell_size = maxi(target_cell_size, 1)
	position = Vector2(cell * cell_size) + Vector2.ONE * (float(cell_size) * 0.5)
	queue_redraw()


func get_content_id() -> StringName:
	return content.id if content != null else &""


func _draw() -> void:
	if content == null:
		return
	match content.kind:
		StageContent.Kind.CHEST:
			_draw_chest()
		StageContent.Kind.HEALING_POOL:
			_draw_healing_pool()
		_:
			_draw_chest()


func _draw_chest() -> void:
	var half: float = float(cell_size) * 0.22
	var body := Rect2(-half, -half * 0.6, half * 2.0, half * 1.6)
	draw_rect(body, CHEST_FILL, true)
	draw_rect(body, CHEST_EDGE, false, 2.0)
	# Lid seam + latch so it reads as a container rather than a plain block.
	var seam_y: float = -half * 0.6 + half * 0.6
	draw_line(Vector2(-half, seam_y), Vector2(half, seam_y), CHEST_EDGE, 1.0)
	draw_rect(Rect2(-half * 0.18, seam_y - half * 0.22, half * 0.36, half * 0.44), CHEST_EDGE, true)


func _draw_healing_pool() -> void:
	var radius: float = float(cell_size) * 0.30
	var points := PackedVector2Array()
	var segments: int = 20
	for index in range(segments):
		var angle: float = TAU * float(index) / float(segments)
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.62))
	draw_colored_polygon(points, POOL_FILL)
	points.append(points[0])
	draw_polyline(points, POOL_EDGE, 2.0)
	# A small cross keeps the "restores HP" reading obvious at a glance.
	var arm: float = radius * 0.42
	draw_line(Vector2(-arm, 0.0), Vector2(arm, 0.0), POOL_EDGE, 2.0)
	draw_line(Vector2(0.0, -arm * 0.62), Vector2(0.0, arm * 0.62), POOL_EDGE, 2.0)
