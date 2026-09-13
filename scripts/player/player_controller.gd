class_name PlayerController
extends Node2D

const SubHeroProgressionServiceResource = preload("res://scripts/sub_hero/sub_hero_progression_service.gd")

## Hero art drawn on the grid cell; the rect keeps the source aspect (139x172)
## with the feet resting near the cell bottom.
const PLAYER_SPRITE: Texture2D = preload("res://assets/characters/player.png")
const SPRITE_RECT: Rect2 = Rect2(-24.25, -34.0, 48.5, 60.0)

## Every PlayerStats field that a level growth or an equipment affix can move,
## mapped to the bonus key that carries it. ONE table, read by _adjust_stats: an
## affix whose key is missing here would be rolled, displayed and score-counted yet
## never reach combat (see implementation-status §3.2).
const STAT_BONUS_KEYS: Dictionary = {
	&"max_hp": &"hp",
	&"attack": &"attack",
	&"defense": &"defense",
	&"critical_chance": &"critical_chance",
	&"critical_damage": &"critical_damage",
	&"dodge": &"dodge",
	&"movement_points": &"movement",
	&"attack_range": &"attack_range",
	&"life_steal": &"life_steal",
	&"damage_vs_elite": &"damage_vs_elite",
	&"damage_vs_boss": &"damage_vs_boss",
	&"stun_chance": &"stun_chance",
}

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
## The potion counter changed without a potion being drunk (§7 loot replenishment),
## so surfaces that display it can refresh without faking a use.
signal healing_items_changed(remaining_items: int)
signal item_used(item: EquipmentInstance, amount_healed: int)
## The player gave an item up for good (discarded from the bag or the warehouse).
## Emitted by the two paths that end ownership, so a listener can keep a record of
## what left the player's hands without either path knowing about it — the
## Scavenger Shop's buyback book is the listener today.
signal equipment_discarded(item: EquipmentInstance)
signal sub_hero_collection_changed
signal sub_hero_slots_changed

@export var grid_path: NodePath
@export var player_id: StringName = &"player"
@export var grid_position: Vector2i = Vector2i(1, 1)
@export var player_stats: PlayerStats = PlayerStats.new()
@export var player_progression: PlayerProgression = PlayerProgression.new()
@export var equipment_inventory: EquipmentInventory
@export var storage_inventory: StorageInventory
## The buyback book the town's sell surfaces share (gameplay-spec §19). It lives on
## the player, not on a panel, because both the Scavenger Shop and the warehouse stock it:
## an item sold or discarded in either place must be recoverable in the same book.
@export var scavenger_shop: ScavengerShop
## The stage the player is on. The item economy needs it to price a sale: the §19 windfall
## cap is measured against the stage's expected income. The host keeps it in sync through
## `set_current_stage_number()`.
@export_range(1, 999999, 1) var current_stage_number: int = 1
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
## Player-input movement lock, driven by the combat host while an enemy's attack
## animation is still playing. The hero keeps everything it can do from the cell
## it stands on (attack, skill, item) — only stepping to another cell waits, so a
## manual move can never race the enemy's swing. It gates the player's own input
## paths (keyboard, D-pad, click-to-move) and free roam; the autonomous walkers
## (AUTO, the exit roam) drive try_move() directly and stay unaffected, so auto
## farming never stalls on a presentation.
var _movement_locked: bool = false
var _target: Node
## The hero's own numbers at level 1, captured before the first rebuild adds anything
## to them: they are the base every rebuild starts from.
var _base_stats: Dictionary = {}
var _attack_count: int = 0
var _cells_moved_since_attack: int = 0
var _sub_hero_signals_bound: bool = false


func _ready() -> void:
	_ensure_equipment_inventory()
	recompute_stats_from_level_and_equipment()
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
	recompute_stats_from_level_and_equipment()


## Injects the Sub Hero progression the host owns (the save's restored collection).
## Rebinding the collection signals is part of the swap: the hero must announce the
## restored collection and slot assignment, so every surface (assignment panel,
## town, combat spawns) reads the restored Sub Heroes instead of an empty set.
func set_sub_hero_progression(progression: SubHeroProgressionService) -> void:
	_release_sub_hero_signals()
	sub_hero_progression = progression
	get_sub_hero_progression()
	sub_hero_collection_changed.emit()
	sub_hero_slots_changed.emit()


## Injects the warehouse the host owns (the save's restored storage). Storage is a
## plain container with no signals on the player, so the swap is just the swap.
func set_storage(storage: StorageInventory) -> void:
	storage_inventory = storage


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
	var discarded: bool = get_storage().remove_item(item)
	if discarded:
		equipment_discarded.emit(item)
	return discarded


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


