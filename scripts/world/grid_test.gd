class_name GridTest
extends Node2D

const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")

@onready var grid: GridMap2D = $Grid
@onready var player: PlayerController = $Player
@onready var turn_manager: TurnManager = $TurnManager
@onready var combat_system: CombatSystem = $CombatSystem
@onready var stage_manager: StageManager = $StageManager
@onready var experience_system: ExperienceSystem = $ExperienceSystem
@onready var hud: MobileCombatHUD = $MobileCombatHUD
@onready var gold_system = $GoldSystem
@onready var loot_system = $LootSystem
@onready var auto_combat: AutoCombatController = $AutoCombatController

var _last_move_text: String = "Awaiting input"
var _active_enemies: Array[Node] = []
var _grid_play_area: Rect2 = Rect2()


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
	gold_system.attach_player(player)
	gold_system.attach_combat_system(combat_system)
	gold_system.attach_stage_manager(stage_manager)
	gold_system.gold_awarded.connect(_on_gold_awarded)
	loot_system.attach_combat_system(combat_system)
	loot_system.attach_stage_manager(stage_manager)
	loot_system.loot_dropped.connect(_on_loot_dropped)
	turn_manager.state_changed.connect(_on_turn_state_changed)
	stage_manager.stage_started.connect(_on_stage_started)
	stage_manager.enemy_spawned.connect(_on_enemy_spawned)
	stage_manager.stage_completed.connect(_on_stage_completed)
	stage_manager.stage_generation_failed.connect(_on_stage_generation_failed)
	player.selection_changed.connect(_on_selection_changed)
	player.equipment_effect_triggered.connect(_on_equipment_effect_triggered)
	hud.move_requested.connect(_on_hud_move_requested)
	hud.attack_requested.connect(_on_hud_attack_requested)
	hud.end_turn_requested.connect(_on_hud_end_turn_requested)
	hud.auto_toggle_requested.connect(_on_hud_auto_toggle_requested)
	auto_combat.attach_systems(player, turn_manager, combat_system, stage_manager, grid)
	auto_combat.auto_mode_changed.connect(_on_auto_mode_changed)
	auto_combat.auto_action_taken.connect(_on_auto_action_taken)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_layout_portrait_grid()
	stage_manager.initialize_stage(1)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_auto") and turn_manager.get_phase() != TurnState.DEFEAT:
		auto_combat.toggle_auto()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("primary_action") and turn_manager.get_phase() == TurnState.VICTORY:
		if stage_manager.start_next_stage():
			get_viewport().set_input_as_handled()


func _on_hud_move_requested(direction: Vector2i) -> void:
	player.try_move(direction)


func _on_hud_attack_requested() -> void:
	if turn_manager.get_phase() != TurnState.PLAYER_TURN or not player.is_input_enabled():
		return
	player.attack_requested.emit(player, player.get_target())


func _on_hud_end_turn_requested() -> void:
	if turn_manager.get_phase() == TurnState.VICTORY:
		stage_manager.start_next_stage()
	elif turn_manager.get_phase() == TurnState.PLAYER_TURN:
		turn_manager.complete_player_turn()


func _on_hud_auto_toggle_requested() -> void:
	auto_combat.toggle_auto()


func _on_auto_mode_changed(enabled: bool) -> void:
	hud.set_auto_mode(enabled)
	_last_move_text = "AUTO MODE %s" % ("ENABLED" if enabled else "DISABLED")
	queue_redraw()


func _on_auto_action_taken(description: String) -> void:
	if not description.is_empty():
		_last_move_text = description
		queue_redraw()


func _on_viewport_size_changed() -> void:
	_layout_portrait_grid()
	queue_redraw()


func _layout_portrait_grid() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var top_reserved: float = clampf(viewport_size.y * 0.14, 180.0, 210.0)
	var bottom_reserved: float = clampf(viewport_size.y * 0.28, 338.0, 390.0)
	var side_margin: float = clampf(viewport_size.x * 0.045, 18.0, 36.0)
	var available_size := Vector2(
		maxf(viewport_size.x - side_margin * 2.0, 1.0),
		maxf(viewport_size.y - top_reserved - bottom_reserved - 24.0, 1.0)
	)
	var cell_size: int = maxi(floori(minf(
		available_size.x / float(grid.grid_size.x),
		available_size.y / float(grid.grid_size.y)
	)), 1)
	var grid_pixel_size := Vector2(grid.grid_size * cell_size)
	var play_area_top: float = top_reserved + 12.0
	var play_area_height: float = maxf(viewport_size.y - top_reserved - bottom_reserved - 24.0, grid_pixel_size.y)
	grid.cell_size = cell_size
	grid.origin = Vector2(
		(viewport_size.x - grid_pixel_size.x) * 0.5,
		play_area_top + (play_area_height - grid_pixel_size.y) * 0.5
	)
	_grid_play_area = Rect2(grid.origin - Vector2(8.0, 8.0), grid_pixel_size + Vector2(16.0, 16.0))
	grid.queue_redraw()
	player.global_position = grid.grid_to_world(player.grid_position)
	for enemy_node in _active_enemies:
		var enemy := enemy_node as EnemyController
		if enemy != null and is_instance_valid(enemy):
			enemy.global_position = grid.grid_to_world(enemy.grid_position)


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


func _on_gold_awarded(amount: int, _current_gold: int, source_name: String) -> void:
	_last_move_text = "Gained %d Gold%s" % [amount, " from %s" % source_name if not source_name.is_empty() else ""]
	queue_redraw()


func _on_loot_dropped(_enemy: Node, loot: Array[EquipmentInstance]) -> void:
	var loot_names: Array[String] = []
	var added_count: int = 0
	for item in loot:
		if item != null:
			loot_names.append(item.get_display_name())
			if player.add_equipment(item):
				added_count += 1
	if added_count == loot.size():
		_last_move_text = "Loot added: %s (%d/%d)" % [", ".join(loot_names), player.get_inventory().get_item_count(), player.get_inventory().capacity]
	else:
		_last_move_text = "Loot added %d/%d — inventory full" % [added_count, loot.size()]
	queue_redraw()


func _on_equipment_effect_triggered(_effect_id: StringName, description: String) -> void:
	_last_move_text = "EFFECT // %s" % description
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
	var viewport_size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("090811"), true)
	draw_rect(Rect2(Vector2(10.0, 10.0), viewport_size - Vector2(20.0, 20.0)), Color("12101c"), true)
	draw_rect(Rect2(Vector2(10.0, 10.0), viewport_size - Vector2(20.0, 20.0)), Color("6c5331"), false, 2.0)
	if _grid_play_area.size.x > 0.0:
		draw_rect(_grid_play_area, Color("0b0a10", 0.92), true)
		draw_rect(_grid_play_area, Color("4d465e", 0.85), false, 1.0)


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
