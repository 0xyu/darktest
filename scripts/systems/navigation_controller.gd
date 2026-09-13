class_name NavigationController
extends Node

## Click-to-navigate: ONE persistent destination the hero keeps walking toward over as
## many turns as it takes.
##
## The player clicks a cell that is beyond this turn's movement range; the hero walks
## the cells it can afford now, the turn ends the normal way, and on every following
## PLAYER TURN the walk continues by itself until the destination is reached. An enemy
## standing in the way does not end the walk: it is dealt with (walk into reach, strike
## it through the hero's own attack seam), and the original destination is resumed once
## the route is clear again.
##
## This controller owns no movement rule and no combat rule, on purpose:
##
## * a step is a real player-input step (`PlayerController.try_input_move`), so movement
##   points, the movement lock, grid occupancy and the movement animation behave exactly
##   as they do for a D-pad press;
## * an attack on a blocking enemy is the hero's own `attack_requested` seam, so damage,
##   crits, life steal, EXP, gold, loot, enemy death and the end of the turn all stay in
##   `CombatSystem`;
## * the route is `GridMap2D.find_path` — the grid that already owns walkability and
##   occupancy — and never a second source of truth for what a cell contains.
##
## Paths are NEVER cached and never computed per frame: the route is recalculated on the
## events that can change it (a step, a new player turn, an enemy move, an enemy death,
## a new destination), and one recalculation walks as far as the current turn allows.
##
## AUTO and FARMING are independent systems. Starting navigation never toggles either.

## The walk began (or was re-aimed at a new cell). Emitted once per navigation session,
## so a re-aimed destination does not flicker the indicator off and on.
signal navigation_started(target_cell: Vector2i)
## The walk is over: `reason` is one of the REASON_* constants below.
signal navigation_finished(reason: StringName)

## Navigation lifecycle. The two blocker states of a wider design are deliberately not
## states here: walking toward a blocker IS the normal walk, and which enemy the hero is
## dealing with is reported by get_blocker(). Only states that change behaviour exist.
enum State { NONE, NAVIGATING, COMPLETED, CANCELLED }

const REASON_ARRIVED: StringName = &"arrived"
const REASON_NO_ROUTE: StringName = &"no_route"
const REASON_NO_MOVEMENT: StringName = &"no_movement"
const REASON_STAGE_CHANGED: StringName = &"stage_changed"
const REASON_DEFEAT: StringName = &"defeat"
const REASON_CANCELLED: StringName = &"cancelled"

@export var player_path: NodePath = NodePath("../Player")
@export var turn_manager_path: NodePath = NodePath("../TurnManager")
@export var combat_system_path: NodePath = NodePath("../CombatSystem")
@export var stage_manager_path: NodePath = NodePath("../StageManager")
@export var grid_path: NodePath = NodePath("../Grid")

var _player: PlayerController
var _turn_manager: TurnManager
var _combat_system: CombatSystem
var _stage_manager: StageManager
var _grid: GridMap2D

var _state: int = State.NONE
var _target_cell: Vector2i = Vector2i(-1, -1)
var _blocker: EnemyController = null
## One deferred continuation is enough: several events inside the same beat (a step, an
## enemy death) all end in a single recalculation.
var _advance_pending: bool = false


func _ready() -> void:
	_resolve_dependencies()
	_connect_signals()


## Wired by the combat host, exactly like AutoCombatController.attach_systems.
func attach_systems(
	player: PlayerController,
	turn_manager: TurnManager,
	combat_system: CombatSystem,
	stage_manager: StageManager,
	grid: GridMap2D
) -> void:
	_player = player
	_turn_manager = turn_manager
	_combat_system = combat_system
	_stage_manager = stage_manager
	_grid = grid
	_connect_signals()


func is_navigating() -> bool:
	return _state == State.NAVIGATING


func get_state() -> int:
	return _state


## The destination being walked to, or Vector2i(-1, -1) when no walk is active.
func get_navigation_target() -> Vector2i:
	return _target_cell


## The enemy the walk is currently dealing with, or null when the route is clear.
func get_blocker() -> EnemyController:
	if _blocker != null and is_instance_valid(_blocker) and not _blocker.is_defeated():
		return _blocker
	return null


## Arms (or re-aims) the walk to `cell` and walks as far as THIS turn allows.
##
## Returns true while the destination is still being pursued. False means the cell was
## not a legal destination, or the walk gave up immediately (no route, no movement) —
## in which case navigation_finished() has already reported the reason.
##
## There is exactly ONE destination at a time: a second click replaces the first instead
## of queueing another walk, and the session (and so the indicator) simply continues.
func set_navigation_target(cell: Vector2i) -> bool:
	if _grid == null or _player == null:
		return false
	if not _grid.is_walkable(cell) or _grid.is_occupied(cell):
		return false
	if cell == _player.grid_position:
		cancel_navigation()
		return false
	var was_navigating: bool = _state == State.NAVIGATING
	_target_cell = cell
	_blocker = null
	_state = State.NAVIGATING
	if not was_navigating:
		navigation_started.emit(_target_cell)
	_advance()
	return _state == State.NAVIGATING


