class_name GridTest
extends Node2D

const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")
const SubHeroAttackEffectResource = preload("res://scripts/combat/sub_hero_attack_effect.gd")

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
@onready var sub_hero_combat_manager: SubHeroCombatManager = $SubHeroCombatManager

var _last_move_text: String = "Awaiting input"
var _active_enemies: Array[Node] = []
var _grid_play_area: Rect2 = Rect2()
var _defeat_retry_scheduled: bool = false


func _ready() -> void:
	grid.queue_redraw()
	player.reset_movement_points()
	player.moved.connect(_on_player_moved)
	combat_system.attach_turn_manager(turn_manager)
	combat_system.set_player_actor(player)
	combat_system.connect_actor(player)
	combat_system.attack_resolved.connect(_on_attack_resolved)
	combat_system.skill_resolved.connect(_on_skill_resolved)
	combat_system.skill_failed.connect(_on_skill_failed)
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
	player.sub_hero_slots_changed.connect(_on_sub_hero_slots_changed)
	sub_hero_combat_manager.attack_resolved.connect(_on_sub_hero_attack_resolved)
	sub_hero_combat_manager.attack_feedback_requested.connect(_on_sub_hero_attack_feedback_requested)
	sub_hero_combat_manager.cooldown_started.connect(_on_sub_hero_cooldown_started)
	sub_hero_combat_manager.combat_cleared.connect(_on_sub_hero_combat_cleared)
	sub_hero_combat_manager.combat_state_changed.connect(_on_sub_hero_combat_state_changed)
	hud.move_requested.connect(_on_hud_move_requested)
	hud.attack_requested.connect(_on_hud_attack_requested)
	hud.skill_requested.connect(_on_hud_skill_requested)
	hud.item_requested.connect(_on_hud_item_requested)
	hud.end_turn_requested.connect(_on_hud_end_turn_requested)
	hud.auto_toggle_requested.connect(_on_hud_auto_toggle_requested)
	hud.auto_stage_toggle_requested.connect(_on_hud_auto_stage_toggle_requested)
	hud.game_speed_requested.connect(_on_hud_game_speed_requested)
	auto_combat.attach_systems(player, turn_manager, combat_system, stage_manager, grid)
	auto_combat.auto_mode_changed.connect(_on_auto_mode_changed)
	auto_combat.auto_stage_changed.connect(_on_auto_stage_changed)
	auto_combat.auto_action_taken.connect(_on_auto_action_taken)
	auto_combat.game_speed_changed.connect(_on_game_speed_changed)
	hud.set_auto_stage_mode(auto_combat.is_auto_stage_enabled())
	hud.set_game_speed(auto_combat.get_game_speed())
	_sync_sub_hero_combatants()
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


func _on_hud_skill_requested(skill_id: StringName) -> void:
	if turn_manager.get_phase() != TurnState.PLAYER_TURN or not player.is_input_enabled():
		return
	player.skill_requested.emit(player, player.get_target(), skill_id)


func can_use_skill(skill_id: StringName) -> bool:
	if player == null or combat_system == null:
		return false
	return combat_system.can_use_skill(player, skill_id, player.get_target())


func _on_hud_item_requested() -> void:
	if turn_manager.get_phase() != TurnState.PLAYER_TURN or not player.is_input_enabled():
		return
	if player.use_healing_item():
		_last_move_text = "Used healing item"
		turn_manager.complete_player_turn()
		queue_redraw()


func _on_hud_end_turn_requested() -> void:
	if turn_manager.get_phase() == TurnState.VICTORY:
		stage_manager.start_next_stage()
	elif turn_manager.get_phase() == TurnState.PLAYER_TURN:
		turn_manager.complete_player_turn()


func _on_hud_auto_toggle_requested() -> void:
	auto_combat.toggle_auto()


func _on_hud_auto_stage_toggle_requested() -> void:
	auto_combat.toggle_auto_stage()


func _on_hud_game_speed_requested(speed: int) -> void:
	auto_combat.set_game_speed(speed)


func _on_game_speed_changed(speed: int) -> void:
	hud.set_game_speed(speed)
	_last_move_text = "GAME SPEED %s" % auto_combat.get_game_speed_label()
	queue_redraw()


