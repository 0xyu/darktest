class_name PlayerController
extends Node2D

signal moved(from_cell: Vector2i, to_cell: Vector2i, movement_points_remaining: int)
signal selection_changed(is_selected: bool)
signal action_completed
signal attack_requested(attacker: Node, target: Node)
signal defeated
signal experience_gained(amount: int, current_experience: int, required_experience: int)
signal level_up(new_level: int)
signal equipment_effect_triggered(effect_id: StringName, description: String)
signal healing_item_used(remaining_items: int, amount_healed: int)

@export var grid_path: NodePath
@export var player_id: StringName = &"player"
@export var grid_position: Vector2i = Vector2i(1, 1)
@export var player_stats: PlayerStats = PlayerStats.new()
@export var player_progression: PlayerProgression = PlayerProgression.new()
@export var equipment_inventory: EquipmentInventory
@export var is_selected: bool = true
@export var target_path: NodePath
@export_range(0, 99, 1) var healing_item_count: int = 3
@export_range(0.05, 1.0, 0.05) var healing_item_heal_ratio: float = 0.35

var movement_points_remaining: int = 0
var _grid: GridMap2D
var _input_enabled: bool = true
var _turn_manager: Node
var _is_defeated: bool = false
var _target: Node
var _applied_equipment_bonuses: Dictionary = {}
var _attack_count: int = 0
var _cells_moved_since_attack: int = 0


func _ready() -> void:
	_ensure_equipment_inventory()
	_refresh_equipment_stats()
	_grid = get_node_or_null(grid_path) as GridMap2D
	if _grid == null:
		push_error("PlayerController requires a GridMap2D assigned through grid_path.")
		return
	if not _grid.is_walkable(grid_position):
		grid_position = Vector2i.ZERO
	if not _grid.is_occupied(grid_position):
		_grid.set_occupied(grid_position, player_id)
	global_position = _grid.grid_to_world(grid_position)
	reset_movement_points()
	_input_enabled = true
	_refresh_grid_feedback()
	queue_redraw()


func set_equipment_inventory(inventory: EquipmentInventory) -> void:
	if equipment_inventory != null and equipment_inventory.equipment_changed.is_connected(_on_equipment_changed):
		equipment_inventory.equipment_changed.disconnect(_on_equipment_changed)
	equipment_inventory = inventory
	_ensure_equipment_inventory()
	_refresh_equipment_stats()


func get_inventory() -> EquipmentInventory:
	_ensure_equipment_inventory()
	return equipment_inventory


func add_equipment(item: EquipmentInstance) -> bool:
	return get_inventory().add_item(item)


func equip_item(item: EquipmentInstance) -> bool:
	return get_inventory().equip_item(item)


func unequip_item(slot: int) -> EquipmentInstance:
	return get_inventory().unequip_item(slot)


func get_equipped_item(slot: int) -> EquipmentInstance:
	return get_inventory().get_equipped_item(slot)


func get_equipped_items() -> Array[EquipmentInstance]:
	return get_inventory().get_equipped_items()


func select_item(item: EquipmentInstance) -> bool:
	return get_inventory().select_item(item)


func get_selected_item() -> EquipmentInstance:
	return get_inventory().get_selected_item()


func get_healing_item_count() -> int:
	return maxi(healing_item_count, 0)


func use_healing_item() -> bool:
	if player_stats == null or get_healing_item_count() <= 0:
		return false
	if player_stats.current_hp <= 0 or player_stats.current_hp >= player_stats.max_hp:
		return false
	var previous_hp: int = player_stats.current_hp
	var heal_amount: int = maxi(roundi(float(player_stats.max_hp) * clampf(healing_item_heal_ratio, 0.0, 1.0)), 1)
	player_stats.current_hp = mini(player_stats.current_hp + heal_amount, player_stats.max_hp)
	healing_item_count -= 1
	healing_item_used.emit(healing_item_count, player_stats.current_hp - previous_hp)
	queue_redraw()
	return true


func discard_item(item: EquipmentInstance) -> bool:
	return get_inventory().discard_item(item)


func compare_equipment(item: EquipmentInstance) -> Dictionary:
	return get_inventory().compare_item(item)


