extends SceneTree

class MockEnemy:
	extends Node

	var turn_count: int = 0

	func take_turn(_player: Node, manager: TurnManager) -> void:
		turn_count += 1
		manager.complete_enemy_turn(self)


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var player := Node.new()
	player.set("player_stats", PlayerStats.new())
	root.add_child(player)

	var enemy := MockEnemy.new()
	root.add_child(enemy)

	var manager := TurnManager.new()
	root.add_child(manager)
	manager.start_combat(player, [enemy])
	_expect(manager.is_player_turn(), "combat starts on the player turn")
	_expect(manager.turn_state.turn_number == 1, "combat starts on turn one")

	manager.complete_player_turn()
	_expect(enemy.turn_count == 1, "one enemy receives one enemy turn")
	_expect(manager.is_player_turn(), "enemy completion returns control to the player")
	_expect(manager.turn_state.turn_number == 2, "turn number advances after enemy actions")

	manager.complete_player_turn()
	_expect(enemy.turn_count == 2, "the enemy acts again on the next cycle")
	_expect(manager.is_player_turn(), "second cycle returns to the player")

	manager.set_victory()
	_expect(manager.get_phase() == TurnState.VICTORY, "victory state is terminal")
	manager.complete_player_turn()
	_expect(enemy.turn_count == 2, "terminal state rejects further player turns")

	if _failures.is_empty():
		print("Phase 5 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