func _on_auto_mode_changed(enabled: bool) -> void:
	hud.set_auto_mode(enabled)
	_last_move_text = "AUTO MODE %s" % ("ENABLED" if enabled else "DISABLED")
	queue_redraw()


func _on_auto_stage_changed(enabled: bool) -> void:
	hud.set_auto_stage_mode(enabled)
	_last_move_text = "AUTO STAGE %s" % ("NEXT STAGE" if enabled else "STAY & REFRESH")
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
	var top_reserved: float = clampf(viewport_size.y * 0.17, 220.0, 240.0)
	var bottom_reserved: float = clampf(viewport_size.y * 0.36, 450.0, 480.0)
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
	hud.layout_battle_support(grid.origin.y + grid_pixel_size.y, viewport_size)
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
	combat_system.set_combat_targets(_active_enemies)
	turn_manager.start_combat(player, _active_enemies)
	_sync_sub_hero_combatants()
	sub_hero_combat_manager.start_combat(_active_enemies)
	var encounter_label: String = "MINI BOSS" if stage_state.is_mini_boss_stage else "NORMAL"
	if stage_state.is_special_encounter:
		encounter_label = SpecialEncounterTypeResource.get_display_name(stage_state.special_encounter_type).to_upper()
	_last_move_text = "%s // %s started" % [stage_manager.current_definition.display_name, encounter_label]
	hud.log_event("log.stage_start", {"stage": stage_state.stage_number})
	queue_redraw()


func _on_enemy_spawned(enemy: Node) -> void:
	var enemy_controller := enemy as EnemyController
	if enemy_controller == null:
		return
	_active_enemies.append(enemy_controller)
	_register_enemy(enemy_controller)
	combat_system.set_combat_targets(_active_enemies)
	turn_manager.add_enemy(enemy_controller)
	sub_hero_combat_manager.add_enemy(enemy_controller)
	_last_move_text = "%s summoned" % enemy_controller.get_display_name()
	hud.log_event("log.enemy_summoned", {"name": enemy_controller.get_display_name()})
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
	sub_hero_combat_manager.stop_combat()
	_last_move_text = "STAGE %d CLEARED — SPACE FOR NEXT STAGE" % stage_state.stage_number
	hud.log_event("log.stage_clear", {"stage": stage_state.stage_number})
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
		if result.is_critical:
			hud.show_critical_indicator(result.final_damage)
	queue_redraw()


func _on_skill_resolved(skill_id: StringName, hit_count: int) -> void:
	var skill := SkillCatalog.get_skill(skill_id)
	_last_move_text = "%s hit %d target%s" % [skill.display_name, hit_count, "" if hit_count == 1 else "s"]
	queue_redraw()


func _on_skill_failed(skill_id: StringName, reason: String) -> void:
	var skill := SkillCatalog.get_skill(skill_id)
	_last_move_text = "%s unavailable: %s" % [skill.display_name, reason]
	queue_redraw()


func _on_experience_awarded(amount: int, _current_experience: int, _required_experience: int, source_name: String) -> void:
	_last_move_text = "Gained %d EXP%s" % [amount, " from %s" % source_name if not source_name.is_empty() else ""]
	queue_redraw()


func _on_level_up(new_level: int, _max_hp_gain: int, _attack_gain: int, _defense_gain: int) -> void:
	_last_move_text = "LEVEL UP — Player reached level %d" % new_level
	hud.log_event("log.level_up", {"level": new_level})
	queue_redraw()


func _on_gold_awarded(amount: int, _current_gold: int, source_name: String) -> void:
	_last_move_text = "Gained %d Gold%s" % [amount, " from %s" % source_name if not source_name.is_empty() else ""]
	hud.log_event("log.gold_gained", {"amount": amount})
	queue_redraw()


