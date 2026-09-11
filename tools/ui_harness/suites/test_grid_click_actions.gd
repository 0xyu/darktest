extends "res://tools/ui_harness/ui_harness_suite.gd"

## Battlefield CLICK commands.
##
## The model under test: a left click on a cell walks the hero there, but never
## further than the movement range of the current turn; a left click on an enemy
## attacks it (and an out-of-range enemy click only selects the target instead of
## wasting the turn on a miss).
##
## Clicks are pushed through the REAL GUI pipeline (viewport input -> the HUD's
## CombatSection -> grid_combat), so the suite proves the whole input path and not
## just the movement rule.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")

var _grid_test: Node


func suite_name() -> String:
	return "test_grid_click_actions"


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_grid_test = instance.find_child("grid_combat", true, false)
	# Let stage generation, turn start and the first HUD layout settle.
	await flush_frames(6)


func _player() -> Node:
	return _grid_test.find_child("Player", true, false)


func _grid() -> Node:
	return _grid_test.find_child("Grid", true, false)


func _turn_manager() -> Node:
	return _grid_test.find_child("TurnManager", true, false)


func _living_enemies() -> Array:
	var living: Array = []
	var manager: Node = _grid_test.find_child("StageManager", true, false)
	var spawned: Array = manager.call("get_spawned_enemies") as Array if manager != null else []
	for enemy in spawned:
		if enemy != null and is_instance_valid(enemy) and not bool(enemy.call("is_defeated")):
			living.append(enemy)
	return living


func _cell_of(actor: Node) -> Vector2i:
	return actor.get("grid_position")


func _distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


func _free_cell(cell: Vector2i) -> bool:
	var grid := _grid()
	return bool(grid.call("is_walkable", cell)) and not bool(grid.call("is_occupied", cell))


func _stage() -> Node:
	return _grid_test.find_child("StageManager", true, false)


## Clears the fight the deterministic way (no damage math): defeating every
## spawned enemy is what puts the hero into free roam.
func _defeat_all_enemies() -> void:
	var guard: int = 0
	while guard < 80:
		var living: Array = _living_enemies()
		if living.is_empty():
			break
		living[0].call("handle_defeat")
		guard += 1
		await flush_frames(1)


## A free cell at least 3 cells away from `start`, preferring the middle rows so
## the click lands on the open battlefield rather than under a HUD panel.
func _far_free_cell(start: Vector2i) -> Vector2i:
	var grid := _grid()
	var grid_size: Vector2i = grid.get("grid_size")
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: int = 0
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if cell == start or not _free_cell(cell):
				continue
			var cell_distance: int = _distance(start, cell)
			if cell_distance < 3:
				continue
			if cell.y >= 2 and cell.y <= 4:
				return cell
			if cell_distance > best_distance:
				best_distance = cell_distance
				best = cell
	return best


## Pushes a real left click at the centre of `cell` through the viewport's GUI
## pipeline — the same route a mouse click takes in the running game.
func _click_cell(cell: Vector2i) -> void:
	var position: Vector2 = _grid().call("grid_to_world", cell) as Vector2
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	press.global_position = position
	_tree.root.push_input(press, false)


## A destination inside the movement range that costs more than one step and, when
## possible, sits in the middle rows of the battlefield so the click lands on the
## open area rather than under a HUD panel.
func _multi_step_destination(start: Vector2i, points: int) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var reachable: Array = _grid().call("get_reachable_cells", start, points)
	for cell in reachable:
		if cell == start:
			continue
		var path: Array = _grid().call("find_path", start, cell)
		if path.size() >= 3:
			candidates.append(cell)
	var middle: Array[Vector2i] = []
	for cell in candidates:
		if cell.y >= 2 and cell.y <= 4:
			middle.append(cell)
	return middle if not middle.is_empty() else candidates


# --- Tests ---------------------------------------------------------------