## Stops the walk and clears the destination. AUTO and FARMING are never touched here:
## they are separate systems, and only their own controls change them.
func cancel_navigation(reason: StringName = REASON_CANCELLED) -> void:
	if _state != State.NAVIGATING:
		return
	_finish(reason)


## The board can have changed under the hero's feet — an enemy moved, an enemy died, the
## stage was rebuilt. The route is recalculated on the next beat instead of trusting a
## path that was valid a moment ago.
func notify_environment_changed() -> void:
	_request_advance()


func _resolve_dependencies() -> void:
	if _player == null:
		_player = get_node_or_null(player_path) as PlayerController
	if _turn_manager == null:
		_turn_manager = get_node_or_null(turn_manager_path) as TurnManager
	if _combat_system == null:
		_combat_system = get_node_or_null(combat_system_path) as CombatSystem
	if _stage_manager == null:
		_stage_manager = get_node_or_null(stage_manager_path) as StageManager
	if _grid == null:
		_grid = get_node_or_null(grid_path) as GridMap2D


func _connect_signals() -> void:
	if _turn_manager != null and not _turn_manager.player_turn_started.is_connected(_on_player_turn_started):
		_turn_manager.player_turn_started.connect(_on_player_turn_started)
	if _player != null and not _player.moved.is_connected(_on_player_moved):
		_player.moved.connect(_on_player_moved)


func _on_player_turn_started() -> void:
	# The turn that pays for the next stretch of the walk. Deferred: a new turn is
	# announced from inside the enemy phase, and the walk must not step before the turn
	# manager has finished handing the turn over.
	_request_advance()


func _on_player_moved(_from_cell: Vector2i, _to_cell: Vector2i, _points_remaining: int) -> void:
	# Covers a move navigation did not make itself (a manual D-pad step): the walk
	# re-aims from wherever the hero actually is.
	_request_advance()


func _request_advance() -> void:
	if _state != State.NAVIGATING or _advance_pending:
		return
	_advance_pending = true
	call_deferred("_run_advance")


func _run_advance() -> void:
	_advance_pending = false
	_advance()


## One navigation beat: recalculate the route and walk it for as long as THIS turn can
## pay for it.
func _advance() -> void:
	if _state != State.NAVIGATING:
		return
	if _player == null or _grid == null or _turn_manager == null:
		_finish(REASON_CANCELLED)
		return
	if _player.is_defeated():
		_finish(REASON_DEFEAT)
		return
	if _player.grid_position == _target_cell:
		_finish(REASON_ARRIVED)
		return
	if _player.is_free_moving():
		# A cleared stage hands the arena to free roam: that walk is unbounded, spends no
		# points, and belongs to the exit walk — never to a clicked destination.
		_finish(REASON_CANCELLED)
		return
	if _player.is_movement_locked():
		return
	if _turn_manager.get_phase() != TurnState.PLAYER_TURN or not _player.is_input_enabled():
		# Waiting for the hero's own turn. The walk is not lost: player_turn_started
		# continues it.
		return

	var step_budget: int = maxi(_player.movement_points_remaining, 0)
	if step_budget <= 0:
		# A turn with nothing to spend can never advance the walk, and asking again every
		# turn would be an endless turn loop. Stop instead.
		_finish(REASON_NO_MOVEMENT)
		return

	var steps_taken: int = 0
	while (
		_state == State.NAVIGATING
		and steps_taken < step_budget
		and _turn_manager.get_phase() == TurnState.PLAYER_TURN
	):
		if _player.grid_position == _target_cell:
			_finish(REASON_ARRIVED)
			return
		var next_cell: Vector2i = _next_step_cell()
		if next_cell == _player.grid_position:
			# Nothing to walk: the blocking enemy was just struck, or there is no route
			# left to walk — both are already settled.
			return
		if not _player.try_input_move(next_cell - _player.grid_position):
			# A step the hero cannot take is not something to retry forever.
			_finish(REASON_NO_ROUTE)
			return
		steps_taken += 1

	# The turn's movement is spent. A manual walk is settled by the combat host and AUTO
	# settles its own turn; a navigating hero walks with AUTO held back, so the turn is
	# ended here and the hero's NEXT turn continues the walk.
	if _state == State.NAVIGATING and _turn_manager.get_phase() == TurnState.PLAYER_TURN:
		_turn_manager.complete_player_turn()


