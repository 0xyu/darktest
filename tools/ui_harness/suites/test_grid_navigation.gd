extends "res://tools/ui_harness/ui_harness_suite.gd"

## Automatic NAVIGATION (click-to-navigate), the spec in
## `docs/coding-plans/pathfinding-implemention-specification.md`.
##
## The model under test: a click on a cell BEYOND this turn's movement range is no
## longer a refusal — it arms one persistent destination. The hero walks the cells this
## turn can pay for, the turn ends the normal way, and every following player turn
## continues the walk by itself until the hero arrives. A destination an ENEMY is
## standing in front of is fought for, and the destination itself is never replaced by
## the enemy. AUTO and FARMING keep their own state throughout.
##
## Clicks are pushed through the REAL GUI pipeline (viewport input -> the HUD's
## CombatSection -> grid_combat) and the walk goes through the hero's REAL input step,
## so the suite proves the whole path and not just the routing rule.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var _grid_test: Node


func suite_name() -> String:
	return "test_grid_navigation"


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


func _navigation() -> Node:
	return _grid_test.find_child("NavigationController", true, false)


func _hud() -> Node:
	return _grid_test.find_child("MobileCombatHUD", true, false)


func _auto() -> Node:
	return _grid_test.find_child("AutoCombatController", true, false)


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