## §7 potion replenishment: a potion found as loot restocks the counter that the HUD
## button, `use_healing_item()` and AUTO all read. Capped like the exported counter
## itself, so a full stock is not silently swallowed.
func add_healing_items(count: int = 1) -> int:
	if count <= 0:
		return get_healing_item_count()
	healing_item_count = clampi(healing_item_count + count, 0, 99)
	healing_items_changed.emit(get_healing_item_count())
	queue_redraw()
	return get_healing_item_count()


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
	var discarded: bool = get_inventory().discard_item(item)
	if discarded:
		equipment_discarded.emit(item)
	return discarded


## The shared buyback book, created on first use so a headless caller (a test, a tool)
## never has to build the UI to sell something.
func get_scavenger_shop() -> ScavengerShop:
	if scavenger_shop == null:
		scavenger_shop = ScavengerShop.new()
	return scavenger_shop


## The stage every price is measured against. Called by the host when the stage advances.
func set_current_stage_number(stage_number: int) -> void:
	current_stage_number = maxi(stage_number, 1)


## Sells one owned item for gold at its §19 `SellPrice`. The item leaves the bag or the
## warehouse, and is stocked in the shared buyback book at the price it was sold for, so a
## sale can be undone for exactly what it paid.
##
## Result keys are UI-friendly and contain no Control objects:
## {success, reason, price, item}.
func sell_item(item: EquipmentInstance, from_storage: bool = false) -> Dictionary:
	if item == null:
		return _sell_failure("ITEM_UNAVAILABLE", item)
	if item.is_equipped:
		return _sell_failure("ITEM_EQUIPPED", item)
	var owns_item: bool = get_storage().has_item(item) if from_storage else get_inventory().has_item(item)
	if not owns_item:
		return _sell_failure("ITEM_NOT_OWNED", item)

	var price: int = ItemEconomy.get_sell_price(item, current_stage_number)
	# Removal goes through the discard paths so the bag/storage signals fire exactly once
	# and every panel refreshes; the sale's own record follows below.
	var removed: bool = discard_storage_item(item) if from_storage else discard_item(item)
	if not removed:
		return _sell_failure("ITEM_NOT_OWNED", item)
	if player_progression != null:
		player_progression.add_gold(price)
	# Stocked here rather than only by the shop panel's listener: a sale that paid gold must
	# stay recoverable even when no shop UI is listening.
	get_scavenger_shop().record(item, current_stage_number)
	return {
		"success": true,
		"reason": "",
		"price": price,
		"item": item,
	}


func _sell_failure(reason: String, item: EquipmentInstance) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
		"price": 0,
		"item": item,
	}


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
		try_input_move(Vector2i.UP)
	elif event.is_action_pressed("move_right"):
		try_input_move(Vector2i.RIGHT)
	elif event.is_action_pressed("move_down"):
		try_input_move(Vector2i.DOWN)
	elif event.is_action_pressed("move_left"):
		try_input_move(Vector2i.LEFT)
	elif event.is_action_pressed("primary_action"):
		if _turn_manager != null:
			action_completed.emit()
		else:
			reset_movement_points()
	elif event.is_action_pressed("attack"):
		if _input_enabled and is_selected:
			attack_requested.emit(self, _get_attack_target())


## Player-driven step request (keyboard, D-pad, click-to-move). Refused while an
## enemy attack animation is still playing — see _movement_locked. Free roam is
## exempt exactly like it is for the other movement gates.
func try_input_move(direction: Vector2i) -> bool:
	if _movement_locked and not _free_movement:
		return false
	return try_move(direction)


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
## never a destination. A live enemy-attack movement lock also refuses every
## destination: the hero may act from its own cell, but not step away from it.
## Free roam (walking to the exit after a stage clear) spends no points and is
## deliberately unbounded, exactly like the AUTO walk to the exit.
func can_move_to(cell: Vector2i) -> bool:
	if _grid == null or not is_selected or cell == grid_position:
		return false
	if not _grid.is_walkable(cell) or _grid.is_occupied(cell):
		return false
	if _free_movement:
		return _grid.find_path(grid_position, cell).size() > 1
	if _movement_locked or not _input_enabled or movement_points_remaining <= 0:
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


## Holds/releases player-driven movement while an enemy attack animation is still
## playing (set by the combat host from CombatPresentationSystem). Actions from
## the current cell stay available: only stepping to another cell waits.
func set_movement_locked(locked: bool) -> void:
	_movement_locked = locked


func is_movement_locked() -> bool:
	return _movement_locked


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
	recompute_stats_from_level_and_equipment()


func _on_sub_hero_collection_changed() -> void:
	sub_hero_collection_changed.emit()


func _on_sub_hero_slots_changed() -> void:
	sub_hero_slots_changed.emit()


## Unsubscribes the current Sub Hero progression, so swapping in an injected one
## cannot leave the hero listening to a collection nobody owns any more.
func _release_sub_hero_signals() -> void:
	if sub_hero_progression == null or not _sub_hero_signals_bound:
		return
	if sub_hero_progression.collection_changed.is_connected(_on_sub_hero_collection_changed):
		sub_hero_progression.collection_changed.disconnect(_on_sub_hero_collection_changed)
	if sub_hero_progression.active_slots_changed.is_connected(_on_sub_hero_slots_changed):
		sub_hero_progression.active_slots_changed.disconnect(_on_sub_hero_slots_changed)
	_sub_hero_signals_bound = false