## Free roam (the mode a cleared stage puts the hero in) must keep accepting
## battlefield clicks: there the walk is unbounded, exactly like the AUTO walk to
## the stage exit and the D-pad step.
func test_click_in_free_roam_walks_the_hero_to_the_clicked_cell() -> void:
	await _mount_game()
	var player := _player()
	await _defeat_all_enemies()
	await flush_frames(3)
	expect(bool(player.call("is_free_moving")), "clearing the stage puts the hero into free roam")
	var start: Vector2i = _cell_of(player)
	var target: Vector2i = _far_free_cell(start)
	expect(target != Vector2i(-1, -1), "a free cell at least 3 cells away exists")
	if target == Vector2i(-1, -1):
		return

	_click_cell(target)
	await flush_frames(3)

	expect_eq(_cell_of(player), target, "a click in free roam walks the hero to the clicked cell")


## A tap on the hero's own cell must never leave the hero unable to act: with
## click-to-move, a deselected hero ignores every click AND every D-pad step
## (try_move returns false while !is_selected), so one stray tap on the hero would
## silently freeze the player.
func test_clicking_the_hero_cell_never_freezes_the_hero() -> void:
	await _mount_game()
	var player := _player()
	await _defeat_all_enemies()
	await flush_frames(3)
	expect(bool(player.call("is_free_moving")), "clearing the stage puts the hero into free roam")
	var start: Vector2i = _cell_of(player)

	_click_cell(start)
	await flush_frames(1)
	expect(bool(player.get("is_selected")), "a tap on the hero keeps it selected")

	var target: Vector2i = _far_free_cell(start)
	expect(target != Vector2i(-1, -1), "a free cell at least 3 cells away exists")
	if target == Vector2i(-1, -1):
		return
	_click_cell(target)
	await flush_frames(3)
	expect_eq(_cell_of(player), target, "a tap on the hero does not freeze free-roam clicking")


## The top battlefield row sits under the enemy summary panel. That panel is a
## read-only readout, so the click must pass through it and still reach the grid.
func test_click_on_the_top_row_reaches_the_battlefield() -> void:
	await _mount_game()
	var player := _player()
	await _defeat_all_enemies()
	await flush_frames(3)
	var grid_size: Vector2i = _grid().get("grid_size")
	var target: Vector2i = Vector2i(-1, -1)
	for x in range(2, grid_size.x):
		var cell := Vector2i(x, 0)
		if _free_cell(cell):
			target = cell
			break
	expect(target != Vector2i(-1, -1), "a free cell in the top battlefield row exists")
	if target == Vector2i(-1, -1):
		return

	_click_cell(target)
	await flush_frames(3)

	expect_eq(_cell_of(player), target, "a click in the top row reaches the battlefield")


func test_click_on_a_reachable_cell_walks_the_hero_there() -> void:
	await _mount_game()
	var player := _player()
	var start: Vector2i = _cell_of(player)
	var points: int = int(player.get("movement_points_remaining"))
	expect(points > 0, "the hero starts the turn with movement points")

	var candidates: Array[Vector2i] = _multi_step_destination(start, points)
	expect(not candidates.is_empty(), "a multi-step destination inside the movement range exists")
	if candidates.is_empty():
		return
	var target: Vector2i = candidates[0]
	var cost: int = (_grid().call("find_path", start, target) as Array).size() - 1

	_click_cell(target)
	await flush_frames(2)

	expect_eq(_cell_of(player), target, "clicking a reachable cell walks the hero onto it")
	expect_eq(
		int(player.get("movement_points_remaining")),
		points - cost,
		"the click-walk spends exactly one movement point per cell"
	)


func test_click_outside_the_movement_range_does_not_move() -> void:
	await _mount_game()
	var player := _player()
	var grid := _grid()
	var start: Vector2i = _cell_of(player)
	var points: int = int(player.get("movement_points_remaining"))
	var reachable: Array = grid.call("get_reachable_cells", start, points)
	var grid_size: Vector2i = grid.get("grid_size")

	var far_cell: Vector2i = Vector2i(-1, -1)
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if reachable.has(cell) or not _free_cell(cell):
				continue
			far_cell = cell
	expect(far_cell != Vector2i(-1, -1), "a walkable cell beyond the movement range exists")

	_click_cell(far_cell)
	await flush_frames(2)

	expect_eq(_cell_of(player), start, "a click beyond the movement range leaves the hero in place")
	expect_eq(
		int(player.get("movement_points_remaining")),
		points,
		"an out-of-range click spends no movement points"
	)


