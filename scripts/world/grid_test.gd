class_name GridTest
extends Node2D

const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")

@onready var grid: GridMap2D = $Grid
@onready var player: PlayerController = $Player
@onready var turn_manager: TurnManager = $TurnManager
@onready var combat_system: CombatSystem = $CombatSystem
@onready var stage_manager: StageManager = $StageManager
@onready var experience_system: ExperienceSystem = $ExperienceSystem

var _last_move_text: String = "Awaiting input"
var _active_enemies: Array[Node] = []


func _ready() -> void:
	grid.blocked_cells = [
		Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3),
		Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6),
		Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6),
	]
	grid.queue_redraw()
	player.reset_movement_points()
	player.moved.connect(_on_player_moved)
	combat_system.attach_turn_manager(turn_manager)
	combat_system.set_player_actor(player)
	combat_system.connect_actor(player)
	combat_system.attack_resolved.connect(_on_attack_resolved)
	combat_system.actor_died.connect(_on_actor_died)
	experience_system.attach_player(player)
	experience_system.attach_combat_system(combat_system)
	experience_system.experience_awarded.connect(_on_experience_awarded)
	experience_system.level_up.connect(_on_level_up)
	turn_manager.state_changed.connect(_on_turn_state_changed)
	stage_manager.stage_started.connect(_on_stage_started)
	stage_manager.enemy_spawned.connect(_on_enemy_spawned)
	stage_manager.stage_completed.connect(_on_stage_completed)
	stage_manager.stage_generation_failed.connect(_on_stage_generation_failed)
	player.selection_changed.connect(_on_selection_changed)
	stage_manager.initialize_stage(1)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("primary_action") and turn_manager.get_phase() == TurnState.VICTORY:
		if stage_manager.start_next_stage():
			get_viewport().set_input_as_handled()


func _on_stage_started(stage_state: StageState, enemies: Array[Node]) -> void:
	_active_enemies = enemies
	for enemy_node in _active_enemies:
		_register_enemy(enemy_node as EnemyController)
	if not _active_enemies.is_empty():
		player.set_target(_active_enemies[0])
	turn_manager.start_combat(player, _active_enemies)
	var encounter_label: String = "MINI BOSS" if stage_state.is_mini_boss_stage else "NORMAL"
	if stage_state.is_special_encounter:
		encounter_label = SpecialEncounterTypeResource.get_display_name(stage_state.special_encounter_type).to_upper()
	_last_move_text = "%s // %s started" % [stage_manager.current_definition.display_name, encounter_label]
	queue_redraw()


func _on_enemy_spawned(enemy: Node) -> void:
	var enemy_controller := enemy as EnemyController
	if enemy_controller == null:
		return
	_active_enemies.append(enemy_controller)
	_register_enemy(enemy_controller)
	turn_manager.add_enemy(enemy_controller)
	_last_move_text = "%s summoned" % enemy_controller.get_display_name()
	queue_redraw()


func _register_enemy(enemy: EnemyController) -> void:
	if enemy == null:
		return
	combat_system.connect_actor(enemy)
	if enemy.has_signal("moved") and not enemy.moved.is_connected(_on_enemy_moved):
		enemy.moved.connect(_on_enemy_moved)
	if enemy.has_signal("attack_requested") and not enemy.attack_requested.is_connected(_on_enemy_attack_requested):
		enemy.attack_requested.connect(_on_enemy_attack_requested)


func _on_stage_completed(stage_state: StageState) -> void:
	_last_move_text = "STAGE %d CLEARED — SPACE FOR NEXT STAGE" % stage_state.stage_number
	turn_manager.set_victory()
	queue_redraw()


func _on_stage_generation_failed(stage_number: int, reason: String) -> void:
	_last_move_text = "Stage %d failed: %s" % [stage_number, reason]
	queue_redraw()


func _on_player_moved(from_cell: Vector2i, to_cell: Vector2i, points_remaining: int) -> void:
	_last_move_text = "Moved %s → %s" % [from_cell, to_cell]
	queue_redraw()


func _on_enemy_moved(from_cell: Vector2i, to_cell: Vector2i) -> void:
	_last_move_text = "Enemy moved %s → %s" % [from_cell, to_cell]
	queue_redraw()


func _on_enemy_attack_requested(_enemy: EnemyController, _target: Node) -> void:
	_last_move_text = "Enemy attack requested"
	queue_redraw()


