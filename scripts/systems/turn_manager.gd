class_name TurnManager
extends Node

signal state_changed(state: TurnState)
signal player_turn_started
signal enemy_turn_started(enemy: Node)
signal player_action_completed
signal enemy_actions_completed
signal combat_victory
signal combat_defeat

@export var default_movement_points: int = 3

var turn_state: TurnState = TurnState.new()
var _player: Node
var _enemies: Array[Node] = []
var _enemy_index: int = 0
## Optional presentation gate injected by the combat scene (see
## set_enemy_phase_waiter). When set, entering the enemy phase waits until the
## player's attack animation from its just-finished action has played out, so
## enemies never move or hit in the same beat as the hero's own swing.
var _enemy_phase_waiter: Object = null


func start_combat(player: Node, enemies: Array[Node] = []) -> void:
	_player = player
	_enemies = enemies.duplicate()
	_enemy_index = 0
	turn_state = TurnState.new()
	turn_state.begin_player_turn(_get_player_movement_points())
	if _player.has_signal("action_completed"):
		var player_action_signal: Signal = _player.action_completed
		if not player_action_signal.is_connected(_on_player_action_completed):
			player_action_signal.connect(_on_player_action_completed)
	if _player.has_method("attach_turn_manager"):
		_player.attach_turn_manager(self)
	if _player.has_method("begin_player_turn"):
		_player.begin_player_turn(turn_state.movement_points_remaining)
	_emit_state()
	player_turn_started.emit()


func add_enemy(enemy: Node) -> void:
	if enemy == null or _enemies.has(enemy):
		return
	_enemies.append(enemy)


## Injects the combat-presentation layer used to delay the enemy phase until
## the player's attack animation has finished. Kept optional so the turn
## manager stays fully runnable (and synchronous) without presentation in
## isolated tests and tooling.
func set_enemy_phase_waiter(waiter: Object) -> void:
	_enemy_phase_waiter = waiter


func complete_player_turn() -> void:
	if turn_state.phase != TurnState.PLAYER_TURN:
		return
	if turn_state.action_available:
		turn_state.action_available = false
		player_action_completed.emit()
	if _player != null and _player.has_method("end_player_turn"):
		_player.end_player_turn()
	_begin_enemy_phase()


func is_action_available(actor: Node = null) -> bool:
	if turn_state.phase != TurnState.PLAYER_TURN or not turn_state.action_available:
		return false
	return actor == null or actor == _player


func is_active_actor(actor: Node) -> bool:
	if actor == null or turn_state.phase != TurnState.ENEMY_TURN:
		return false
	if _enemy_index <= 0 or _enemy_index > _enemies.size():
		return false
	return _enemies[_enemy_index - 1] == actor


func consume_player_action(actor: Node) -> bool:
	if not is_action_available(actor):
		return false
	turn_state.action_available = false
	return true


func complete_enemy_turn(enemy: Node) -> void:
	if turn_state.phase != TurnState.ENEMY_TURN:
		return
	if _enemy_index <= 0 or _enemy_index > _enemies.size():
		return
	var expected_enemy: Node = _enemies[_enemy_index - 1]
	if enemy != expected_enemy:
		return
	_run_next_enemy_turn()


func set_victory() -> void:
	if turn_state.phase == TurnState.VICTORY or turn_state.phase == TurnState.DEFEAT:
		return
	turn_state.phase = TurnState.VICTORY
	turn_state.action_available = false
	_emit_state()
	combat_victory.emit()


func set_defeat() -> void:
	if turn_state.phase == TurnState.VICTORY or turn_state.phase == TurnState.DEFEAT:
		return
	turn_state.phase = TurnState.DEFEAT
	turn_state.action_available = false
	_emit_state()
	combat_defeat.emit()


func get_phase() -> int:
	return turn_state.phase


func is_player_turn() -> bool:
	return turn_state.phase == TurnState.PLAYER_TURN


func is_enemy_turn() -> bool:
	return turn_state.phase == TurnState.ENEMY_TURN


func _begin_enemy_phase() -> void:
	if _enemies.is_empty():
		_begin_player_phase()
		return
	# Enter the enemy phase immediately: the player's action already ended the
	# turn, and announcing the phase now blocks a second action from slipping in
	# while we wait. The first enemy *action* is then deferred until the hero's
	# attack animation has finished, so the swing reads as complete on screen
	# before enemies react to it.
	turn_state.phase = TurnState.ENEMY_TURN
	turn_state.active_actor_id = &"enemy"
	_enemy_index = 0
	_emit_state()
	await _wait_for_player_attack_presentation()
	if turn_state.phase != TurnState.ENEMY_TURN:
		return
	_run_next_enemy_turn()


## Blocks the first enemy action until the player's attack presentation reports
## idle. Polls the optional waiter with a bounded deadline so a missing or
## interrupted animation can never stall combat. No waiter = no waiting.
func _wait_for_player_attack_presentation() -> void:
	var waiter: Object = _enemy_phase_waiter
	if waiter == null or not is_instance_valid(waiter) or not waiter.has_method("is_player_attack_active"):
		return
	if not bool(waiter.call("is_player_attack_active")):
		return
	var tree := get_tree()
	if tree == null:
		return
	const MAX_WAIT_SECONDS: float = 6.0
	const POLL_INTERVAL_SECONDS: float = 0.03
	var remaining: float = MAX_WAIT_SECONDS
	while remaining > 0.0:
		if not is_instance_valid(waiter) or not waiter.has_method("is_player_attack_active"):
			return
		if not bool(waiter.call("is_player_attack_active")):
			return
		var poll_timer := tree.create_timer(POLL_INTERVAL_SECONDS)
		await poll_timer.timeout
		remaining -= POLL_INTERVAL_SECONDS


func _run_next_enemy_turn() -> void:
	if turn_state.phase != TurnState.ENEMY_TURN:
		return
	if _enemy_index >= _enemies.size():
		enemy_actions_completed.emit()
		_begin_player_phase()
		return

	var enemy: Node = _enemies[_enemy_index]
	_enemy_index += 1
	turn_state.active_actor_id = _get_actor_id(enemy, &"enemy")
	_emit_state()
	enemy_turn_started.emit(enemy)
	if enemy.has_method("take_turn"):
		enemy.take_turn(_player, self)
	else:
		complete_enemy_turn(enemy)


func _begin_player_phase() -> void:
	turn_state.turn_number += 1
	turn_state.begin_player_turn(_get_player_movement_points())
	if _player != null and _player.has_method("begin_player_turn"):
		_player.begin_player_turn(turn_state.movement_points_remaining)
	_emit_state()
	player_turn_started.emit()


func _on_player_action_completed() -> void:
	complete_player_turn()


func _get_player_movement_points() -> int:
	if _player != null and _player.get("player_stats") is PlayerStats:
		var stats: PlayerStats = _player.get("player_stats")
		return maxi(stats.movement_points, 0)
	return maxi(default_movement_points, 0)


func _get_actor_id(actor: Node, fallback: StringName) -> StringName:
	if actor.get("enemy_id") is StringName:
		return StringName(actor.get("enemy_id"))
	if actor.get("player_id") is StringName:
		return StringName(actor.get("player_id"))
	return fallback


func _emit_state() -> void:
	state_changed.emit(turn_state)
