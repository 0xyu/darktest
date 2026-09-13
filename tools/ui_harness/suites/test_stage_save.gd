extends "res://tools/ui_harness/ui_harness_suite.gd"

## Phase 8 headless suite: the player-side progress save, end to end, in the REAL
## game scene.
##
## What is under test
## -----------------
## The scene mounts, loads the player's saved stage progress, boots on the saved
## stage, and writes every progress change back to disk on its own (autosave) — no
## gameplay path has to remember to save. A new game is simply the case where no
## save file exists yet.
##
## The rules the plan sets for a load are all asserted here:
##   * the position is ONE number and is resumed as it was, including a position
##     past every authored area (the endless tail), which is never pulled back
##     into a range
##   * the unlock ceiling is restored too, otherwise the map's unlocked stages are
##     lost on load
##   * completed stages and consumed one-shot content are restored together, so the
##     player can never come back to a state they never had
##   * a damaged or future-format save never blocks booting: a new game starts
##     instead of a half-restored one
##
## The save path is redirected to the harness scratch file by the base suite (see
## ui_harness_suite.gd), so these tests never touch a real player save in user://.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")
const AreaViewScript := preload("res://scripts/ui/area_view.gd")
const FixtureScript := preload("res://tests/fixtures/ui_fixture.gd")
const SubHeroInstanceScript := preload("res://scripts/sub_hero/sub_hero_instance.gd")
## StageProgressSaveScript and HARNESS_SAVE_PATH are inherited from the base suite,
## which owns the redirect that keeps these tests off the player's real save.

var _grid_test: Node
var _main_instance: Node


func suite_name() -> String:
	return "test_stage_save"


# --- Fixtures ------------------------------------------------------------

func _mount_game() -> void:
	_main_instance = MAIN_SCENE.instantiate()
	_tree.root.add_child(_main_instance)
	track_node(_main_instance)
	_grid_test = _main_instance.find_child("grid_combat", true, false)
	# Let stage generation, the restored content, turn start, and HUD refresh settle.
	await flush_frames(6)


## Tears the running scene down so the NEXT mount boots from the save file, which
## is exactly the "quit the game and come back" path this suite has to prove.
func _unmount_game() -> void:
	if _main_instance != null and is_instance_valid(_main_instance):
		_main_instance.queue_free()
	_main_instance = null
	_grid_test = null
	await flush_frames(3)


func _stage_number() -> int:
	var manager: Node = _grid_test.find_child("StageManager")
	var state: Resource = manager.get("stage_state") as Resource if manager != null else null
	return int(state.get("stage_number")) if state != null else -1


func _progress() -> Resource:
	return _grid_test.call("get_stage_progress") if _grid_test != null else null


func _content() -> Node:
	return _grid_test.find_child("StageContentController", true, false)


func _player() -> Node:
	return _grid_test.find_child("Player", true, false)


func _grid() -> Node:
	return _grid_test.find_child("Grid", true, false)


func _status_text() -> String:
	return str(_grid_test.get("_last_move_text")) if _grid_test != null else ""


func _combat_view() -> Node:
	var hud: Node = _grid_test.find_child("MobileCombatHUD", true, false)
	return hud.get_node("%CombatView") if hud != null else null


func _town_view() -> Node:
	var hud: Node = _grid_test.find_child("MobileCombatHUD", true, false)
	return hud.get_node("%TownView") if hud != null else null


## Walks the hero onto `cell` for real, so the walk-on content trigger fires.
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


func _cell_of(content_id: StringName) -> Vector2i:
	for cell in _content().call("get_content_cells"):
		if _content().call("get_content_id_at", cell) == content_id:
			return cell
	return Vector2i(-1, -1)


func _find_living_enemy() -> Node:
	var manager: Node = _grid_test.find_child("StageManager")
	for enemy in manager.call("get_spawned_enemies"):
		if enemy != null and is_instance_valid(enemy) and not bool(enemy.call("is_defeated")):
			return enemy
	return null


func _defeat_all_enemies() -> void:
	var guard := 0
	while guard < 80:
		var enemy := _find_living_enemy()
		if enemy == null:
			break
		enemy.call("handle_defeat")
		guard += 1
		await flush_frames(1)


## A save file as a previous session would have left it.
func _write_progress_save(position: int, ceiling: int, completed: Array = [], consumed: Array = []) -> void:
	var save = StageProgressSaveScript.new(null, null, HARNESS_SAVE_PATH)
	save.progress.current_stage_number = position
	save.progress.mark_reached(ceiling)
	for stage_id in completed:
		save.progress.completed_stages[stage_id] = true
	for key in consumed:
		save.content_state.consumed[key] = true
	save.save()