func create_attack_context(target: Node) -> Dictionary:
	_attack_count += 1
	var context := {
		"attack_number": _attack_count,
		"cells_moved": _cells_moved_since_attack,
		"attacking_from_behind": _is_attacking_from_behind(target),
		"target_poisoned": _is_target_poisoned(target),
	}
	_cells_moved_since_attack = 0
	return context


func get_equipment_damage_multiplier(target: Node, attack_context: Dictionary) -> float:
	var multiplier: float = 1.0
	for effect in get_inventory().get_equipped_effects():
		multiplier *= maxf(effect.get_damage_multiplier(self, target, attack_context), 0.0)
	return multiplier


func apply_equipment_attack_effects(target: Node, result: DamageResult, attack_context: Dictionary) -> void:
	for effect in get_inventory().get_equipped_effects():
		effect.on_attack_resolved(self, target, result, attack_context)


func heal_from_equipment_effect(max_hp_ratio: float, effect_id: StringName, description: String) -> int:
	if player_stats == null or player_stats.current_hp <= 0:
		return 0
	var heal_amount: int = maxi(roundi(float(player_stats.max_hp) * clampf(max_hp_ratio, 0.0, 1.0)), 1)
	var previous_hp: int = player_stats.current_hp
	player_stats.current_hp = mini(player_stats.current_hp + heal_amount, player_stats.max_hp)
	var actual_heal: int = player_stats.current_hp - previous_hp
	if actual_heal > 0:
		equipment_effect_triggered.emit(effect_id, description)
	return actual_heal


func reset_equipment_effect_state() -> void:
	_attack_count = 0
	_cells_moved_since_attack = 0