## Rebuilds the hero's derived stats from the only two inputs that produce them: the
## character's LEVEL and the items the hero has EQUIPPED. Every path that can change
## either one goes through here — a fresh boot, a level-up, an equip, a remove, and
## the load that restores a save — so a restored session fights with the numbers its
## level and its gear produce instead of with the level-1 numbers the scene was
## authored with (the save stores level and gear, never the derived stats).
##
## IDEMPOTENT by construction: the numbers are rebuilt from the level-1 base every
## time, never adjusted by a remembered delta ("subtract what was added last time"),
## so calling it twice with the same level and the same gear changes nothing.
##
## HP: a rebuild that does not move the maximum leaves the current HP exactly where
## it was — that is what makes a repeated call a no-op; one that does move it keeps
## the same FRACTION of the new maximum, so a session that boots at full HP boots at
## full HP of the restored maximum, and a wounded hero stays exactly as wounded as
## they were. A dead hero stays dead, and no projection may kill a living one.
##
## `keep_current_hp` is the level-up policy: a level-up has always left the current
## HP alone (a bigger maximum, not a heal).
func recompute_stats_from_level_and_equipment(keep_current_hp: bool = false) -> void:
	if player_stats == null:
		return
	if _base_stats.is_empty():
		_capture_base_stats()
	var previous_max_hp: int = player_stats.max_hp
	var previous_current_hp: int = player_stats.current_hp
	# 1. The level-1 numbers, exactly as they were authored.
	for field in STAT_BONUS_KEYS:
		player_stats.set(field, _base_stats[field])
	# 2. The growth the character's level carries, then 3. the gear. Both are additive
	# on top of that base, and neither is ever applied twice.
	_adjust_stats(_level_growth_totals(), 1.0)
	if equipment_inventory != null:
		_adjust_stats(equipment_inventory.get_equipped_stat_totals(), 1.0)
	_apply_projected_current_hp(previous_max_hp, previous_current_hp, keep_current_hp)
	if movement_points_remaining > 0:
		movement_points_remaining = mini(movement_points_remaining, maxi(player_stats.movement_points, 0))
	queue_redraw()


## What ONE level adds to the three core numbers, keyed like the equipment totals so a
## level-up can report what it granted without holding a second copy of the numbers.
func get_level_growth() -> Dictionary:
	if player_stats == null:
		return {}
	return {
		&"hp": maxi(player_stats.max_hp_per_level, 0),
		&"attack": maxi(player_stats.attack_per_level, 0),
		&"defense": maxi(player_stats.defense_per_level, 0),
	}


## The growth the character's whole level carries, as a bonus dictionary _adjust_stats
## reads (empty at level 1, where the base IS the answer).
func _level_growth_totals() -> Dictionary:
	var levels: int = maxi(get_level(), 1) - 1
	if levels <= 0:
		return {}
	var growth: Dictionary = get_level_growth()
	var totals: Dictionary = {}
	for key in growth:
		totals[key] = float(growth[key]) * float(levels)
	return totals


## The level-1 numbers the hero was authored with, captured ONCE — before the first
## rebuild adds anything to them — because every later rebuild starts from them. A
## hero that is not in the tree yet captures them on its first rebuild, so a host (or
## a test) that tunes player_stats before adding the hero keeps its tuning.
func _capture_base_stats() -> void:
	_base_stats.clear()
	for field in STAT_BONUS_KEYS:
		_base_stats[field] = player_stats.get(field)


func _apply_projected_current_hp(previous_max_hp: int, previous_current_hp: int, keep_current_hp: bool) -> void:
	if keep_current_hp or player_stats.max_hp == previous_max_hp or previous_current_hp <= 0:
		player_stats.current_hp = previous_current_hp
	elif previous_max_hp > 0:
		player_stats.current_hp = maxi(
			floori(float(previous_current_hp) * float(player_stats.max_hp) / float(previous_max_hp)), 1
		)
	player_stats.clamp_current_hp()


## Adds a bonus dictionary — the equipment affix totals, or the growth a level carries
## — to the stats. ONE mapping table decides which stat a key moves, and integer stats
## take the rounded amount so a recompute from the base lands on the same integer a
## level-up used to add.
func _adjust_stats(bonuses: Dictionary, direction: float) -> void:
	if player_stats == null:
		return
	for field in STAT_BONUS_KEYS:
		var amount: float = float(bonuses.get(STAT_BONUS_KEYS[field], 0.0)) * direction
		var current: Variant = player_stats.get(field)
		if current is int:
			player_stats.set(field, int(current) + roundi(amount))
		else:
			player_stats.set(field, float(current) + amount)


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