## The cell to step onto next, or the hero's own cell when it must not step this beat —
## either because the blocking enemy was attacked from where the hero stands, or because
## there is no route left at all (navigation has then already stopped).
func _next_step_cell() -> Vector2i:
	var here: Vector2i = _player.grid_position
	_blocker = null
	var path: Array[Vector2i] = _grid.find_path(here, _target_cell)
	if path.size() >= 2:
		return path[1]

	# No route as things stand. Enemies are dynamic obstacles the grid deliberately does
	# not bake in, so the question is whether an ACTOR — rather than the terrain — is what
	# stands between the hero and the destination.
	var blocker: EnemyController = _find_blocking_enemy()
	if blocker == null:
		_finish(REASON_NO_ROUTE)
		return here
	_blocker = blocker
	# The clicked destination stays the hero's target for every other system; the blocker
	# is only what navigation has to get past.
	_player.set_target(blocker)

	if _combat_system != null and _combat_system.can_attack(_player, blocker):
		# Already in reach: the strike goes out through the hero's own attack seam, so
		# the whole combat flow (damage, death, EXP, loot, end of turn) is untouched by
		# navigation. The route is recalculated when the enemy dies or the turn turns.
		_player.attack_requested.emit(_player, blocker)
		return here

	var approach: Vector2i = _approach_cell(blocker)
	if approach == here:
		_finish(REASON_NO_ROUTE)
		return here
	var approach_path: Array[Vector2i] = _grid.find_path(here, approach)
	if approach_path.size() < 2:
		_finish(REASON_NO_ROUTE)
		return here
	return approach_path[1]


## The enemy navigation has to deal with, or null when the missing route is the
## terrain's own fault (a wall the hero can never walk around).
##
## An enemy counts as a blocker only when BOTH hold:
##   1. it is what stands in the way — with every living enemy's cell treated as free, a
##      route to the destination exists, so removing ACTORS opens the way;
##   2. the hero can actually start that fight — one of the free cells inside its attack
##      range is reachable.
## Among those, the closest one to the hero wins (and, on a tie, the one nearest the
## destination), so navigation never picks a fight it cannot begin.
func _find_blocking_enemy() -> EnemyController:
	var here: Vector2i = _player.grid_position
	var living: Array[EnemyController] = _living_enemies()
	if living.is_empty():
		return null

	var occupied_cells: Array[Vector2i] = []
	for enemy in living:
		occupied_cells.append(enemy.grid_position)
	if _grid.find_path(here, _target_cell, occupied_cells).size() < 2:
		return null

	var best: EnemyController = null
	var best_cost: int = 2147483647
	var best_to_target: int = 2147483647
	for enemy in living:
		var approach: Vector2i = _approach_cell(enemy)
		if approach == Vector2i(-1, -1):
			continue
		var cost: int = 0
		if approach != here:
			var path: Array[Vector2i] = _grid.find_path(here, approach)
			if path.size() < 2:
				continue
			cost = path.size() - 1
		var to_target: int = _cell_distance(approach, _target_cell)
		if cost < best_cost or (cost == best_cost and to_target < best_to_target):
			best = enemy
			best_cost = cost
			best_to_target = to_target
	return best


## A free cell the hero can strike `enemy` from: its own cell when it is already in
## reach, otherwise the closest reachable cell inside the hero's attack range. Returns
## Vector2i(-1, -1) when no such cell exists (the enemy is walled off).
##
## The range is the hero's own `attack_range` — the same number CombatSystem.can_attack
## uses — so "in reach" here can never disagree with what a real attack accepts.
func _approach_cell(enemy: EnemyController) -> Vector2i:
	if _grid == null or enemy == null:
		return Vector2i(-1, -1)
	var here: Vector2i = _player.grid_position
	var enemy_cell: Vector2i = enemy.grid_position
	var attack_range: int = _get_player_attack_range()
	var best: Vector2i = Vector2i(-1, -1)
	var best_cost: int = 2147483647
	for y in range(enemy_cell.y - attack_range, enemy_cell.y + attack_range + 1):
		for x in range(enemy_cell.x - attack_range, enemy_cell.x + attack_range + 1):
			var cell := Vector2i(x, y)
			if _cell_distance(cell, enemy_cell) > attack_range:
				continue
			if cell == enemy_cell or not _grid.is_walkable(cell) or _grid.is_occupied(cell):
				continue
			if cell == here:
				return here
			var path: Array[Vector2i] = _grid.find_path(here, cell)
			if path.size() < 2:
				continue
			var cost: int = path.size() - 1
			if cost < best_cost:
				best_cost = cost
				best = cell
	return best


func _living_enemies() -> Array[EnemyController]:
	var living: Array[EnemyController] = []
	if _stage_manager == null or not _stage_manager.has_method("get_spawned_enemies"):
		return living
	for enemy_node in _stage_manager.get_spawned_enemies():
		var enemy := enemy_node as EnemyController
		if enemy == null or not is_instance_valid(enemy) or enemy.is_defeated():
			continue
		if enemy.enemy_runtime == null or enemy.enemy_runtime.current_hp <= 0:
			continue
		living.append(enemy)
	return living


func _get_player_attack_range() -> int:
	if _player == null or _player.player_stats == null:
		return 1
	return maxi(_player.player_stats.attack_range, 0)


func _cell_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


func _finish(reason: StringName) -> void:
	if _state != State.NAVIGATING:
		return
	_state = State.COMPLETED if reason == REASON_ARRIVED else State.CANCELLED
	_target_cell = Vector2i(-1, -1)
	_blocker = null
	navigation_finished.emit(reason)
