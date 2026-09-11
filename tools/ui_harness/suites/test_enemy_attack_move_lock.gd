extends "res://tools/ui_harness/ui_harness_suite.gd"

## Integration suite for the enemy-attack movement lock.
##
## The enemy turn ends the moment its strike is RESOLVED, so the attack animation
## keeps playing into the hero's turn. Acting from the cell the hero stands on must
## keep working (attack/skill/item — the intended feel), but stepping to ANOTHER
## cell must wait until that animation has completely finished.
##
## Mounts the real game scene (res://scenes/world/Main.tscn), walks the hero next to
## a spawned enemy, ends the turn, and inspects the live lock through the same seams
## the player uses (D-pad move request, click-to-move reachability, HUD attack).

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")

const STEP_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const LOCK_WAIT_TIMEOUT_SECONDS: float = 5.0
const LOCK_POLL_SECONDS: float = 0.05

var _grid_test: Node


func suite_name() -> String:
	return "test_enemy_attack_move_lock"


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_grid_test = instance.find_child("grid_combat", true, false)
	# Let stage generation, turn start, and HUD refresh settle.
	await flush_frames(6)


func _player() -> Node:
	return _grid_test.find_child("Player", true, false)


func _grid() -> Node:
	return _grid_test.find_child("Grid", true, false)


func _stage() -> Node:
	return _grid_test.find_child("StageManager")


func _turn() -> Node:
	return _grid_test.find_child("TurnManager")


func _cell_of(node: Node) -> Vector2i:
	return node.call("get_grid_position")


func _first_living_enemy() -> Node:
	for enemy in _stage().call("get_spawned_enemies"):
		if enemy != null and is_instance_valid(enemy) and not bool(enemy.call("is_defeated")):
			return enemy
	return null


func _is_free_cell(cell: Vector2i) -> bool:
	var grid := _grid()
	return bool(grid.call("is_walkable", cell)) and not bool(grid.call("is_occupied", cell))


## Places the hero on a free cell next to `enemy`; returns the cell it now stands
## on, or (-1,-1) when the enemy has no free neighbour.
func _stand_next_to(enemy: Node) -> Vector2i:
	var enemy_cell: Vector2i = _cell_of(enemy)
	for direction in STEP_DIRECTIONS:
		var cell: Vector2i = enemy_cell + direction
		if _is_free_cell(cell) and bool(_player().call("place_at", cell)):
			return cell
	return Vector2i(-1, -1)


## A free neighbour of `from_cell` other than `avoid`: the step the hero is asked
## to take while the lock is live (and again once it has cleared).
func _find_open_step(from_cell: Vector2i, avoid: Vector2i) -> Vector2i:
	for direction in STEP_DIRECTIONS:
		var cell: Vector2i = from_cell + direction
		if cell != avoid and _is_free_cell(cell):
			return cell
	return Vector2i(-1, -1)


## Sets up the reported scenario: the hero stands next to a living enemy, the
## player's turn ends and the enemy strikes. Returns
## { enemy, standing, step_cell } or an empty Dictionary when the starting stage
## cannot build it.
func _stage_enemy_strike() -> Dictionary:
	var enemy: Node = _first_living_enemy()
	if enemy == null:
		return {}
	var standing: Vector2i = _stand_next_to(enemy)
	if standing == Vector2i(-1, -1):
		return {}
	var step_cell: Vector2i = _find_open_step(standing, _cell_of(enemy))
	if step_cell == Vector2i(-1, -1):
		return {}
	_turn().call("complete_player_turn")
	return {"enemy": enemy, "standing": standing, "step_cell": step_cell}


## Polls the live lock until it clears (or the deadline expires) and returns the
## seconds it took. Real time must pass: the lock is held by animation tweens.
func _wait_for_lock_release(player: Node) -> float:
	var waited: float = 0.0
	while bool(player.call("is_movement_locked")) and waited < LOCK_WAIT_TIMEOUT_SECONDS:
		await _tree.create_timer(LOCK_POLL_SECONDS).timeout
		waited += LOCK_POLL_SECONDS
	return waited


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