func _is_attacking_from_behind(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_attacked_from_behind"):
		return bool(target.is_attacked_from_behind(grid_position))
	var facing_variant: Variant = target.get("facing_direction")
	if facing_variant is Vector2i:
		var relative_cell: Vector2i = grid_position - _get_target_grid_position(target)
		return relative_cell == -(facing_variant as Vector2i)
	return false


func _is_target_poisoned(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_poisoned"):
		return bool(target.is_poisoned())
	return bool(target.get("poisoned"))


func _get_target_grid_position(target: Node) -> Vector2i:
	if target.has_method("get_grid_position"):
		return target.get_grid_position()
	var target_cell: Variant = target.get("grid_position")
	return target_cell as Vector2i if target_cell is Vector2i else Vector2i.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if _grid == null:
		return
	if event.is_action_pressed("move_up"):
		try_move(Vector2i.UP)
	elif event.is_action_pressed("move_right"):
		try_move(Vector2i.RIGHT)
	elif event.is_action_pressed("move_down"):
		try_move(Vector2i.DOWN)
	elif event.is_action_pressed("move_left"):
		try_move(Vector2i.LEFT)
	elif event.is_action_pressed("primary_action"):
		if _turn_manager != null:
			action_completed.emit()
		else:
			reset_movement_points()
	elif event.is_action_pressed("attack"):
		if _input_enabled and is_selected:
			attack_requested.emit(self, _get_attack_target())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked_cell: Vector2i = _grid.world_to_grid(get_global_mouse_position())
		if clicked_cell == grid_position:
			set_selected(not is_selected)


func try_move(direction: Vector2i) -> bool:
	if not _input_enabled or not is_selected or movement_points_remaining <= 0 or _grid == null:
		return false
	var target_cell: Vector2i = grid_position + direction
	if not _grid.is_walkable(target_cell) or _grid.is_occupied(target_cell):
		return false

	var previous_cell: Vector2i = grid_position
	_grid.clear_occupied(previous_cell, player_id)
	_grid.set_occupied(target_cell, player_id)
	grid_position = target_cell
	movement_points_remaining -= 1
	_cells_moved_since_attack += 1
	global_position = _grid.grid_to_world(grid_position)
	_refresh_grid_feedback()
	queue_redraw()
	moved.emit(previous_cell, grid_position, movement_points_remaining)
	return true


func reset_movement_points() -> void:
	if player_stats == null:
		return
	movement_points_remaining = maxi(player_stats.movement_points, 0)
	_refresh_grid_feedback()
	queue_redraw()


func begin_player_turn(movement_points: int = -1) -> void:
	_input_enabled = true
	if movement_points >= 0:
		movement_points_remaining = movement_points
		_refresh_grid_feedback()
		queue_redraw()
	else:
		reset_movement_points()


func end_player_turn() -> void:
	_input_enabled = false
	_refresh_grid_feedback()
	queue_redraw()


func attach_turn_manager(turn_manager: Node) -> void:
	_turn_manager = turn_manager


func set_target(target: Node) -> void:
	_target = target


func get_target() -> Node:
	return _get_attack_target()


func is_input_enabled() -> bool:
	return _input_enabled


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	_refresh_grid_feedback()
	queue_redraw()
	selection_changed.emit(is_selected)


func get_grid_position() -> Vector2i:
	return grid_position


func handle_defeat() -> void:
	if _is_defeated:
		return
	_is_defeated = true
	player_stats.current_hp = 0
	_input_enabled = false
	if _grid != null:
		_grid.clear_occupied(grid_position, player_id)
	queue_redraw()
	defeated.emit()


func is_defeated() -> bool:
	return _is_defeated


func _ensure_equipment_inventory() -> void:
	if equipment_inventory == null:
		equipment_inventory = EquipmentInventory.new()
	if not equipment_inventory.equipment_changed.is_connected(_on_equipment_changed):
		equipment_inventory.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed(_slot: int, _equipped_item: EquipmentInstance, _previous_item: EquipmentInstance) -> void:
	_refresh_equipment_stats()


func _refresh_equipment_stats() -> void:
	if player_stats == null:
		return
	if equipment_inventory == null:
		return
	_adjust_stats(_applied_equipment_bonuses, -1.0)
	_applied_equipment_bonuses = equipment_inventory.get_equipped_stat_totals()
	_adjust_stats(_applied_equipment_bonuses, 1.0)
	player_stats.clamp_current_hp()
	if movement_points_remaining > 0:
		movement_points_remaining = mini(movement_points_remaining, maxi(player_stats.movement_points, 0))
	queue_redraw()


func _adjust_stats(bonuses: Dictionary, direction: float) -> void:
	if player_stats == null:
		return
	player_stats.attack += roundi(float(bonuses.get(&"attack", 0.0)) * direction)
	player_stats.defense += roundi(float(bonuses.get(&"defense", 0.0)) * direction)
	player_stats.max_hp += roundi(float(bonuses.get(&"hp", 0.0)) * direction)
	player_stats.critical_chance += float(bonuses.get(&"critical_chance", 0.0)) * direction
	player_stats.critical_damage += float(bonuses.get(&"critical_damage", 0.0)) * direction
	player_stats.dodge += float(bonuses.get(&"dodge", 0.0)) * direction
	player_stats.movement_points += roundi(float(bonuses.get(&"movement", 0.0)) * direction)
	player_stats.attack_range += roundi(float(bonuses.get(&"attack_range", 0.0)) * direction)
	player_stats.life_steal += float(bonuses.get(&"life_steal", 0.0)) * direction


func get_level() -> int:
	if player_progression == null:
		return 1
	return maxi(player_progression.level, 1)


func get_experience() -> int:
	if player_progression == null:
		return 0
	return maxi(player_progression.experience, 0)


func get_experience_to_next_level() -> int:
	if player_progression == null:
		return 1
	return player_progression.experience_to_next_level()


func notify_experience_gained(amount: int, current_experience: int, required_experience: int) -> void:
	experience_gained.emit(amount, current_experience, required_experience)


func notify_level_up(new_level: int) -> void:
	level_up.emit(new_level)


func _get_attack_target() -> Node:
	if _target != null and is_instance_valid(_target):
		return _target
	return get_node_or_null(target_path)


func _refresh_grid_feedback() -> void:
	if _grid == null:
		return
	_grid.set_selected_cell(grid_position)
	if is_selected:
		_grid.set_highlighted_cells(_grid.get_reachable_cells(grid_position, movement_points_remaining))
	else:
		_grid.set_highlighted_cells([])


func _draw() -> void:
	var body_color := Color("5c5366") if _is_defeated else (Color("b7a2d1") if is_selected else Color("736a82"))
	draw_circle(Vector2.ZERO, 22.0, Color("08070c", 0.85))
	draw_circle(Vector2.ZERO, 18.0, body_color)
	draw_circle(Vector2(0, -5), 7.0, Color("e3c889"))
	draw_line(Vector2(-9, 7), Vector2(9, 7), Color("4b294e"), 4.0)
	if is_selected:
		draw_arc(Vector2.ZERO, 29.0, 0.0, TAU, 32, Color("d8af5c"), 2.0)
