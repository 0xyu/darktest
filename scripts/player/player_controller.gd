class_name PlayerController
extends Node2D

const SubHeroProgressionServiceResource = preload("res://scripts/sub_hero/sub_hero_progression_service.gd")

## Hero art drawn on the grid cell; the rect keeps the source aspect (139x172)
## with the feet resting near the cell bottom.
const PLAYER_SPRITE: Texture2D = preload("res://assets/characters/player.png")
const SPRITE_RECT: Rect2 = Rect2(-24.25, -34.0, 48.5, 60.0)

signal moved(from_cell: Vector2i, to_cell: Vector2i, movement_points_remaining: int)
signal selection_changed(is_selected: bool)
signal action_completed
signal attack_requested(attacker: Node, target: Node)
signal skill_requested(attacker: Node, target: Node, skill_id: StringName)
signal defeated
signal experience_gained(amount: int, current_experience: int, required_experience: int)
signal level_up(new_level: int)
signal equipment_effect_triggered(effect_id: StringName, description: String)
signal healing_item_used(remaining_items: int, amount_healed: int)
signal item_used(item: EquipmentInstance, amount_healed: int)
signal sub_hero_collection_changed
signal sub_hero_slots_changed

@export var grid_path: NodePath
@export var player_id: StringName = &"player"
@export var grid_position: Vector2i = Vector2i(1, 1)
@export var player_stats: PlayerStats = PlayerStats.new()
@export var player_progression: PlayerProgression = PlayerProgression.new()
@export var equipment_inventory: EquipmentInventory
@export var storage_inventory: StorageInventory
@export var sub_hero_progression: SubHeroProgressionService
@export var is_selected: bool = true
@export var target_path: NodePath
@export_range(0, 99, 1) var healing_item_count: int = 3
@export_range(0.05, 1.0, 0.05) var healing_item_heal_ratio: float = 0.35

var movement_points_remaining: int = 0
var _grid: GridMap2D
var _token: CharacterToken
var _input_enabled: bool = true
var _turn_manager: Node
var _is_defeated: bool = false
var _free_movement: bool = false
var _target: Node
var _applied_equipment_bonuses: Dictionary = {}
var _attack_count: int = 0
var _cells_moved_since_attack: int = 0
var _sub_hero_signals_bound: bool = false


func _ready() -> void:
	_ensure_equipment_inventory()
	_refresh_equipment_stats()
	_grid = get_node_or_null(grid_path) as GridMap2D
	if _grid == null:
		push_error("PlayerController requires a GridMap2D assigned through grid_path.")
		return
	# Presentation token: hero art + shadow live here so gameplay can keep
	# teleporting global_position while visuals animate via local offsets.
	_token = CharacterToken.new()
	_token.name = &"CharacterToken"
	add_child(_token)
	_token.setup(PLAYER_SPRITE, SPRITE_RECT, false)
	if not _grid.is_walkable(grid_position):
		grid_position = Vector2i.ZERO
	if not _grid.is_occupied(grid_position):
		_grid.set_occupied(grid_position, player_id)
	global_position = _grid.grid_to_world(grid_position)
	_token.snap()
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


func get_sub_hero_progression() -> SubHeroProgressionService:
	if sub_hero_progression == null:
		sub_hero_progression = SubHeroProgressionServiceResource.new()
	if not _sub_hero_signals_bound:
		var collection_signal: Signal = sub_hero_progression.collection_changed
		if not collection_signal.is_connected(_on_sub_hero_collection_changed):
			collection_signal.connect(_on_sub_hero_collection_changed)
		var slots_signal: Signal = sub_hero_progression.active_slots_changed
		if not slots_signal.is_connected(_on_sub_hero_slots_changed):
			slots_signal.connect(_on_sub_hero_slots_changed)
		_sub_hero_signals_bound = true
	return sub_hero_progression


func add_sub_hero(instance: SubHeroInstance) -> Dictionary:
	return get_sub_hero_progression().add_instance(instance)


func assign_sub_hero_slot(slot_index: int, hero_id: StringName) -> bool:
	return get_sub_hero_progression().assign_active_slot(slot_index, hero_id)


func remove_sub_hero_slot(slot_index: int) -> bool:
	return get_sub_hero_progression().remove_active_slot(slot_index)


func get_active_sub_hero_entries() -> Array[Dictionary]:
	return get_sub_hero_progression().get_active_entries()


func load_sub_hero_save_data(save_data: Dictionary) -> void:
	get_sub_hero_progression().load_save_data(save_data)


func add_equipment(item: EquipmentInstance) -> bool:
	return get_inventory().add_item(item)


func get_storage() -> StorageInventory:
	if storage_inventory == null:
		storage_inventory = StorageInventory.new()
	return storage_inventory