func _write_raw_save(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(HARNESS_SAVE_PATH.get_base_dir())
	var file := FileAccess.open(HARNESS_SAVE_PATH, FileAccess.WRITE)
	expect(file != null, "the scratch save file can be written")
	if file == null:
		return
	file.store_string(text)
	file.close()


## The payload the running game has written to disk (empty when there is no file
## yet, or when the file is damaged).
func _saved_payload() -> Dictionary:
	if not FileAccess.file_exists(HARNESS_SAVE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(HARNESS_SAVE_PATH)
	if text.strip_edges().is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	return json.data as Dictionary


func _saved_list(key: String) -> Array:
	var value: Variant = _saved_payload().get(key, [])
	return value as Array if value is Array else []


# --- Tests ---------------------------------------------------------------

func test_a_new_game_boots_on_stage_one_and_saves_once_progress_happens() -> void:
	await _mount_game()
	expect(_grid_test.call("get_stage_save") != null, "the scene owns a progress save")
	expect(_stage_number() == 1, "a new game boots on stage 1")
	expect(int(_progress().get("current_stage_number")) == 1, "a new game's position is stage 1")
	expect(not _status_text().contains("SAVE RESTORED"), "a new game does not claim to have restored anything")
	# Autosave fires on a REAL change of progress, and booting a new game changes
	# nothing: a session that has played nothing has nothing to store yet.
	expect(
		not StageProgressSaveScript.save_exists_at(HARNESS_SAVE_PATH),
		"a new untouched game has written no save yet"
	)

	# Clearing the boot stage is the first real progress, and it is written on its
	# own — no gameplay path asked for a save.
	await _defeat_all_enemies()
	expect(StageProgressSaveScript.save_exists_at(HARNESS_SAVE_PATH), "recording progress created the save file")
	var payload: Dictionary = _saved_payload()
	expect(int(payload.get("current_stage_number", -1)) == 1, "the saved position is where the player actually stands")
	expect(int(payload.get("version", -1)) == StageProgressSaveScript.FORMAT_VERSION, "the file carries the format version")
	expect(_saved_list("completed_stages").has("forest_001"), "the recorded clear is on disk")
	expect(_saved_list("consumed_content").is_empty(), "nothing was consumed on this stage")


func test_playing_a_stage_writes_position_and_completion_without_asking() -> void:
	await _mount_game()
	expect(bool(_grid_test.call("enter_area_stage", 6)), "entering authored stage 06 should succeed")
	await flush_frames(3)
	expect(int(_saved_payload().get("current_stage_number", -1)) == 6, "the entry wrote the new position to disk")

	await _defeat_all_enemies()
	expect(bool(_progress().call("is_stage_completed", 6)), "clearing the stage records the completion in progress")
	expect(_saved_list("completed_stages").has("forest_006"), "the recorded clear is on disk under its canonical id")
	expect(int(_saved_payload().get("highest_stage_reached", -1)) >= 6, "the unlock ceiling on disk keeps up with the position")


func test_boot_resumes_the_saved_stage_and_its_progress() -> void:
	await _mount_game()
	expect(bool(_grid_test.call("enter_area_stage", 6)), "entering authored stage 06 should succeed")
	await flush_frames(3)
	await _defeat_all_enemies()
	expect(bool(_progress().call("is_stage_completed", 6)), "the stage is cleared before the session ends")
	await _unmount_game()

	# A second session: nothing is carried over in memory, only the save file.
	await _mount_game()
	expect(_stage_number() == 6, "the restored session runs the battle of the saved stage")
	expect(int(_progress().get("current_stage_number")) == 6, "the restored position is the saved stage")
	expect(bool(_progress().call("is_stage_completed", 6)), "the restored session knows the stage was cleared")
	expect(bool(_progress().call("is_stage_unlocked", 7)), "the restored completion still unlocks the next stage")
	expect(_status_text().contains("SAVE RESTORED"), "the restored session says so instead of silently starting mid-path")


func test_a_restored_unlock_ceiling_keeps_the_map_open() -> void:
	# The plan's explicit warning: a save that forgot highest_stage_reached would
	# come back with the map's unlocked stages lost. Nothing here is completed, so
	# stage 8 is open ONLY because the restored ceiling reaches it.
	_write_progress_save(5, 8)
	await _mount_game()
	expect(int(_progress().get("highest_stage_reached")) == 8, "the unlock ceiling is restored")
	expect(bool(_grid_test.call("open_world_map")), "the world map opens")
	await flush_frames(2)
	var map: Node = _grid_test.find_child("MobileCombatHUD", true, false).get_node("%WorldMapView")
	var forest: Node = map.call("get_area_view", &"forest")
	expect(forest != null, "the forest area view is built")
	var inside_ceiling: Button = forest.call("get_stage_node", 8) as Button
	expect(inside_ceiling != null and not bool(inside_ceiling.disabled), "a stage inside the restored ceiling is enterable")
	var past_ceiling: Button = forest.call("get_stage_node", 9) as Button
	expect(past_ceiling != null and bool(past_ceiling.disabled), "a stage past the ceiling is still locked")
	var position_node: Button = forest.call("get_stage_node", 5) as Button
	expect(
		position_node != null and int(position_node.get_meta("stage_state")) == AreaViewScript.NodeState.CURRENT,
		"the map marks the restored position as the current stage"
	)


func test_a_saved_position_past_the_authored_path_resumes_as_endless() -> void:
	# Past the last authored area the position is legal and must be resumed as it
	# is: pulling it back into a range would undo the player's progress.
	_write_progress_save(57, 57)
	await _mount_game()
	expect(_stage_number() == 57, "the endless position resumes as a battle on that stage")
	expect(int(_progress().get("current_stage_number")) == 57, "the restored position is not pulled back into an area")
	expect(String(_progress().call("get_current_area_id")) == "", "that position derives no area (the endless tail)")
	expect(_find_living_enemy() != null, "the resumed endless stage actually spawned its battle")


func test_a_saved_visit_stage_resumes_as_a_playable_battle() -> void:
	# A save made while standing on a TOWN stage resumes the battle at that stage
	# number rather than re-opening the town: the visit is already recorded as
	# completed, and a boot that started no stage would leave the arena with no
	# enemies and no way to move on.
	_write_progress_save(8, 8, ["forest_008"])
	await _mount_game()
	expect(_stage_number() == 8, "the saved town position resumes as a battle on that stage")
	expect(_town_view() != null and not bool(_town_view().get("visible")), "the town view is not re-opened on boot")
	expect(_combat_view() != null and bool(_combat_view().get("visible")), "the restored session shows a playable combat view")
	expect(_find_living_enemy() != null, "the resumed stage has a battle to play")
	expect(bool(_progress().call("is_stage_completed", 8)), "the recorded town visit is still recorded")


func test_consumed_content_is_restored_with_the_progress() -> void:
	await _mount_game()
	expect(bool(_grid_test.call("enter_area_stage", 6)), "entering authored stage 06 should succeed")
	await flush_frames(3)
	var chest_cell: Vector2i = _cell_of(&"cache")
	expect(chest_cell != Vector2i(-1, -1), "the one-shot chest exists on the first visit")
	expect(_step_onto(chest_cell), "the hero can walk onto the chest cell")
	await flush_frames(3)
	expect(_saved_list("consumed_content").has("forest_006:cache"), "the consumed chest is on disk")
	await _unmount_game()

	# Second session: the consumed chest must stay gone, the repeatable pool must
	# return — the "half restored" state this save exists to prevent.
	await _mount_game()
	var state: Resource = _content().call("get_state")
	expect(bool(state.call("is_consumed", "forest_006", &"cache")), "the consumed chest is still consumed after a reload")
	expect(_cell_of(&"cache") == Vector2i(-1, -1), "the consumed chest does not respawn in the restored session")
	expect(_cell_of(&"spring") != Vector2i(-1, -1), "the repeatable content does respawn in the restored session")
	expect_eq(_content().call("get_content_count"), 1, "only the repeatable entry is restored")


func test_a_damaged_save_boots_a_new_game_instead_of_a_half_restored_one() -> void:
	_write_raw_save("{ this is not json")
	await _mount_game()
	expect(_stage_number() == 1, "a damaged save boots a new game at stage 1")
	expect(int(_progress().get("current_stage_number")) == 1, "a damaged save leaves the fresh position alone")
	expect(not _status_text().contains("SAVE RESTORED"), "a refused save is not reported as restored")
	await _unmount_game()

	# A save written by a NEWER build is refused rather than half-read.
	_write_raw_save("{\"version\": %d, \"current_stage_number\": 6}" % (StageProgressSaveScript.FORMAT_VERSION + 1))
	await _mount_game()
	expect(_stage_number() == 1, "a future-format save boots a new game at stage 1")
	expect(int(_progress().get("current_stage_number")) == 1, "a future-format save leaves the fresh position alone")


## The player's belongings are part of the same save as the map progress: quit the
## game and come back, and the equipped gear, the bag, the warehouse and the Sub
## Heroes are what they were — without any gameplay path calling save().
func test_items_and_sub_heroes_survive_a_restart() -> void:
	await _mount_game()
	var player: Node = _player()
	# One item in each of the three places an owned item can live.
	var weapon: EquipmentInstance = FixtureScript.create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, 12, &"every_3rd_attack")
	# The level-1 numbers, before any gear is worn: the round trip below has to come
	# back to exactly these.
	var unequipped_attack: int = int(player.player_stats.attack)
	expect(bool(player.call("add_equipment", weapon)), "the hero takes the weapon")
	expect(bool(player.call("equip_item", weapon)), "the weapon is equipped")
	expect(int(player.player_stats.attack) > unequipped_attack, "equipping the weapon raises attack")
	var ring: EquipmentInstance = FixtureScript.create_equipment(EquipmentRarity.EPIC, EquipmentSlot.RING, 22)
	expect(bool(player.call("add_equipment", ring)), "the ring enters the bag")
	var boots: EquipmentInstance = FixtureScript.create_equipment(EquipmentRarity.COMMON, EquipmentSlot.BOOTS, 4)
	expect(bool(player.call("add_to_storage", boots)), "the boots go to the warehouse")
	var hero := SubHeroInstanceScript.new(&"skeleton_archer", 3)
	hero.duplicate_count = 2
	expect(bool(player.call("add_sub_hero", hero).get("is_new", false)), "the Sub Hero is summoned")
	expect(bool(player.call("assign_sub_hero_slot", 1, &"skeleton_archer")), "the Sub Hero is assigned to a slot")
	await flush_frames(2)

	# Autosave: everything above persisted on its own, and the file holds the items
	# and the Sub Heroes — not just the map progress.
	var payload: Dictionary = _saved_payload()
	expect((payload.get("inventory", []) as Array).size() == 2, "the equipped weapon and the bagged ring are on disk")
	expect((payload.get("storage", []) as Array).size() == 1, "the stored boots are on disk")
	expect(((payload.get("sub_heroes", {}) as Dictionary).get("owned_sub_heroes", []) as Array).size() == 1, "the Sub Hero is on disk")
	var equipped_attack_bonus: int = int(player.player_stats.attack)
	await _unmount_game()

	# A second session: nothing is carried over in memory, only the save file.
	await _mount_game()
	var restored_player: Node = _player()
	var restored_weapon: EquipmentInstance = restored_player.call("get_equipped_item", EquipmentSlot.WEAPON)
	expect(restored_weapon != null, "the equipped weapon is restored")
	if restored_weapon != null:
		expect(restored_weapon.instance_id == weapon.instance_id, "the restored weapon is the same item")
		expect(restored_weapon.definition.unique_effect_id == &"every_3rd_attack", "its unique effect survived the restart")
		expect(restored_weapon.affixes.size() == weapon.affixes.size(), "its rolled affixes survived the restart")
	expect(int(restored_player.player_stats.attack) == equipped_attack_bonus, "the equipped item's stats are applied in the restored session")
	# A round trip: taking the weapon off and putting it back on returns the SAME
	# numbers, because the stats are rebuilt from the level and the gear instead of
	# being adjusted by a remembered delta.
	expect(
		restored_player.call("unequip_item", EquipmentSlot.WEAPON) == restored_weapon,
		"the restored weapon comes off"
	)
	expect_eq(int(restored_player.player_stats.attack), unequipped_attack, "removing it returns the numbers the level alone is worth")
	expect(bool(restored_player.call("equip_item", restored_weapon)), "the weapon goes back on")
	expect_eq(int(restored_player.player_stats.attack), equipped_attack_bonus, "re-equipping it restores exactly the same attack")
	expect(restored_player.call("get_inventory").has_item(ring), "the bagged ring is restored")
	expect(not ring.is_equipped, "a bagged item does not come back equipped")
	expect(restored_player.call("get_storage").has_item(boots), "the warehouse contents are restored")

	var restored_hero: SubHeroInstance = restored_player.call("get_sub_hero_progression").get_owned_instance(&"skeleton_archer")
	expect(restored_hero != null, "the Sub Hero is restored as owned")
	if restored_hero != null:
		expect(restored_hero.level == 3, "the Sub Hero keeps its level")
		expect(restored_hero.duplicate_count == 2, "the Sub Hero keeps its duplicate progress")
	expect(
		restored_player.call("get_sub_hero_progression").active_slot_ids[1] == &"skeleton_archer",
		"the Sub Hero is restored into its slot"
	)
	# And it is a LIVE combatant, not just a line in the file: the scene spawns the
	# restored active slots when it boots.
	var restored_manager: Node = _grid_test.find_child("SubHeroCombatManager", true, false)
	expect_eq(
		(restored_manager.get("_active_states") as Array).size(),
		1,
		"the restored Sub Hero fights in the resumed session"
	)


## The character's own numbers are part of the same save: quit the game and come
## back, and the level, the EXP inside it, the purse, the skill points and the
## learned skills are what they were. The save ADOPTS the hero's own progression
## object, so the identity check below is also what keeps the skill panel's binding
## (made while the scene was still coming up) pointed at the live object.
func test_character_progression_survives_a_restart() -> void:
	await _mount_game()
	var save: StageProgressSave = _grid_test.call("get_stage_save") as StageProgressSave
	expect(save != null, "the scene owns a progress save")
	var player: Node = _player()
	var progression: PlayerProgression = player.get("player_progression") as PlayerProgression
	expect(progression != null, "the hero has a progression object")
	expect(save.player_progression == progression, "the save adopts the hero's own progression, never a second copy")

	# The ordinary progression paths: an EXP award that levels the hero, the skill
	# point it grants, a skill learned with it, and an awarded coin.
	var experience_system: Node = _grid_test.find_child("ExperienceSystem", true, false)
	expect(experience_system != null, "the scene owns the experience system")
	expect_eq(int(experience_system.call("grant_experience", 150)), 1, "the awarded EXP levels the hero once")
	expect(bool(player.call("upgrade_skill", SkillCatalog.WHIRLWIND)), "the level-up's skill point learns a skill")
	expect(progression.add_gold(275) == 275, "the purse takes the awarded gold")
	await flush_frames(2)

	# The level is worth numbers, and those numbers are NOT stored: the hero rebuilds
	# them from the level and the gear it owns, so a session that comes back has to
	# fight with what its level is worth.
	var live_max_hp: int = int(player.player_stats.max_hp)
	var live_attack: int = int(player.player_stats.attack)
	var live_defense: int = int(player.player_stats.defense)
	expect(live_max_hp > 100, "a level-up raises max HP above the level-1 base (got %d)" % live_max_hp)

	# Autosave: all of it persisted on its own — no gameplay path and no panel asked
	# for a save.
	var payload: Dictionary = _saved_payload()
	expect_eq(int(payload.get("level", -1)), 2, "the level is on disk")
	expect_eq(int(payload.get("experience", -1)), 50, "the EXP left inside the level is on disk")
	expect_eq(int(payload.get("gold", -1)), 275, "the purse is on disk")
	expect_eq(int(payload.get("skill_points", -1)), 0, "the spent skill point is on disk")
	expect_eq(
		int((payload.get("skill_levels", {}) as Dictionary).get("whirlwind", 0)),
		1,
		"the learned skill is on disk"
	)
	expect_eq(int(payload.get("version", -1)), StageProgressSaveScript.FORMAT_VERSION, "the file carries the format version that added them")
	await _unmount_game()

	# A second session: nothing is carried over in memory, only the save file.
	await _mount_game()
	var restored: PlayerProgression = _player().get("player_progression") as PlayerProgression
	var restored_player: Node = _player()
	expect_eq(int(restored_player.player_stats.max_hp), live_max_hp, "the restored session rebuilds max HP from its level")
	expect_eq(int(restored_player.player_stats.attack), live_attack, "the restored session rebuilds attack from its level")
	expect_eq(int(restored_player.player_stats.defense), live_defense, "the restored session rebuilds defense from its level")
	expect_eq(
		int(restored_player.player_stats.current_hp),
		live_max_hp,
		"a restored session boots at full HP of the restored maximum"
	)
	expect_eq(restored.level, 2, "the restored session keeps the level")
	expect_eq(restored.experience, 50, "the restored session keeps the EXP inside the level")
	expect_eq(restored.gold, 275, "the restored session keeps the purse")
	expect_eq(restored.get_skill_points(), 0, "the restored session keeps the point as spent")
	expect_eq(restored.get_skill_level(SkillCatalog.WHIRLWIND), 1, "the restored session keeps the learned skill")
	expect_eq(
		restored.get_skill_level(SkillCatalog.ARCANE_BOLT),
		0,
		"a skill that was never learned is not restored as learned"
	)
