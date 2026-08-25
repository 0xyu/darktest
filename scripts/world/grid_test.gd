class_name GridTest
extends Node2D

@onready var grid: GridMap2D = $Grid
@onready var player: PlayerController = $Player
@onready var enemy: EnemyController = $Enemy
@onready var turn_manager: TurnManager = $TurnManager
@onready var combat_system: CombatSystem = $CombatSystem

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
	enemy.moved.connect(_on_enemy_moved)
	enemy.attack_requested.connect(_on_enemy_attack_requested)
	combat_system.attach_turn_manager(turn_manager)
	combat_system.set_player_actor(player)
	combat_system.connect_actor(player)
	combat_system.connect_actor(enemy)
	combat_system.attack_resolved.connect(_on_attack_resolved)
	combat_system.actor_died.connect(_on_actor_died)
	turn_manager.state_changed.connect(_on_turn_state_changed)
	turn_manager.start_combat(player, [enemy])
	player.selection_changed.connect(_on_selection_changed)
	queue_redraw()


func _on_player_moved(from_cell: Vector2i, to_cell: Vector2i, points_remaining: int) -> void:
	_last_move_text = "Moved %s → %s" % [from_cell, to_cell]
	queue_redraw()


func _on_enemy_moved(from_cell: Vector2i, to_cell: Vector2i) -> void:
	_last_move_text = "Enemy moved %s → %s" % [from_cell, to_cell]
	queue_redraw()


func _on_enemy_attack_requested(_enemy: EnemyController, _target: Node) -> void:
	_last_move_text = "Enemy attack requested (damage in Phase 7)"
	queue_redraw()


func _on_attack_resolved(result: DamageResult) -> void:
	if result.is_miss:
		_last_move_text = "Attack missed: target out of range"
	else:
		_last_move_text = "Critical hit for %d" % result.final_damage if result.is_critical else "Hit for %d" % result.final_damage
	queue_redraw()


func _on_actor_died(actor: Node) -> void:
	if actor == player:
		_last_move_text = "PLAYER DEFEATED"
		turn_manager.set_defeat()
	elif actor == enemy:
		_last_move_text = "ENEMY DEFEATED"
		turn_manager.set_victory()
	queue_redraw()


func _on_turn_state_changed(_state: TurnState) -> void:
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
	draw_string(font, Vector2(930, 300), "Turn", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 300), _turn_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e2c988"))
	draw_string(font, Vector2(930, 334), "Enemy HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 334), "%d / %d" % [enemy.enemy_stats.current_hp, enemy.enemy_stats.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("f0e7d1"))

	draw_string(font, Vector2(930, 390), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c59b52"))
	draw_string(font, Vector2(930, 430), "W A S D", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 430), "Move", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(930, 464), "SPACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 464), "End player turn", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(930, 498), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 498), "Attack training enemy", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(930, 532), "CLICK", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 532), "Toggle selection", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))

	draw_string(font, Vector2(930, 566), "LAST EVENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("887d9b"))
	draw_string(font, Vector2(930, 598), _last_move_text, HORIZONTAL_ALIGNMENT_LEFT, 250, 14, Color("d5cbe0"))


func _turn_label() -> String:
	if turn_manager == null:
		return "-"
	match turn_manager.get_phase():
		TurnState.PLAYER_TURN:
			return "PLAYER"
		TurnState.ENEMY_TURN:
			return "ENEMY"
		TurnState.VICTORY:
			return "VICTORY"
		TurnState.DEFEAT:
			return "DEFEAT"
		_:
			return "-"
