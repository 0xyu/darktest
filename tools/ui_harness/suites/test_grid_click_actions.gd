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
const TurnStateScript := preload("res://scripts/combat/turn_state.gd")

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


## A free cell next to `start`, preferring the middle rows so a click on it lands on
## the open battlefield rather than under a HUD panel. This is the destination of a
## single step, the walk that can spend the last movement point of a turn.
func _adjacent_free_cell(start: Vector2i) -> Vector2i:
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for direction in directions:
		var cell: Vector2i = start + direction
		if cell.y >= 2 and cell.y <= 4 and _free_cell(cell):
			return cell
	for direction in directions:
		var cell: Vector2i = start + direction
		if _free_cell(cell):
			return cell
	return Vector2i(-1, -1)


## The destination geometry for the automatic-strike tests: a free step target in the
## middle rows (so a click on it lands on the battlefield rather than under a HUD
## panel), a free cell beside it for the hero to start from, and `enemy_slots` further
## free cells around the target for enemies to stand on inside the hero's attack range.
## Empty when the board has no such arrangement.
func _step_geometry(enemy_slots: int) -> Dictionary:
	var grid_size: Vector2i = _grid().get("grid_size")
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for y in range(2, mini(grid_size.y - 1, 5)):
		for x in range(1, grid_size.x - 1):
			var cell := Vector2i(x, y)
			if not _free_cell(cell):
				continue
			var neighbours: Array[Vector2i] = []
			for direction in directions:
				var neighbour: Vector2i = cell + direction
				if _free_cell(neighbour):
					neighbours.append(neighbour)
			if neighbours.size() < enemy_slots + 1:
				continue
			return {"start": neighbours[0], "cell": cell, "slots": neighbours.slice(1)}
	return {}


## Puts `enemy` on `cell` through the production grid API (occupancy and position),
## exactly like _relocate_enemy_to_open_cell places one on a cell of its own choosing.
func _place_enemy_at(enemy: Node, cell: Vector2i) -> void:
	var grid := _grid()
	grid.call("clear_occupied", _cell_of(enemy))
	grid.call("set_occupied", cell, StringName(enemy.get("enemy_id")))
	enemy.set("grid_position", cell)
	enemy.set("global_position", grid.call("grid_to_world", cell))


## Moves every living enemy as far from `cell` as the board allows, so a test decides
## exactly which enemy (if any) ends up inside the hero's attack range.
func _park_enemies_away_from(cell: Vector2i) -> void:
	var grid_size: Vector2i = _grid().get("grid_size")
	for enemy in _living_enemies():
		var destination: Vector2i = _cell_of(enemy)
		var best_distance: int = _distance(cell, destination)
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				var candidate := Vector2i(x, y)
				if not _free_cell(candidate):
					continue
				var candidate_distance: int = _distance(cell, candidate)
				if candidate_distance > best_distance:
					destination = candidate
					best_distance = candidate_distance
		_place_enemy_at(enemy, destination)


func _enemy_hp(enemy: Node) -> int:
	return int(enemy.get("enemy_runtime").get("current_hp"))


func _total_enemy_hp() -> int:
	var total: int = 0
	for enemy in _living_enemies():
		total += _enemy_hp(enemy)
	return total


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