func _path_steps(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var path: Array = _grid().call("find_path", from_cell, to_cell)
	return 0 if path.is_empty() else path.size() - 1


## Pushes a real left click at the centre of `cell` through the viewport's GUI pipeline
## — the same route a mouse click takes in the running game.
func _click_cell(cell: Vector2i) -> void:
	var position: Vector2 = _grid().call("grid_to_world", cell) as Vector2
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	press.global_position = position
	_tree.root.push_input(press, false)


## Puts `enemy` on `cell` through the production grid API (occupancy and position).
func _place_enemy_at(enemy: Node, cell: Vector2i) -> void:
	var grid := _grid()
	grid.call("clear_occupied", _cell_of(enemy))
	grid.call("set_occupied", cell, StringName(enemy.get("enemy_id")))
	enemy.set("grid_position", cell)
	enemy.set("global_position", grid.call("grid_to_world", cell))


## Moves every living enemy as far from `cell` as the board allows, so a walk cannot run
## into a fight the test did not arrange.
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


## A free destination `min_steps` cells away at least (so it can never be one turn's
## walk), preferring the cell furthest from every enemy so the walk stays a pure walk.
##
## The middle battlefield rows are searched first: the action bar sits over the lower
## rows and a click there presses a HUD button instead of reaching the grid, so a
## destination is only looked for in the whole field when the middle band has none.
func _far_destination(start: Vector2i, min_steps: int) -> Vector2i:
	for window in [[2, 4], [1, 4], [0, -1]]:
		var found: Vector2i = _search_destination(start, min_steps, int(window[0]), int(window[1]))
		if found != Vector2i(-1, -1):
			return found
	return Vector2i(-1, -1)


func _search_destination(start: Vector2i, min_steps: int, first_row: int, last_row: int) -> Vector2i:
	var grid_size: Vector2i = _grid().get("grid_size")
	var top_row: int = clampi(first_row, 0, grid_size.y - 1)
	var bottom_row: int = grid_size.y - 1 if last_row < 0 else clampi(last_row, 0, grid_size.y - 1)
	var best: Vector2i = Vector2i(-1, -1)
	var best_clearance: int = -1
	for y in range(top_row, bottom_row + 1):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if cell == start or not _free_cell(cell):
				continue
			var steps: int = _path_steps(start, cell)
			if steps < min_steps:
				continue
			var clearance: int = 2147483647
			for enemy in _living_enemies():
				clearance = mini(clearance, _distance(cell, _cell_of(enemy)))
			if clearance > best_clearance:
				best_clearance = clearance
				best = cell
	return best


## A destination whose ONLY two walkable neighbours are the cells returned in
## "blockers": with enemies standing on both of them the destination is unreachable
## while the terrain alone would allow it — the arrangement that makes an ACTOR, and
## not a wall, the reason a route is missing. "hero" is a free cell beside the first
## blocker, so the hero starts the arrangement already inside attack range.
func _blocked_destination() -> Dictionary:
	var grid := _grid()
	var grid_size: Vector2i = grid.get("grid_size")
	for y in range(grid_size.y):
		for x in range(1, grid_size.x - 1):
			var destination := Vector2i(x, y)
			if not _free_cell(destination):
				continue
			var blockers: Array[Vector2i] = []
			for direction in DIRECTIONS:
				var neighbour: Vector2i = destination + direction
				if bool(grid.call("is_walkable", neighbour)):
					blockers.append(neighbour)
			if blockers.size() != 2:
				continue
			for direction in DIRECTIONS:
				var hero_cell: Vector2i = blockers[0] + direction
				if hero_cell == destination or hero_cell == blockers[0] or hero_cell == blockers[1]:
					continue
				if not _free_cell(hero_cell):
					continue
				return {"destination": destination, "blockers": blockers, "hero": hero_cell}
	return {}


# --- Tests ---------------------------------------------------------------

## §5 / §14 / §27: a destination beyond the movement range is walked over several turns
## with NO further input. The hero spends exactly this turn's movement points on the
## first turn, keeps the destination, and reaches it on a later turn — while the
## "AUTO NAVIGATING" indicator is on for the whole walk (§13) and AUTO / FARMING are
## never touched (§12).
func test_a_far_destination_is_walked_over_several_turns() -> void:
	await _mount_game()
	var player := _player()
	var navigation := _navigation()
	var hud := _hud()
	var auto := _auto()
	expect(navigation != null, "the scene has a navigation controller")
	if navigation == null:
		return
	var auto_before: bool = bool(auto.call("is_auto_enabled"))
	var farming_before: bool = bool(auto.call("is_farming_enabled"))

	# One movement point per turn, so a two-step destination takes exactly two turns:
	# the multi-turn walk is what is under test, not the hero's default speed.
	_park_enemies_away_from(_cell_of(player))
	player.get("player_stats").set("movement_points", 1)
	player.call("reset_movement_points")
	var start: Vector2i = _cell_of(player)
	var target: Vector2i = _far_destination(start, 2)
	expect(target != Vector2i(-1, -1), "the arena has a free cell two steps away")
	if target == Vector2i(-1, -1):
		return

	_click_cell(target)

	# Asserted before the deferred continuation can walk again: the click armed the
	# destination and spent the turn's single movement point on the first cell of the
	# route. Running out of movement ends the turn the normal way, so the enemy phase
	# and the next player turn may already have happened inside the click — what must
	# still hold is that the walk is armed, aimed at the clicked cell, and exactly one
	# movement point's worth of walking happened.
	expect(bool(navigation.call("is_navigating")), "a click beyond the range arms a destination")
	expect_eq(
		navigation.call("get_navigation_target"),
		target,
		"the clicked cell is the navigation target"
	)
	expect_eq(
		_distance(start, _cell_of(player)),
		1,
		"the walk spends exactly this turn's movement point"
	)
	expect_ne(_cell_of(player), start, "the hero walks toward the destination at once")
	expect_ne(_cell_of(player), target, "one movement point is not enough for a two-step destination")
	expect(bool(hud.call("is_navigating")), "the AUTO NAVIGATING indicator is on while walking")

	# No further clicks: the walk continues on the hero's own following turns.
	var guard: int = 0
	while bool(navigation.call("is_navigating")) and guard < 240:
		guard += 1
		await flush_frames(1)

	expect_eq(_cell_of(player), target, "navigation reaches the destination without another click")
	expect(not bool(navigation.call("is_navigating")), "arriving ends the navigation")
	expect_eq(
		navigation.call("get_navigation_target"),
		Vector2i(-1, -1),
		"an arrived navigation clears its destination"
	)
	expect(not bool(hud.call("is_navigating")), "the AUTO NAVIGATING indicator is hidden again")
	expect_eq(
		bool(auto.call("is_auto_enabled")),
		auto_before,
		"navigation never toggles AUTO"
	)
	expect_eq(
		bool(auto.call("is_farming_enabled")),
		farming_before,
		"navigation never toggles FARMING"
	)


## §10 Case A + §11: an enemy standing in front of the destination is an intermediate
## blocker. The hero strikes it with its own attack seam (real damage, real turn), and
## the ORIGINAL destination stays the navigation target — the enemy never replaces it.
func test_an_enemy_blocking_the_destination_is_fought_for() -> void:
	await _mount_game()
	var player := _player()
	var navigation := _navigation()

	# Two actors are needed to wall the destination off, plus one spare so killing a
	# blocker can never clear the stage and end the battle the walk lives in.
	var enemies: Array = _living_enemies()
	expect(not enemies.is_empty(), "the stage spawned a living enemy")
	if enemies.is_empty():
		return
	_park_enemies_away_from(_cell_of(player))
	var summon_guard: int = 0
	while _living_enemies().size() < 3 and summon_guard < 4:
		summon_guard += 1
		enemies[0].emit_signal("summon_requested", enemies[0], 1)
		await flush_frames(2)
	enemies = _living_enemies()
	expect(enemies.size() >= 3, "three enemies stand on the board")
	if enemies.size() < 3:
		return

	var geometry: Dictionary = _blocked_destination()
	expect(not geometry.is_empty(), "the arena has a destination walled off by two actors")
	if geometry.is_empty():
		return
	var destination: Vector2i = geometry["destination"]
	var blockers: Array = geometry["blockers"]
	var hero_cell: Vector2i = geometry["hero"]

	expect(bool(player.call("place_at", hero_cell)), "the hero can stand beside the blocker")
	_place_enemy_at(enemies[0], blockers[0])
	_place_enemy_at(enemies[1], blockers[1])
	expect_eq(_path_steps(_cell_of(player), destination), 0, "the destination is unreachable while blocked")

	var hp_before: int = 0
	for enemy in enemies:
		if not bool(enemy.call("is_defeated")):
			hp_before += int(enemy.get("enemy_runtime").get("current_hp"))

	_click_cell(destination)
	await flush_frames(1)

	var hp_after: int = 0
	for enemy in enemies:
		if is_instance_valid(enemy) and not bool(enemy.call("is_defeated")):
			hp_after += int(enemy.get("enemy_runtime").get("current_hp"))
	expect(
		hp_after < hp_before,
		"a blocking enemy in reach is struck instead of the walk simply stopping"
	)
	expect(
		bool(navigation.call("is_navigating")),
		"the walk keeps the destination while the blocker is being dealt with"
	)
	expect_eq(
		navigation.call("get_navigation_target"),
		destination,
		"the blocking enemy never replaces the clicked destination"
	)

	# §11 / §28: the blocker is only intermediate. With it gone the destination is STILL
	# the target and the walk goes on instead of following the enemy.
	var living_after: Array = _living_enemies()
	expect(not living_after.is_empty(), "a blocker is still standing")
	if not living_after.is_empty():
		living_after[0].call("handle_defeat")
	await flush_frames(3)

	expect(
		bool(navigation.call("is_navigating")),
		"the walk survives the death of a blocker"
	)
	expect_eq(
		navigation.call("get_navigation_target"),
		destination,
		"the destination outlives the enemy that was blocking it"
	)


## §21: a destination the terrain itself walls off stops the walk safely instead of
## leaving the indicator on, chasing an unrelated enemy, or waiting forever.
func test_a_terrain_walled_destination_stops_the_walk_safely() -> void:
	await _mount_game()
	var player := _player()
	var navigation := _navigation()
	var hud := _hud()
	var enemies: Array = _living_enemies()
	expect(not enemies.is_empty(), "the stage spawned a living enemy")
	if enemies.is_empty():
		return

	var geometry: Dictionary = _blocked_destination()
	expect(not geometry.is_empty(), "the arena has a cell with exactly two ways in")
	if geometry.is_empty():
		return
	var destination: Vector2i = geometry["destination"]
	var blockers: Array = geometry["blockers"]
	var hero_cell: Vector2i = geometry["hero"]

	# BOTH ways in are the grid's own static obstacles, so no actor can be blamed for
	# the missing route — while an enemy stands within the hero's own attack range,
	# ready to be hit by anybody who mistakes it for the reason.
	var blocked_cells: Array = _grid().get("blocked_cells")
	for blocker in blockers:
		blocked_cells.append(blocker)
	expect(bool(player.call("place_at", hero_cell)), "the hero can stand away from the destination")
	var bait: Vector2i = Vector2i(-1, -1)
	for direction in DIRECTIONS:
		var candidate: Vector2i = hero_cell + direction
		if candidate != destination and _free_cell(candidate):
			bait = candidate
			break
	expect(bait != Vector2i(-1, -1), "a free cell beside the hero exists")
	if bait == Vector2i(-1, -1):
		return
	_place_enemy_at(enemies[0], bait)
	expect_eq(_path_steps(_cell_of(player), destination), 0, "no route to the destination exists")
	var bait_hp_before: int = int(enemies[0].get("enemy_runtime").get("current_hp"))

	_click_cell(destination)
	await flush_frames(1)

	expect(not bool(navigation.call("is_navigating")), "a destination with no route stops the walk")
	expect_eq(
		navigation.call("get_navigation_target"),
		Vector2i(-1, -1),
		"a stopped navigation clears its destination"
	)
	expect(not bool(hud.call("is_navigating")), "the AUTO NAVIGATING indicator is hidden again")
	expect_contains(
		str(_grid_test.get("_last_move_text")),
		"no route",
		"the combat host reports why the walk stopped"
	)
	expect_eq(
		int(enemies[0].get("enemy_runtime").get("current_hp")),
		bait_hp_before,
		"a walk with no route never attacks an unrelated enemy in reach"
	)


## §19 / §20: a tap on the hero's own cell is the manual stop — it cancels the walk and
## re-selects the hero, and the hero does not take another step afterwards.
func test_clicking_the_hero_cell_cancels_the_walk() -> void:
	await _mount_game()
	var player := _player()
	var navigation := _navigation()
	var hud := _hud()
	_park_enemies_away_from(_cell_of(player))
	var start: Vector2i = _cell_of(player)
	var target: Vector2i = _far_destination(start, 6)
	expect(target != Vector2i(-1, -1), "the arena has a free cell at least six steps away")
	if target == Vector2i(-1, -1):
		return

	_click_cell(target)
	expect(bool(navigation.call("is_navigating")), "the far click arms a destination")
	if not bool(navigation.call("is_navigating")):
		return

	var stopped_at: Vector2i = _cell_of(player)
	_click_cell(stopped_at)
	await flush_frames(4)

	expect(not bool(navigation.call("is_navigating")), "a tap on the hero's cell cancels the walk")
	expect_eq(
		navigation.call("get_navigation_target"),
		Vector2i(-1, -1),
		"a cancelled navigation clears its destination"
	)
	expect(not bool(hud.call("is_navigating")), "the AUTO NAVIGATING indicator is hidden again")
	expect_eq(_cell_of(player), stopped_at, "the hero does not walk on after the cancel")
	expect(bool(player.get("is_selected")), "the hero stays selected after the cancel")


## §12: AUTO is an independent system. A navigation click is walked by navigation, not
## by AUTO, and AUTO keeps its state — it only holds its own decision for the walk and
## takes the turn back afterwards.
func test_navigation_walks_the_clicked_cell_while_auto_stays_on() -> void:
	await _mount_game()
	var player := _player()
	var navigation := _navigation()
	var auto := _auto()
	_park_enemies_away_from(_cell_of(player))
	auto.call("set_auto_enabled", true)
	expect(bool(auto.call("is_auto_enabled")), "AUTO is on before the click")

	var start: Vector2i = _cell_of(player)
	# Beyond the default three movement points, so the walk really is a navigation and
	# not the ordinary in-range click-walk.
	var target: Vector2i = _far_destination(start, 4)
	expect(target != Vector2i(-1, -1), "the arena has a free cell beyond the movement range")
	if target == Vector2i(-1, -1):
		auto.call("set_auto_enabled", false)
		return

	_click_cell(target)
	expect(bool(navigation.call("is_navigating")), "the click arms a navigation even with AUTO on")
	expect(bool(auto.call("is_auto_enabled")), "starting a navigation does not disable AUTO")
	expect(bool(auto.call("is_navigation_held")), "AUTO holds its own decision for the walk")

	var guard: int = 0
	while bool(navigation.call("is_navigating")) and guard < 240:
		guard += 1
		await flush_frames(1)

	expect_eq(_cell_of(player), target, "navigation — not AUTO — walks the clicked cell")
	expect(bool(auto.call("is_auto_enabled")), "AUTO is still on when the walk ends")
	expect(not bool(auto.call("is_navigation_held")), "AUTO takes its turn back when the walk ends")
	auto.call("set_auto_enabled", false)