func test_a_step_away_waits_for_the_enemy_attack_animation() -> void:
	await _mount_game()
	var scenario: Dictionary = _stage_enemy_strike()
	expect(not scenario.is_empty(), "the starting stage has an enemy with a free cell next to it")
	if scenario.is_empty():
		return

	var player := _player()
	var enemy: Node = scenario["enemy"]
	var standing: Vector2i = scenario["standing"]
	var step_cell: Vector2i = scenario["step_cell"]
	var step_direction: Vector2i = step_cell - standing

	# The strike is already resolved, so the hero's turn is live again while the
	# enemy's attack animation is still on screen.
	expect(bool(_turn().call("is_player_turn")), "the resolved enemy strike hands the turn back to the hero")
	expect(bool(player.call("is_movement_locked")), "the hero is movement-locked while the enemy's attack animation plays")
	expect(
		not bool(player.call("can_move_to", step_cell)),
		"no cell is reachable while the enemy's attack animation plays"
	)

	# Both of the player's movement paths must refuse the step: D-pad and click.
	var points_before: int = int(player.get("movement_points_remaining"))
	expect(points_before > 0, "the hero has movement points on this turn")
	_grid_test.call("_on_hud_move_requested", step_direction)
	expect_eq(_cell_of(player), standing, "a D-pad step is refused while the enemy's attack animation plays")
	_grid_test.call("_click_move_to", step_cell)
	expect_eq(_cell_of(player), standing, "a click-to-move step is refused while the enemy's attack animation plays")
	expect_eq(
		int(player.get("movement_points_remaining")),
		points_before,
		"a refused step spends no movement points"
	)

	# ... and the block is only temporary.
	var waited: float = await _wait_for_lock_release(player)
	expect(waited < LOCK_WAIT_TIMEOUT_SECONDS, "the movement lock is released once the enemy's attack has finished")
	expect(
		not bool(player.call("is_movement_locked")),
		"the lock is clear after the enemy's attack animation has completely finished"
	)

	# The enemy phase may have walked other enemies around, so the step is re-read
	# from the CURRENT board instead of reusing the cell picked before the turn.
	var open_step: Vector2i = _find_open_step(_cell_of(player), _cell_of(enemy))
	expect(open_step != Vector2i(-1, -1), "the hero still has a free cell to step to")
	if open_step == Vector2i(-1, -1):
		return
	expect(bool(player.call("can_move_to", open_step)), "moving is legal again once the animation is over")

	var cell_before_step: Vector2i = _cell_of(player)
	_grid_test.call("_on_hud_move_requested", open_step - cell_before_step)
	expect_eq(_cell_of(player), open_step, "the hero walks the step that was refused during the animation")


## Reported bug: after the hero is defeated and the stage restarts, the hero could
## still attack but no longer move. The restart must leave the hero fully playable.
func test_a_defeat_restart_leaves_the_hero_playable() -> void:
	await _mount_game()
	var player := _player()
	var enemy: Node = _first_living_enemy()
	expect(enemy != null, "the stage spawned a living enemy")
	if enemy == null:
		return
	expect(_stand_next_to(enemy) != Vector2i(-1, -1), "the hero can stand next to the enemy")

	# One enemy hit is lethal, which is the reported "keep ending the turn until the
	# hero dies" path.
	player.get("player_stats").current_hp = 1
	_turn().call("complete_player_turn")
	# Defeat -> deferred retreat -> stage restart, with the fatal attack animation
	# still in flight while the old enemies are freed and the arena is rebuilt.
	await flush_frames(4)
	await _tree.create_timer(0.5).timeout

	expect(not bool(player.call("is_defeated")), "the defeat restart revives the hero")
	expect(bool(_turn().call("is_player_turn")), "the restarted stage hands the turn back to the hero")
	expect(
		not bool(player.call("is_movement_locked")),
		"the defeat restart does not leave the hero movement-locked"
	)

	var open_step: Vector2i = _find_open_step(_cell_of(player), Vector2i(-1, -1))
	expect(open_step != Vector2i(-1, -1), "the hero has a free cell to step to after the restart")
	if open_step == Vector2i(-1, -1):
		return
	var standing: Vector2i = _cell_of(player)
	expect(bool(player.call("can_move_to", open_step)), "a step is legal again after the defeat restart")
	_grid_test.call("_on_hud_move_requested", open_step - standing)
	expect_eq(_cell_of(player), open_step, "the hero can move again after the defeat restart")


## The behavior the lock must never touch: acting from the cell the hero already
## stands on stays allowed while the enemy's attack animation plays.
func test_acting_from_the_current_cell_stays_allowed() -> void:
	await _mount_game()
	var scenario: Dictionary = _stage_enemy_strike()
	expect(not scenario.is_empty(), "the starting stage has an enemy with a free cell next to it")
	if scenario.is_empty():
		return

	var player := _player()
	var enemy: Node = scenario["enemy"]
	expect(bool(player.call("is_movement_locked")), "the hero is movement-locked while the enemy's attack animation plays")

	player.call("set_target", enemy)
	var enemy_runtime: Variant = enemy.get("enemy_runtime")
	var enemy_hp_before: int = int(enemy_runtime.current_hp)
	_grid_test.call("_on_hud_attack_requested")
	expect(
		int(enemy_runtime.current_hp) < enemy_hp_before or bool(enemy.call("is_defeated")),
		"the hero can still attack from the cell it stands on while the animation plays"
	)


## The lock is scoped to the PLAYER's input paths on purpose: AUTO takes its steps
## through the raw try_move() seam on a 0.05 s cadence, so gating that seam would
## make auto farming miss turns whenever an enemy animation is on screen.
func test_the_lock_never_gates_the_seam_auto_walks_with() -> void:
	await _mount_game()
	var scenario: Dictionary = _stage_enemy_strike()
	expect(not scenario.is_empty(), "the starting stage has an enemy with a free cell next to it")
	if scenario.is_empty():
		return

	var player := _player()
	var standing: Vector2i = scenario["standing"]
	var step_cell: Vector2i = scenario["step_cell"]
	expect(bool(player.call("is_movement_locked")), "the enemy's strike locks player movement")

	expect(
		bool(player.call("try_move", step_cell - standing)),
		"AUTO's raw step seam keeps working while the movement lock is live"
	)
	expect_eq(_cell_of(player), step_cell, "AUTO's step still lands on its destination cell")