## A click BEYOND the movement range is no longer a refusal: it arms a persistent
## navigation destination (see test_grid_navigation for the multi-turn walk itself).
## The hero still spends exactly one movement point per cell walked this turn, and the
## destination is kept for its own following turns.
func test_click_outside_the_movement_range_arms_a_destination() -> void:
	await _mount_game()
	var player := _player()
	var grid := _grid()
	var navigation: Node = _grid_test.find_child("NavigationController", true, false)
	expect(navigation != null, "the scene has a navigation controller")
	if navigation == null:
		return
	var start: Vector2i = _cell_of(player)
	var points: int = int(player.get("movement_points_remaining"))
	var reachable: Array = grid.call("get_reachable_cells", start, points)
	var grid_size: Vector2i = grid.get("grid_size")

	# A cell that IS reachable in the end, but not with this turn's movement points: the
	# walk has a route, it simply cannot finish it yet.
	var far_cell: Vector2i = Vector2i(-1, -1)
	var far_steps: int = 0
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if reachable.has(cell) or not _free_cell(cell):
				continue
			var path: Array = grid.call("find_path", start, cell)
			if path.size() < 2:
				continue
			if path.size() - 1 > far_steps:
				far_steps = path.size() - 1
				far_cell = cell
	expect(far_cell != Vector2i(-1, -1), "a walkable cell beyond the movement range exists")
	if far_cell == Vector2i(-1, -1):
		return

	_click_cell(far_cell)

	# Asserted before the deferred continuation can walk again: the click armed the
	# destination and walked the first cells of the route. Running out of movement ends
	# the turn the normal way, so the enemy phase and the next player turn may already
	# have happened inside the click — the walk must simply still be aimed at the cell.
	expect(bool(navigation.call("is_navigating")), "a click beyond the range starts automatic navigation")
	expect_eq(
		navigation.call("get_navigation_target"),
		far_cell,
		"the clicked cell becomes the navigation target"
	)
	expect_ne(_cell_of(player), start, "the hero walks toward the clicked cell at once")
	expect(
		_distance(_cell_of(player), far_cell) < _distance(start, far_cell),
		"the walk closes the distance to the clicked cell"
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


## Once the hero has spent every movement point, a move click can no longer be a
## walk: it ends the turn, exactly like the END TURN button, instead of leaving the
## player clicking a battlefield that refuses every cell. This is the state a turn
## STARTS in when the hero's stats grant no movement, and the safety net behind the
## automatic end-of-walk trigger tested below.
func test_click_with_no_movement_points_left_ends_the_turn() -> void:
	await _mount_game()
	var player := _player()
	var turn_manager := _turn_manager()
	var start: Vector2i = _cell_of(player)
	expect_eq(
		int(turn_manager.call("get_phase")),
		TurnStateScript.PLAYER_TURN,
		"the click happens on the hero's own turn"
	)

	var points: int = int(player.get("movement_points_remaining"))
	expect(points > 0, "the hero starts the turn with movement points")
	var candidates: Array[Vector2i] = _multi_step_destination(start, points)
	expect(not candidates.is_empty(), "a multi-step destination inside the movement range exists")
	if candidates.is_empty():
		return
	var target: Vector2i = candidates[0]

	var completed: Array[bool] = []
	turn_manager.connect("player_action_completed", func() -> void: completed.append(true))

	# The destination itself stays legal — only the movement points are gone, so the
	# click is refused for the empty tank and nothing else.
	player.set("movement_points_remaining", 0)
	_click_cell(target)
	await flush_frames(1)

	expect_eq(completed.size(), 1, "a move click with no movement points ends the turn")
	expect_eq(_cell_of(player), start, "the hero does not walk when the click ends the turn")


## Free roam is exempt from the empty-tank rule: a cleared stage spends no movement
## points, so a click there keeps walking even when the counter reads zero.
func test_free_roam_click_still_walks_with_no_movement_points() -> void:
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

	player.set("movement_points_remaining", 0)
	_click_cell(target)
	await flush_frames(3)

	expect_eq(_cell_of(player), target, "free roam still walks with an empty movement-point counter")


## With no enemy inside the attack range, a walk that spends the turn's last movement
## point ends the turn on the spot: the click flow settles the turn by itself, so the
## player never has to click a second time to be finished.
func test_the_last_movement_point_ends_the_turn_with_nothing_in_reach() -> void:
	await _mount_game()
	var player := _player()
	var turn_manager := _turn_manager()
	var geometry: Dictionary = _step_geometry(0)
	expect(not geometry.is_empty(), "the board has a free step with a free cell beside it")
	if geometry.is_empty():
		return
	var start: Vector2i = geometry["start"]
	var target: Vector2i = geometry["cell"]
	# Every enemy is moved to the far side of the board, so nothing is inside the
	# hero's attack range by the time the walk arrives.
	_park_enemies_away_from(target)
	expect(not _living_enemies().is_empty(), "the stage still has an enemy to be out of reach")
	expect(bool(player.call("place_at", start)), "the hero can stand next to the step")

	var completed: Array[bool] = []
	turn_manager.connect("player_action_completed", func() -> void: completed.append(true))
	var enemy_hp_before: int = _total_enemy_hp()

	player.set("movement_points_remaining", 1)
	_click_cell(target)
	await flush_frames(1)

	expect_eq(_cell_of(player), target, "the last movement point still walks the hero")
	expect_eq(completed.size(), 1, "the turn ends on the spot when nothing is in reach")
	expect_eq(_total_enemy_hp(), enemy_hp_before, "an enemy out of reach is never struck")


## An enemy inside the attack range is struck with the turn's remaining action instead
## of the turn simply ending, so the walk that spends the last point also lands the hit.
func test_the_last_movement_point_attacks_an_enemy_in_range() -> void:
	await _mount_game()
	var player := _player()
	var geometry: Dictionary = _step_geometry(1)
	expect(not geometry.is_empty(), "the board has a step with a free cell for an enemy")
	if geometry.is_empty():
		return
	var start: Vector2i = geometry["start"]
	var target: Vector2i = geometry["cell"]
	var slots: Array = geometry["slots"]
	var slot: Vector2i = slots[0]
	_park_enemies_away_from(target)
	var enemies: Array = _living_enemies()
	expect(not enemies.is_empty(), "the stage has a living enemy to strike")
	if enemies.is_empty():
		return
	expect(_free_cell(slot), "the enemy's cell is free once the others were parked away")
	expect(bool(player.call("place_at", start)), "the hero can stand next to the step")
	_place_enemy_at(enemies[0], slot)
	expect_eq(_distance(target, slot), 1, "the enemy waits inside the hero's attack range")

	var enemy_hp_before: int = _enemy_hp(enemies[0])
	player.set("movement_points_remaining", 1)
	_grid_test.call("_on_hud_move_requested", target - start)

	expect_eq(_cell_of(player), target, "the last movement point still walks the hero")
	expect(
		_enemy_hp(enemies[0]) < enemy_hp_before,
		"the enemy in reach is struck instead of the turn just ending"
	)
	expect(
		not bool(_turn_manager().call("is_player_turn")),
		"the automatic strike spends the action and ends the turn"
	)


## The enemy the player clicked is the one struck: a click on a distant enemy selects it
## as the target, and the walk that spends the last point then swings at THAT enemy even
## though another enemy stands just as close.
func test_the_last_movement_point_attacks_the_clicked_enemy() -> void:
	await _mount_game()
	var player := _player()
	# Stage 1 spawns one enemy, so a second one is brought in through the summon path
	# the mini bosses use: choosing between two enemies needs two of them on the board.
	var spawned: Array = _living_enemies()
	expect(not spawned.is_empty(), "the stage spawned a living enemy to summon")
	if spawned.is_empty():
		return
	spawned[0].emit_signal("summon_requested", spawned[0], 1)
	await flush_frames(2)

	var geometry: Dictionary = _step_geometry(2)
	expect(not geometry.is_empty(), "the board has a step with free cells for two enemies")
	if geometry.is_empty():
		return
	var start: Vector2i = geometry["start"]
	var target: Vector2i = geometry["cell"]
	var slots: Array = geometry["slots"]
	var slot_a: Vector2i = slots[0]
	var slot_b: Vector2i = slots[1]
	_park_enemies_away_from(target)
	var enemies: Array = _living_enemies()
	expect(enemies.size() >= 2, "the stage spawns two enemies to choose between")
	if enemies.size() < 2:
		return
	expect(_free_cell(slot_a) and _free_cell(slot_b), "both enemy cells are free after parking")
	expect(bool(player.call("place_at", start)), "the hero can stand next to the step")
	_place_enemy_at(enemies[0], slot_a)
	_place_enemy_at(enemies[1], slot_b)

	# The clicked enemy is deliberately the one the automatic target would NOT reach for
	# first, so a hit on it can only come from the click.
	var spawn_order: Array = _grid_test.get("_active_enemies")
	var clicked: Node = enemies[0] if spawn_order.find(enemies[0]) > spawn_order.find(enemies[1]) else enemies[1]
	var other: Node = enemies[1] if clicked == enemies[0] else enemies[0]
	_grid_test.call("_click_attack_enemy", clicked)
	expect_eq(player.call("get_target"), clicked, "a click on a distant enemy selects it as the target")

	var clicked_hp_before: int = _enemy_hp(clicked)
	var other_hp_before: int = _enemy_hp(other)
	player.set("movement_points_remaining", 1)
	_grid_test.call("_on_hud_move_requested", target - start)

	expect_eq(_cell_of(player), target, "the last movement point still walks the hero")
	expect(_enemy_hp(clicked) < clicked_hp_before, "the clicked enemy is the one the walk strikes")
	expect_eq(_enemy_hp(other), other_hp_before, "the other enemy in reach is left alone")


## AUTO owns its turn: it walks the hero toward a target and attacks in the SAME
## turn, so a walk that spends the last movement point must not end the turn out
## from under that attack. AUTO ends its own turn when the movement is really spent.
func test_a_full_cost_step_does_not_end_an_auto_owned_turn() -> void:
	await _mount_game()
	var player := _player()
	var auto_controller: Node = _grid_test.find_child("AutoCombatController", true, false)
	expect(auto_controller != null, "the scene has an AUTO controller")
	if auto_controller == null:
		return
	var start: Vector2i = _cell_of(player)
	var target: Vector2i = _adjacent_free_cell(start)
	expect(target != Vector2i(-1, -1), "a free cell next to the hero exists")
	if target == Vector2i(-1, -1):
		return

	# AUTO is mid-turn: enabling it only arms its decision timer, so the step below
	# is the only move that happens before the turn is inspected.
	auto_controller.call("set_auto_enabled", true)
	player.set("movement_points_remaining", 1)
	_grid_test.call("_on_hud_move_requested", target - start)

	expect_eq(_cell_of(player), target, "an AUTO-owned step still walks the hero")
	expect_eq(
		int(player.get("movement_points_remaining")),
		0,
		"the step spends the last movement point"
	)
	expect(
		bool(_turn_manager().call("is_player_turn")),
		"an AUTO-owned turn survives a walk that spends the last movement point"
	)
	auto_controller.call("set_auto_enabled", false)
