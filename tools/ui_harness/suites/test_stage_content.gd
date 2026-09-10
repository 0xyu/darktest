extends "res://tools/ui_harness/ui_harness_suite.gd"

## Authored stage CONTENT LAYER: runtime behaviour.
##
## The model under test: a stage is a normal stage first; authored content is
## layered on top of it and appears whenever the stage starts, however the player
## reached it. Content resolves when the hero STEPS onto its cell — the same
## trigger for a manual move and for an AUTO move — and one-shot content is
## consumed for good while repeatable content comes back on later visits.
##
## Forest 06 is the shipped example: a one-shot "Hidden Cache" chest and a
## repeatable "Forest Spring" healing pool.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")

var _grid_test: Node


func suite_name() -> String:
	return "test_stage_content"


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_grid_test = instance.find_child("grid_combat", true, false)
	# Let stage generation, turn start, and HUD refresh settle.
	await flush_frames(6)


func _content() -> Node:
	return _grid_test.find_child("StageContentController", true, false)


func _player() -> Node:
	return _grid_test.find_child("Player", true, false)


func _grid() -> Node:
	return _grid_test.find_child("Grid", true, false)


func _stage_number() -> int:
	var manager: Node = _grid_test.find_child("StageManager")
	var state: Resource = manager.get("stage_state") as Resource if manager != null else null
	return int(state.get("stage_number")) if state != null else -1


func _gold() -> int:
	var progression: Resource = _player().get("player_progression") as Resource
	return int(progression.get("gold")) if progression != null else 0


func _cell_of(content_id: StringName) -> Vector2i:
	for cell in _content().call("get_content_cells"):
		if _content().call("get_content_id_at", cell) == content_id:
			return cell
	return Vector2i(-1, -1)


## Walks the hero onto `cell` for real: it finds a free neighbour, teleports there
## and then MOVES onto the cell, so the walk-on trigger (the player "moved" signal)
## is what resolves the content — not a direct call into the controller.
func _step_onto(cell: Vector2i) -> bool:
	var player: Node = _player()
	var grid: Node = _grid()
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbour: Vector2i = cell + direction
		if not bool(grid.call("is_walkable", neighbour)) or bool(grid.call("is_occupied", neighbour)):
			continue
		if not bool(player.call("place_at", neighbour)):
			continue
		player.call("set_free_movement", true)
		if bool(player.call("try_move", -direction)):
			return true
	return false


# --- Tests ---------------------------------------------------------------

func test_authored_stage_spawns_its_content_on_a_normal_battle() -> void:
	await _mount_game()
	expect(bool(_grid_test.call("enter_area_stage", 6)), "entering authored forest 06 should succeed")
	await flush_frames(3)

	# The stage is still a normal battle: content is layered on top of the
	# gameplay and does not replace it.
	expect_eq(_stage_number(), 6, "forest 06 still starts its usual battle")
	expect_eq(_content().call("get_content_count"), 2, "forest 06 spawns both authored content entries")

	var cache_cell: Vector2i = _cell_of(&"cache")
	var spring_cell: Vector2i = _cell_of(&"spring")
	expect(cache_cell != Vector2i(-1, -1), "the chest is placed on a cell")
	expect(spring_cell != Vector2i(-1, -1), "the healing pool is placed on a cell")
	expect_ne(cache_cell, spring_cell, "the two entries are placed on different cells")


func test_plain_stages_spawn_no_content() -> void:
	await _mount_game()
	# Boot is global stage 1 of Forest, which authors no content: a plain stage.
	expect_eq(_content().call("get_content_count"), 0, "the boot stage carries no content")

	# Stage 02 is authored by nobody, so it is a plain normal stage.
	expect(bool(_grid_test.call("enter_area_stage", 2)), "entering stage 02 should succeed")
	await flush_frames(3)
	expect_eq(_stage_number(), 2, "stage 02 started its battle")
	expect_eq(_content().call("get_content_count"), 0, "an un-authored stage carries no content")


func test_walking_onto_the_chest_grants_gold_consumes_it_and_removes_it() -> void:
	await _mount_game()
	expect(bool(_grid_test.call("enter_area_stage", 6)), "entering authored forest 06 should succeed")
	await flush_frames(3)

	var state: Resource = _content().call("get_state")
	expect(not bool(state.call("is_consumed", "forest_006", &"cache")), "the chest starts unconsumed")
	var gold_before: int = _gold()

	var cache_cell: Vector2i = _cell_of(&"cache")
	expect(cache_cell != Vector2i(-1, -1), "the chest exists to walk onto")
	expect(_step_onto(cache_cell), "the hero can walk onto the chest cell")
	await flush_frames(3)

	expect(_gold() > gold_before, "opening the chest granted gold (%d -> %d)" % [gold_before, _gold()])
	expect(bool(state.call("is_consumed", "forest_006", &"cache")), "the opened chest is recorded as consumed")
	expect(not bool(_content().call("has_content_at", cache_cell)), "the opened chest is removed from the grid")
	expect_eq(_content().call("get_content_count"), 1, "only the repeatable spring is left")


func test_one_shot_content_stays_gone_but_repeatable_content_returns() -> void:
	await _mount_game()
	expect(bool(_grid_test.call("enter_area_stage", 6)), "entering authored forest 06 should succeed")
	await flush_frames(3)

	# Consume the chest during this visit.
	var cache_cell: Vector2i = _cell_of(&"cache")
	expect(_step_onto(cache_cell), "the hero can walk onto the chest cell")
	await flush_frames(3)
	expect_eq(_content().call("get_content_count"), 1, "the chest is gone after being opened")

	# Re-enter the same authored stage: the one-shot chest must not come back, the
	# repeatable pool must. This is what "the stage is a normal stage again" means.
	expect(bool(_grid_test.call("enter_area_stage", 6)), "re-entering authored forest 06 should succeed")
	await flush_frames(3)
	expect_eq(_content().call("get_content_count"), 1, "only the repeatable entry respawns")
	expect(_cell_of(&"cache") == Vector2i(-1, -1), "the consumed chest does not respawn")
	expect_ne(_cell_of(&"spring"), Vector2i(-1, -1), "the repeatable spring does respawn")

	var state: Resource = _content().call("get_state")
	expect_eq(state.call("get_consumed_count"), 1, "exactly one content key is recorded in total")


func test_healing_pool_restores_hp_once_per_visit() -> void:
	await _mount_game()
	expect(bool(_grid_test.call("enter_area_stage", 6)), "entering authored forest 06 should succeed")
	await flush_frames(3)

	var stats: Resource = _player().get("player_stats")
	expect(stats != null, "the hero has stats")
	if stats == null:
		return
	stats.set("current_hp", 1)
	var max_hp: int = int(stats.get("max_hp"))

	var spring_cell: Vector2i = _cell_of(&"spring")
	expect(spring_cell != Vector2i(-1, -1), "the healing pool exists to walk onto")
	expect(_step_onto(spring_cell), "the hero can walk onto the healing pool cell")
	await flush_frames(3)

	var healed_hp: int = int(stats.get("current_hp"))
	expect(healed_hp > 1, "the pool restored HP (1 -> %d of %d)" % [healed_hp, max_hp])

	# Stepping off and back on must not farm the pool within one visit.
	stats.set("current_hp", 1)
	expect(_step_onto(spring_cell), "the hero can step back onto the pool cell")
	await flush_frames(3)
	expect_eq(int(stats.get("current_hp")), 1, "a repeatable entry resolves at most once per visit")
