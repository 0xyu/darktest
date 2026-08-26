class_name EnemyController
extends Node2D

const MiniBossDefinitionResource = preload("res://scripts/enemies/mini_boss_definition.gd")

signal moved(from_cell: Vector2i, to_cell: Vector2i)
signal target_selected(target: Node)
signal attack_requested(enemy: EnemyController, target: Node)
signal area_attack_requested(enemy: EnemyController, target: Node, attack_range: int, damage_multiplier: float)
signal summon_requested(enemy: EnemyController, summon_count: int)
signal enraged(enemy: EnemyController)
signal defeated

@export var grid_path: NodePath
@export var enemy_id: StringName = &"enemy"
@export var grid_position: Vector2i = Vector2i(1, 1)
@export_range(1, 999999, 1) var enemy_level: int = 1
@export var enemy_definition: EnemyDefinition

var enemy_stats: EnemyStats = EnemyStats.new()
var is_mini_boss: bool = false
var boss_identifier: StringName = &""
var boss_display_name: String = ""
var boss_behavior: int = -1
var _grid: GridMap2D
var _target: Node
var _is_defeated: bool = false
var _boss_definition: Resource
var _summons_used: int = 0
var _is_enraged: bool = false
var poisoned: bool = false
var facing_direction: Vector2i = Vector2i.DOWN


func _ready() -> void:
	_grid = get_node_or_null(grid_path) as GridMap2D
	if _grid == null:
		push_error("EnemyController requires a GridMap2D assigned through grid_path.")
		return
	if enemy_definition != null and enemy_definition.base_stats != null:
		enemy_stats = enemy_definition.base_stats.duplicate(true) as EnemyStats
		enemy_stats.level = maxi(enemy_level, 1)
		enemy_stats.current_hp = enemy_stats.max_hp
	_configure_boss()
	if not _grid.is_walkable(grid_position):
		grid_position = Vector2i.ZERO
	if not _grid.is_occupied(grid_position):
		_grid.set_occupied(grid_position, enemy_id)
	global_position = _grid.grid_to_world(grid_position)
	queue_redraw()


func take_turn(player: Node, turn_manager: TurnManager) -> void:
	if _is_defeated or enemy_stats.current_hp <= 0:
		turn_manager.complete_enemy_turn(self)
		return
	if _grid == null or player == null:
		turn_manager.complete_enemy_turn(self)
		return

	_target = player
	target_selected.emit(_target)
	if _try_boss_turn(player, turn_manager):
		return
	var target_cell: Vector2i = _get_target_cell(player)
	if _grid_distance(grid_position, target_cell) > enemy_stats.attack_range:
		_move_toward_target(target_cell)
	if _grid_distance(grid_position, target_cell) <= enemy_stats.attack_range:
		attack_requested.emit(self, _target)
	turn_manager.complete_enemy_turn(self)


func get_grid_position() -> Vector2i:
	return grid_position


func handle_defeat() -> void:
	if _is_defeated:
		return
	_is_defeated = true
	enemy_stats.current_hp = 0
	if _grid != null:
		_grid.clear_occupied(grid_position, enemy_id)
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	defeated.emit()


func is_defeated() -> bool:
	return _is_defeated


func set_poisoned(is_poisoned_value: bool = true) -> void:
	poisoned = is_poisoned_value
	queue_redraw()


func is_poisoned() -> bool:
	return poisoned


func is_attacked_from_behind(attacker_cell: Vector2i) -> bool:
	if facing_direction == Vector2i.ZERO:
		return false
	return attacker_cell - grid_position == -facing_direction


func get_display_name() -> String:
	if is_mini_boss and not boss_display_name.is_empty():
		return boss_display_name
	if enemy_definition != null:
		return enemy_definition.display_name
	return "Enemy"


func get_boss_behavior_name() -> String:
	match boss_behavior:
		0:
			return "AOE"
		1:
			return "SUMMONER"
		2:
			return "ENRAGER"
		_:
			return ""


func _configure_boss() -> void:
	if enemy_definition == null or enemy_definition.get_script() != MiniBossDefinitionResource:
		return
	_boss_definition = enemy_definition
	is_mini_boss = true
	boss_identifier = enemy_definition.definition_id
	boss_display_name = enemy_definition.display_name
	boss_behavior = int(_boss_definition.get("boss_behavior"))