func _on_attack_resolved(result: DamageResult) -> void:
	if result.is_miss:
		_last_move_text = "Attack missed: target out of range"
	else:
		_last_move_text = "Critical hit for %d" % result.final_damage if result.is_critical else "Hit for %d" % result.final_damage
	queue_redraw()


func _on_experience_awarded(amount: int, _current_experience: int, _required_experience: int, source_name: String) -> void:
	_last_move_text = "Gained %d EXP%s" % [amount, " from %s" % source_name if not source_name.is_empty() else ""]
	queue_redraw()


func _on_level_up(new_level: int, _max_hp_gain: int, _attack_gain: int, _defense_gain: int) -> void:
	_last_move_text = "LEVEL UP — Player reached level %d" % new_level
	queue_redraw()


func _on_actor_died(actor: Node) -> void:
	if actor == player:
		_last_move_text = "PLAYER DEFEATED"
		turn_manager.set_defeat()
	else:
		_last_move_text = "Enemy defeated"
		_select_next_target()
	queue_redraw()


func _select_next_target() -> void:
	for enemy_node in _active_enemies:
		var enemy := enemy_node as EnemyController
		if enemy != null and is_instance_valid(enemy) and not enemy.is_defeated():
			player.set_target(enemy)
			return


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
	draw_string(font, Vector2(66, 66), "DARK FANTASY // STAGE GENERATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("e2c988"))
	draw_string(font, Vector2(68, 91), "Phase 12 EXP / Level harness", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("887d9b"))

	draw_rect(Rect2(900, 112, 308, 570), Color("171522"), true)
	draw_rect(Rect2(900, 112, 308, 570), Color("4d465e"), false, 1.0)
	var stage_title: String = "STAGE %d" % stage_manager.stage_state.stage_number
	if stage_manager.stage_state.is_mini_boss_stage:
		stage_title += " // MINI BOSS"
	elif stage_manager.stage_state.is_special_encounter:
		stage_title += " // " + SpecialEncounterTypeResource.get_display_name(stage_manager.stage_state.special_encounter_type).to_upper()
	draw_string(font, Vector2(930, 158), stage_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c59b52"))
	draw_string(font, Vector2(930, 181), "Enemies %d / %d" % [stage_manager.stage_state.defeated_enemy_count, stage_manager.stage_state.spawned_enemy_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9c91ad"))
	draw_string(font, Vector2(930, 217), "PLAYER", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c59b52"))
	draw_string(font, Vector2(930, 257), "Cell", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 257), str(player.grid_position), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("f0e7d1"))
	draw_string(font, Vector2(930, 291), "Movement", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 291), "%d / %d" % [player.movement_points_remaining, player.player_stats.movement_points], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("f0e7d1"))
	draw_string(font, Vector2(930, 325), "Status", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 325), "SELECTED" if player.is_selected else "IDLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b7a2d1"))
	draw_string(font, Vector2(930, 359), "Turn", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 359), _turn_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e2c988"))
	draw_string(font, Vector2(930, 393), "Level", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 393), str(player.get_level()), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("e2c988"))
	draw_string(font, Vector2(930, 427), "EXP", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(1088, 427), "%d / %d" % [player.get_experience(), player.get_experience_to_next_level()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f0e7d1"))
	var enemy_y: int = 463
	for enemy_node in _active_enemies:
		var enemy := enemy_node as EnemyController
		if enemy == null or not is_instance_valid(enemy):
			continue
		var enemy_stats: EnemyStats = enemy.enemy_stats
		if enemy_stats == null:
			continue
		var enemy_label: String = "%s Lv.%d" % [enemy.get_display_name(), enemy.enemy_level]
		if enemy.is_mini_boss:
			enemy_label += " [%s]" % enemy.get_boss_behavior_name()
		draw_string(font, Vector2(930, enemy_y), enemy_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9c91ad"))
		draw_string(font, Vector2(1088, enemy_y), "%d / %d" % [enemy_stats.current_hp, enemy_stats.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f0e7d1"))
		enemy_y += 24

	draw_string(font, Vector2(930, 570), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c59b52"))
	draw_string(font, Vector2(930, 596), "W A S D", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 596), "Move", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(930, 620), "SPACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 620), "End turn / Next stage", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))
	draw_string(font, Vector2(930, 644), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c988"))
	draw_string(font, Vector2(1030, 644), "Attack target", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9c91ad"))

	draw_string(font, Vector2(930, 668), "LAST EVENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("887d9b"))
	draw_string(font, Vector2(930, 686), _last_move_text, HORIZONTAL_ALIGNMENT_LEFT, 250, 12, Color("d5cbe0"))


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