## Adds a picked-up item straight to the warehouse (overflow path).
func add_to_storage(item: EquipmentInstance) -> bool:
	return get_storage().add_item(item)


## Moves a bag item into the warehouse. Equipped items cannot be stored.
func move_to_storage(item: EquipmentInstance) -> bool:
	var bag := get_inventory()
	if item == null or item.is_equipped or not bag.has_item(item):
		return false
	var storage := get_storage()
	if storage.get_remaining_capacity() <= 0:
		return false
	if not bag.remove_item(item):
		return false
	return storage.add_item(item)


## Moves a warehouse item back into the bag. Requires a free bag slot.
func move_to_bag(item: EquipmentInstance) -> bool:
	var storage := get_storage()
	if item == null or not storage.has_item(item):
		return false
	var bag := get_inventory()
	if bag.get_remaining_capacity() <= 0:
		return false
	if not storage.remove_item(item):
		return false
	return bag.add_item(item)


func discard_storage_item(item: EquipmentInstance) -> bool:
	return get_storage().remove_item(item)


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


## Uses a consumable item from the bag: heals by its heal_ratio, then removes
## the item. Rejects potions that are already at full HP, mirroring
## `use_healing_item()`.
func use_item(item: EquipmentInstance) -> bool:
	var inventory := get_inventory()
	if item == null or not item.is_consumable() or not inventory.has_item(item):
		return false
	if player_stats == null or player_stats.current_hp <= 0 or player_stats.current_hp >= player_stats.max_hp:
		return false
	var previous_hp: int = player_stats.current_hp
	var heal_amount: int = maxi(roundi(float(player_stats.max_hp) * clampf(item.get_heal_ratio(), 0.0, 1.0)), 1)
	player_stats.current_hp = mini(player_stats.current_hp + heal_amount, player_stats.max_hp)
	if not inventory.remove_item(item):
		return false
	item_used.emit(item, player_stats.current_hp - previous_hp)
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


## Restores `amount` HP, clamped to max HP, and returns how much was actually
## restored (0 when already full, defeated, or nothing to restore).
##
## Purpose-named seam for stage content that heals the hero (e.g. a healing pool).
## Consumables keep going through use_item() / use_healing_item(), and equipment
## procs through heal_from_equipment_effect() — those differ in what they consume
## and what they emit, so they stay separate.
func heal(amount: int) -> int:
	if player_stats == null or player_stats.current_hp <= 0 or amount <= 0:
		return 0
	var previous_hp: int = player_stats.current_hp
	player_stats.current_hp = mini(player_stats.current_hp + amount, player_stats.max_hp)
	return player_stats.current_hp - previous_hp


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


func try_move(direction: Vector2i) -> bool:
	if _grid == null or not is_selected:
		return false
	# Free movement (victory roam / walking to the exit) bypasses the normal
	# turn input and movement-point gates so the hero can walk freely.
	if not _free_movement and (not _input_enabled or movement_points_remaining <= 0):
		return false
	var target_cell: Vector2i = grid_position + direction
	if not _grid.is_walkable(target_cell) or _grid.is_occupied(target_cell):
		return false

	var previous_cell: Vector2i = grid_position
	_grid.clear_occupied(previous_cell, player_id)
	_grid.set_occupied(target_cell, player_id)
	grid_position = target_cell
	if not _free_movement:
		movement_points_remaining -= 1
		_cells_moved_since_attack += 1
	var previous_world: Vector2 = global_position
	global_position = _grid.grid_to_world(grid_position)
	if _token != null:
		_token.play_move(previous_world - global_position, 1, false)
	_refresh_grid_feedback()
	queue_redraw()
	moved.emit(previous_cell, grid_position, movement_points_remaining)
	return true


## Click-to-move reachability: true when the hero could walk to `cell` right now.
##
## The gate is the SAME rule the grid highlights with — the cells reachable with
## the movement points left this turn — so a clicked cell can never take the hero
## further than the highlighted area, and a cell blocked by an actor or a wall is
## never a destination. Free roam (walking to the exit after a stage clear) spends
## no points and is deliberately unbounded, exactly like the AUTO walk to the exit.
func can_move_to(cell: Vector2i) -> bool:
	if _grid == null or not is_selected or cell == grid_position:
		return false
	if not _grid.is_walkable(cell) or _grid.is_occupied(cell):
		return false
	if _free_movement:
		return _grid.find_path(grid_position, cell).size() > 1
	if not _input_enabled or movement_points_remaining <= 0:
		return false
	return _grid.get_reachable_cells(grid_position, movement_points_remaining).has(cell)