func _try_boss_turn(player: Node, turn_manager: TurnManager) -> bool:
	if not is_mini_boss or _boss_definition == null:
		return false
	if boss_behavior == 1 and _summons_used < maxi(int(_boss_definition.get("summon_count")), 1):
		var remaining_summons: int = maxi(int(_boss_definition.get("summon_count")) - _summons_used, 0)
		_summons_used += remaining_summons
		summon_requested.emit(self, remaining_summons)
		turn_manager.complete_enemy_turn(self)
		return true
	if boss_behavior == 0:
		return _take_area_attack_turn(player, turn_manager)
	if boss_behavior == 2:
		_update_enrage_state()
	return false


func _take_area_attack_turn(player: Node, turn_manager: TurnManager) -> bool:
	var target_cell: Vector2i = _get_target_cell(player)
	var ability_range: int = maxi(int(_boss_definition.get("ability_range")), 1)
	if _grid_distance(grid_position, target_cell) > ability_range:
		_move_toward_target(target_cell)
	if _grid_distance(grid_position, target_cell) <= ability_range:
		var damage_multiplier: float = maxf(float(_boss_definition.get("ability_damage_multiplier")), 0.1)
		area_attack_requested.emit(self, player, ability_range, damage_multiplier)
	turn_manager.complete_enemy_turn(self)
	return true


func _update_enrage_state() -> void:
	if _is_enraged or enemy_stats.max_hp <= 0:
		return
	var threshold: float = clampf(float(_boss_definition.get("enrage_health_threshold")), 0.05, 0.95)
	var health_ratio: float = float(enemy_stats.current_hp) / float(enemy_stats.max_hp)
	if health_ratio > threshold:
		return
	var attack_multiplier: float = maxf(float(_boss_definition.get("enrage_attack_multiplier")), 1.0)
	enemy_stats.attack = maxi(roundi(float(enemy_stats.attack) * attack_multiplier), 1)
	_is_enraged = true
	enraged.emit(self)
	queue_redraw()


func _move_toward_target(target_cell: Vector2i) -> void:
	var reachable_cells: Array[Vector2i] = _grid.get_reachable_cells(grid_position, enemy_stats.movement_points)
	var best_cell: Vector2i = grid_position
	var best_distance: int = _grid_distance(grid_position, target_cell)
	for candidate in reachable_cells:
		if _grid.is_occupied(candidate):
			continue
		var candidate_distance: int = _grid_distance(candidate, target_cell)
		if candidate_distance < best_distance:
			best_cell = candidate
			best_distance = candidate_distance
	if best_cell == grid_position:
		return

	var path: Array[Vector2i] = _grid.find_path(grid_position, best_cell)
	if path.is_empty():
		return
	var previous_cell: Vector2i = grid_position
	_grid.clear_occupied(previous_cell, enemy_id)
	if not _grid.set_occupied(best_cell, enemy_id):
		_grid.set_occupied(previous_cell, enemy_id)
		return
	grid_position = best_cell
	facing_direction = _direction_to_cell(previous_cell, best_cell)
	global_position = _grid.grid_to_world(grid_position)
	queue_redraw()
	moved.emit(previous_cell, grid_position)


func _get_target_cell(target: Node) -> Vector2i:
	if target.has_method("get_grid_position"):
		return target.get_grid_position()
	var target_position: Variant = target.get("grid_position")
	if target_position is Vector2i:
		return target_position
	return grid_position


func _grid_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


func _direction_to_cell(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var difference: Vector2i = to_cell - from_cell
	if absi(difference.x) >= absi(difference.y) and difference.x != 0:
		return Vector2i(signi(difference.x), 0)
	if difference.y != 0:
		return Vector2i(0, signi(difference.y))
	return facing_direction


func _draw() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color("09070d", 0.9))
	var body_color: Color = Color("8d304d") if is_mini_boss else Color("9d5267")
	draw_circle(Vector2.ZERO, 18.0, body_color)
	draw_circle(Vector2(0, -5), 7.0, Color("e4c5a1"))
	draw_line(Vector2(-9, 7), Vector2(9, 7), Color("4a1d2e"), 4.0)
	if is_mini_boss:
		draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 32, Color("d8af5c"), 2.0)
	var health_ratio: float = clampf(float(enemy_stats.current_hp) / maxi(enemy_stats.max_hp, 1), 0.0, 1.0)
	draw_rect(Rect2(-24, -38, 48, 5), Color("26151f"), true)
	draw_rect(Rect2(-24, -38, 48 * health_ratio, 5), Color("b94d63"), true)
