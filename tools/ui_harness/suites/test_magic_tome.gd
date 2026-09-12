extends "res://tools/ui_harness/ui_harness_suite.gd"

## §16 Magic Tome — the HUD-to-combat wiring.
##
## Mounts the REAL game scene and presses the MAGIC row the way the player does, so
## the suite covers the whole chain (CombatActions -> MobileCombatHUD -> grid_combat ->
## MagicTome -> CombatSystem) and pins the two properties that make the tome worth
## having during AUTO:
##   * a cast costs neither the player's action nor the turn;
##   * the row stays pressable when the player's own input is closed (the enemy phase
##     and AUTO close it, and a spell is still legal there).
##
## The cooldown RULE (four Player Turns, one tick per new Player Turn) is asserted
## deterministically in res://tests/magic_tome_smoke_test.gd; here we assert that the
## armed cooldown reaches the button.

const MAIN_SCENE := preload("res://scenes/world/Main.tscn")
## The suite drives the enemy phase it needs instead of waiting for enemy AI, so the
## row checks must not sit through a whole turn: a handful of frames is enough for the
## HUD's per-frame refresh to publish the state.
const REFRESH_FRAMES := 3

var _grid_test: Node


func suite_name() -> String:
	return "test_magic_tome"


func _mount_game() -> void:
	var instance: Node = MAIN_SCENE.instantiate()
	_tree.root.add_child(instance)
	track_node(instance)
	_grid_test = instance.find_child("grid_combat", true, false)
	# Let stage generation, turn start and the first HUD layout settle.
	await flush_frames(6)


func _player() -> Node:
	return _grid_test.find_child("Player", true, false)


func _turn() -> Node:
	return _grid_test.find_child("TurnManager", true, false)


func _actions() -> Node:
	var hud: Node = _grid_test.find_child("MobileCombatHUD", true, false)
	return hud.find_child("CombatActions", true, false) if hud != null else null


func _magic_row() -> Node:
	var actions: Node = _actions()
	return actions.find_child("MagicRow", true, false) if actions != null else null


## The button for one spell. The row labels each button with the catalog's display
## name, so the lookup doubles as a check that the row really names its spells.
func _magic_button(skill_id: StringName) -> Button:
	var row: Node = _magic_row()
	if row == null:
		return null
	var display_name: String = MagicTomeCatalog.get_skill(skill_id).display_name
	for child in row.get_children():
		if child is Button and (child as Button).text.begins_with(display_name):
			return child as Button
	return null


func _spawned_enemies() -> Array:
	var manager: Node = _grid_test.find_child("StageManager", true, false)
	if manager == null:
		return []
	return manager.call("get_spawned_enemies") as Array


func _total_enemy_hp() -> int:
	var total: int = 0
	for enemy in _spawned_enemies():
		if enemy == null or not is_instance_valid(enemy):
			continue
		enemy.call("sync_runtime_state")
		var runtime: Variant = enemy.get("enemy_runtime")
		if runtime is EnemyRuntime:
			total += maxi(int((runtime as EnemyRuntime).current_hp), 0)
	return total


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


func test_the_magic_row_lists_one_button_per_tome_spell() -> void:
	await _mount_game()
	var actions: Node = _actions()
	expect(actions != null, "the combat HUD mounts its action cluster")
	var row: Node = _magic_row()
	expect(row != null, "the action cluster has a MAGIC row")
	if row == null:
		return
	expect_eq(row.get_child_count(), MagicTomeCatalog.get_all().size(), "one button per tome spell")
	for skill in MagicTomeCatalog.get_all():
		var button: Button = _magic_button(skill.skill_id)
		expect(button != null, "the row offers %s" % skill.display_name)
		if button != null:
			expect_contains(button.text, "READY", "%s starts ready" % skill.display_name)

	# The cluster grew by one row (MAGIC), so it must still fit the combat section it is
	# anchored to — otherwise the row would spill over the Sub Hero row below it.
	var section: Control = _grid_test.find_child("CombatSection", true, false)
	var summary: Control = _grid_test.find_child("EnemySummaryPanel", true, false)
	var cluster: Control = _actions()
	expect(
		cluster.get_global_rect().end.y <= section.get_global_rect().end.y + 1.0,
		"the action cluster fits inside the combat section"
	)
	expect(
		cluster.get_global_rect().position.y >= summary.get_global_rect().end.y - 1.0,
		"the MAGIC row does not overlap the enemy summary"
	)


func test_a_cast_costs_no_action_and_no_turn() -> void:
	await _mount_game()
	var turn_manager: Node = _turn()
	var button: Button = _magic_button(MagicTomeCatalog.MAGIC_MISSILE)
	expect(button != null and not button.disabled, "Magic Missile is pressable at the start of the fight")
	if button == null:
		return
	var phase_before: int = int(turn_manager.call("get_phase"))
	var action_before: bool = bool(turn_manager.get("turn_state").action_available)
	var hp_before: int = _total_enemy_hp()
	expect(hp_before > 0, "the stage spawned living enemies")

	button.emit_signal("pressed")
	await flush_frames(REFRESH_FRAMES)

	expect(_total_enemy_hp() < hp_before, "the press struck an enemy")
	expect_eq(int(turn_manager.call("get_phase")), phase_before, "the cast did not end the player's turn")
	expect_eq(
		bool(turn_manager.get("turn_state").action_available),
		action_before,
		"the cast did not spend the player's action"
	)


func test_the_armed_cooldown_reaches_the_button() -> void:
	await _mount_game()
	var tome: Node = _grid_test.find_child("MagicTome", true, false)
	var button: Button = _magic_button(MagicTomeCatalog.MAGIC_MISSILE)
	expect(tome != null, "the combat scene owns the tome")
	if tome == null or button == null:
		return

	button.emit_signal("pressed")
	await flush_frames(REFRESH_FRAMES)

	expect_eq(
		int(tome.call("get_cooldown", MagicTomeCatalog.MAGIC_MISSILE)),
		4,
		"the cast armed a four Player Turn cooldown"
	)
	expect(button.disabled, "a recharging spell is not pressable")
	expect_contains(button.text, "CD 4", "the button shows the remaining Player Turns")


## The contract that makes the tome useful in AUTO: attack, skills and potions all
## need the player's own input, and a spell does not. Closing the player's input (what
## the enemy phase does) must therefore leave the tome pressable.
func test_a_spell_stays_pressable_when_the_player_input_closes() -> void:
	await _mount_game()
	var player: Node = _player()
	var nova: Button = _magic_button(MagicTomeCatalog.ARCANE_NOVA)
	expect(nova != null and not nova.disabled, "Arcane Nova is pressable at the start of the fight")
	if nova == null:
		return

	player.call("end_player_turn")
	await flush_frames(REFRESH_FRAMES)

	expect(not bool(player.call("is_input_enabled")), "the player's own input is closed")
	expect(not nova.disabled, "the tome is still pressable with the player's input closed")
	expect(bool(_grid_test.call("can_use_magic", MagicTomeCatalog.ARCANE_NOVA)), "the host still offers the spell")