## Walks the hero to `cell` along the shortest path. Every step goes through
## try_move(), so occupancy, movement points, grid feedback and the `moved` signal
## behave exactly as they do for a manual step; the walk stops early if a step
## becomes illegal. Returns true when at least one cell was walked.
func try_move_to(cell: Vector2i) -> bool:
	if not can_move_to(cell):
		return false
	var path: Array[Vector2i] = _grid.find_path(grid_position, cell)
	if path.size() < 2:
		return false
	var moved_cells: int = 0
	for path_index in range(1, path.size()):
		var direction: Vector2i = path[path_index] - grid_position
		if not try_move(direction):
			break
		moved_cells += 1
	return moved_cells > 0


func reset_movement_points() -> void:
	if player_stats == null:
		return
	movement_points_remaining = maxi(player_stats.movement_points, 0)
	_refresh_grid_feedback()
	queue_redraw()


## Places the hero directly on `cell` (teleport), updating grid occupancy and
## world position. Used by StageManager to walk the hero to the arena entrance
## whenever a new stage is generated.
func place_at(cell: Vector2i) -> bool:
	if _grid == null or not _grid.is_walkable(cell):
		return false
	if _grid.is_occupied(cell) and _grid.get_occupant(cell) != player_id:
		return false
	if _grid.is_occupied(grid_position) and _grid.get_occupant(grid_position) == player_id:
		_grid.clear_occupied(grid_position, player_id)
	grid_position = cell
	if not _grid.is_occupied(grid_position):
		_grid.set_occupied(grid_position, player_id)
	global_position = _grid.grid_to_world(grid_position)
	if _token != null:
		_token.snap()
	if is_instance_valid(_target):
		_target = null
	_refresh_grid_feedback()
	queue_redraw()
	return true


## Enables/disables unrestricted roaming used after a stage clear so the hero
## can walk to the exit (or be auto-pathed there) without spending turns.
func set_free_movement(enabled: bool) -> void:
	if _free_movement == enabled:
		return
	_free_movement = enabled
	# Roaming must be able to move the hero even if the player had deselected it
	# during combat (a click toggles selection).
	if enabled and not is_selected:
		set_selected(true)
	else:
		_refresh_grid_feedback()
		queue_redraw()


func is_free_moving() -> bool:
	return _free_movement


func begin_player_turn(movement_points: int = -1) -> void:
	_input_enabled = true
	_free_movement = false
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


func get_skill_points() -> int:
	if player_progression == null:
		return 0
	return player_progression.get_skill_points()


func get_skill_level(skill_id: StringName) -> int:
	if player_progression == null:
		return 0
	return player_progression.get_skill_level(skill_id)


func upgrade_skill(skill_id: StringName) -> bool:
	if player_progression == null:
		return false
	return player_progression.upgrade_skill(skill_id)


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
	_free_movement = false
	if _grid != null:
		_grid.clear_occupied(grid_position, player_id)
	if _token != null:
		_token.modulate = Color(0.45, 0.42, 0.5, 0.85)
	queue_redraw()
	defeated.emit()


func revive_for_retry() -> void:
	_is_defeated = false
	_input_enabled = true
	if player_stats != null:
		player_stats.reset_current_hp()
	if _grid != null:
		if _grid.is_occupied(grid_position):
			_grid.clear_occupied(grid_position, player_id)
		_grid.set_occupied(grid_position, player_id)
		global_position = _grid.grid_to_world(grid_position)
	if _token != null:
		_token.reset_visuals()
		_token.snap()
	reset_movement_points()
	reset_equipment_effect_state()
	_target = null
	queue_redraw()


func is_defeated() -> bool:
	return _is_defeated


func _ensure_equipment_inventory() -> void:
	if equipment_inventory == null:
		equipment_inventory = EquipmentInventory.new()
	if not equipment_inventory.equipment_changed.is_connected(_on_equipment_changed):
		equipment_inventory.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed(_slot: int, _equipped_item: EquipmentInstance, _previous_item: EquipmentInstance) -> void:
	_refresh_equipment_stats()


func _on_sub_hero_collection_changed() -> void:
	sub_hero_collection_changed.emit()


func _on_sub_hero_slots_changed() -> void:
	sub_hero_slots_changed.emit()


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
	if is_selected and not _free_movement:
		_grid.set_highlighted_cells(_grid.get_reachable_cells(grid_position, movement_points_remaining))
	else:
		_grid.set_highlighted_cells([])


func _draw() -> void:
	# Hero art and ground shadow live on the CharacterToken; only the selection
	# ring stays here, flattened onto the floor plane around the token.
	if is_selected:
		draw_set_transform(Vector2(0.0, 24.0), 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 40, Color("d8af5c"), 2.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