func _on_loot_dropped(_enemy: Node, loot: Array[EquipmentInstance]) -> void:
	var loot_names: Array[String] = []
	var new_best_items: Array[EquipmentInstance] = []
	var added_count: int = 0
	var stowed_count: int = 0
	for item in loot:
		if item == null:
			continue
		loot_names.append(item.get_display_name())
		var comparison: EquipmentComparison = player.get_inventory().create_comparison(item)
		var is_upgrade: bool = comparison != null and comparison.is_upgrade()
		if player.add_equipment(item):
			added_count += 1
		elif player.add_to_storage(item):
			stowed_count += 1
		else:
			continue
		if is_upgrade:
			new_best_items.append(item)
	var inventory: EquipmentInventory = player.get_inventory()
	if added_count + stowed_count == loot.size():
		_last_move_text = "Loot added: %s (%d/%d)" % [", ".join(loot_names), inventory.get_item_count(), inventory.capacity]
	else:
		_last_move_text = "Loot added %d/%d — bag full" % [added_count + stowed_count, loot.size()]
	if stowed_count > 0:
		_last_move_text += "  (%d stored)" % stowed_count
	if not loot_names.is_empty():
		hud.log_event("log.loot_found", {"items": ", ".join(loot_names)})
	hud.present_loot(loot, new_best_items, str(_enemy.get("enemy_id")) if _enemy != null else "")
	queue_redraw()


func _on_equipment_effect_triggered(_effect_id: StringName, description: String) -> void:
	_last_move_text = "EFFECT // %s" % description
	queue_redraw()


func _on_sub_hero_slots_changed() -> void:
	_sync_sub_hero_combatants()


func _sync_sub_hero_combatants() -> void:
	sub_hero_combat_manager.clear_active_sub_heroes()
	if player == null or not player.has_method("get_active_sub_hero_entries"):
		return
	for entry in player.get_active_sub_hero_entries():
		var data := entry.get("data") as SubHeroData
		var instance := entry.get("instance") as SubHeroInstance
		if data != null and instance != null:
			sub_hero_combat_manager.register_active_sub_hero(instance, data)
	if sub_hero_combat_manager.is_combat_running():
		sub_hero_combat_manager.start_combat(_active_enemies)


func _on_sub_hero_attack_resolved(result: DamageResult) -> void:
	if result == null or result.is_miss:
		return
	hud.show_sub_hero_attack_feedback(result.attacker_id, result.final_damage)
	_last_move_text = "Sub Hero hit for %d" % result.final_damage
	queue_redraw()


func _on_sub_hero_attack_feedback_requested(result: DamageResult, target: Node) -> void:
	if result == null or result.is_miss or target == null or not is_instance_valid(target) or not target is Node2D:
		return
	var origin: Vector2 = hud.get_sub_hero_attack_origin(result.attacker_id)
	var destination: Vector2 = (target as Node2D).get_global_transform_with_canvas().origin
	if origin == Vector2.ZERO:
		origin = destination + Vector2(0.0, 40.0)
	var effect := SubHeroAttackEffectResource.new()
	hud.add_child(effect)
	effect.setup(origin, destination)


func _on_sub_hero_cooldown_started(hero_id: StringName, duration: float) -> void:
	hud.start_sub_hero_cooldown(hero_id, duration)


func _on_sub_hero_combat_state_changed(is_running: bool) -> void:
	if is_running:
		hud.reset_sub_hero_cooldowns()


func _on_sub_hero_combat_cleared() -> void:
	stage_manager.complete_stage_if_cleared()


func _on_actor_died(actor: Node) -> void:
	if actor == player:
		sub_hero_combat_manager.stop_combat()
		_last_move_text = "PLAYER DEFEATED"
		hud.log_event("log.player_defeated")
		turn_manager.set_defeat()
		if not _defeat_retry_scheduled:
			_defeat_retry_scheduled = true
			call_deferred("_retry_previous_stage_after_defeat")
	else:
		var enemy := actor as EnemyController
		_last_move_text = "Enemy defeated"
		if enemy != null:
			hud.log_event("log.kill_exp", {
				"name": enemy.get_display_name(),
				"amount": experience_system.calculate_enemy_experience(enemy),
			})
		_select_next_target()
	queue_redraw()


func _retry_previous_stage_after_defeat() -> void:
	_defeat_retry_scheduled = false
	if turn_manager.get_phase() != TurnState.DEFEAT or not player.is_defeated():
		return

	player.revive_for_retry()
	var retry_stage: int = maxi(stage_manager.stage_state.stage_number - 1, 1)
	if stage_manager.start_previous_stage():
		_last_move_text = "DEFEAT — RETURNED TO STAGE %02d" % retry_stage
	else:
		player.handle_defeat()
		_last_move_text = "DEFEAT — RETRY FAILED"
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