## Puts `enemy` on an OPEN battle cell (middle rows, right half) and returns that
## cell. Spawn cells are random, and the bottom grid row lies under the action bar
## — a tap there presses a HUD button instead of reaching the battlefield — so a
## test that clicked a randomly spawned enemy cell would be flaky. Occupancy is
## moved through the production grid API, like EnemyController._move_toward_target.
func _relocate_enemy_to_open_cell(enemy: Node) -> Vector2i:
	var grid := _grid()
	var grid_size: Vector2i = grid.get("grid_size")
	for y in range(1, grid_size.y - 1):
		for x in range(3, grid_size.x):
			var cell := Vector2i(x, y)
			if not _free_cell(cell):
				continue
			if not bool(grid.call("set_occupied", cell, StringName(enemy.get("enemy_id")))):
				continue
			grid.call("clear_occupied", _cell_of(enemy))
			enemy.set("grid_position", cell)
			enemy.set("global_position", grid.call("grid_to_world", cell))
			return cell
	return Vector2i(-1, -1)


func test_click_on_an_enemy_in_range_attacks_it() -> void:
	await _mount_game()
	var player := _player()
	var enemies: Array = _living_enemies()
	expect(not enemies.is_empty(), "the stage spawned a living enemy")
	if enemies.is_empty():
		return
	var enemy: Node = enemies[0]
	var enemy_cell: Vector2i = _relocate_enemy_to_open_cell(enemy)
	expect(enemy_cell != Vector2i(-1, -1), "the enemy can stand on an open battlefield cell")
	if enemy_cell == Vector2i(-1, -1):
		return

	var approach: Vector2i = Vector2i(-1, -1)
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate: Vector2i = enemy_cell + direction
		if _distance(candidate, enemy_cell) <= 1 and _free_cell(candidate):
			approach = candidate
			break
	expect(approach != Vector2i(-1, -1), "a free cell next to the enemy exists")
	if approach == Vector2i(-1, -1):
		return
	expect(bool(player.call("place_at", approach)), "the hero can stand next to the enemy")

	var runtime = enemy.get("enemy_runtime")
	var hp_before: int = int(runtime.get("current_hp"))
	_click_cell(enemy_cell)
	await flush_frames(1)

	expect_eq(player.call("get_target"), enemy, "the clicked enemy becomes the selected target")
	expect(
		int(runtime.get("current_hp")) < hp_before,
		"clicking an enemy in range attacks it"
	)


func test_click_on_an_out_of_range_enemy_does_not_waste_the_turn() -> void:
	await _mount_game()
	var player := _player()
	var enemies: Array = _living_enemies()
	expect(not enemies.is_empty(), "the stage spawned a living enemy")
	if enemies.is_empty():
		return
	var enemy: Node = enemies[0]
	var enemy_cell: Vector2i = _relocate_enemy_to_open_cell(enemy)
	expect(enemy_cell != Vector2i(-1, -1), "the enemy can stand on an open battlefield cell")
	if enemy_cell == Vector2i(-1, -1):
		return

	# Stand far away from every enemy, so the click cannot reach any of them.
	var grid := _grid()
	var grid_size: Vector2i = grid.get("grid_size")
	var far_cell: Vector2i = Vector2i(-1, -1)
	var best_distance: int = -1
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if not _free_cell(cell):
				continue
			var candidate_distance: int = _distance(cell, enemy_cell)
			if candidate_distance > best_distance:
				best_distance = candidate_distance
				far_cell = cell
	expect(best_distance > 1, "a free cell outside the enemy's attack range exists")
	if best_distance <= 1:
		return
	expect(bool(player.call("place_at", far_cell)), "the hero can stand out of the enemy's range")

	var runtime = enemy.get("enemy_runtime")
	var hp_before: int = int(runtime.get("current_hp"))
	_click_cell(enemy_cell)
	await flush_frames(1)

	expect_eq(player.call("get_target"), enemy, "the clicked enemy is still selected")
	expect_eq(
		int(runtime.get("current_hp")),
		hp_before,
		"an out-of-range enemy click does not attack"
	)
	expect(bool(_turn_manager().call("is_player_turn")), "an out-of-range enemy click keeps the player's turn")
