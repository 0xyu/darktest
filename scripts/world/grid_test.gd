class_name GridTest
extends Node2D

@onready var grid: GridMap2D = $Grid
@onready var player: PlayerController = $Player

var _last_move_text: String = "Awaiting input"


func _ready() -> void:
	grid.blocked_cells = [
		Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3),
		Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6),
		Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6),
	]
	grid.queue_redraw()
	player.reset_movement_points()
	player.moved.connect(_on_player_moved)
	player.selection_changed.connect(_on_selection_changed)
	queue_redraw()


func _on_player_moved(from_cell: Vector2i, to_cell: Vector2i, points_remaining: int) -> void:
	_last_move_text = "Moved %s → %s" % [from_cell, to_cell]
	queue_redraw()


func _on_selection_changed(selected: bool) -> void:
	_last_move_text = "Player %s" % ("selected" if selected else "deselected")
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("090811"), true)
	draw_rect(Rect2(34, 26, 1212, 668), Color("12101c"), true)
	draw_rect(Rect2(34, 26, 1212, 668), Color("6c5331"), false, 2.0)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(66, 66), "DARK FANTASY // GRID TEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("e2c988"))
	draw_string(font, Vector2(68, 91), "Phase 3 + Phase 4 development harness", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("887d9b"))

	draw_rect(Rect2(900, 112, 308, 512), Color("171522"), true)
	draw_rect(Rect2(900, 112, 308, 512), Color("4d465e"), false, 1.0)
	draw_string(font, Vector2(930, 158), "PLAYER", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c59b52"))
	draw_string(font, Vector2(930, 198), "Cell", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 198), str(player.grid_position), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("f0e7d1"))
	draw_string(font, Vector2(930, 232), "Movement", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 232), "%d / %d" % [player.movement_points_remaining, player.player_stats.movement_points], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("f0e7d1"))
	draw_string(font, Vector2(930, 266), "Status", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 266), "SELECTED" if player.is_selected else "IDLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b7a2d1"))

	draw_string(font, Vector2(930, 334), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c59b52"))
	draw_string(font, Vector2(930, 374), "W A S D", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 374), "Move", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(930, 408), "SPACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 408), "Refresh movement", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(930, 442), "CLICK", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 442), "Toggle selection", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))

	draw_string(font, Vector2(930, 536), "LAST EVENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("887d9b"))
	draw_string(font, Vector2(930, 568), _last_move_text, HORIZONTAL_ALIGNMENT_LEFT, 250, 14, Color("d5cbe0"))
