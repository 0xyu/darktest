extends SceneTree

## Headless smoke test for the Magic Tome companion (docs/game-design.md §16).
##
## The design rests on four rules, and each is asserted here:
##   1. a spell needs no grid range — caster and target may be cells apart;
##   2. a cast spends no action and never advances the turn, so it is legal during
##      the enemy phase (and therefore during AUTO);
##   3. the cost is a cooldown in PLAYER TURNS: the cast arms it, and only a new
##      Player Turn ticks it down;
##   4. a spell is pure damage — the weapon riders (life steal, stun, equipment
##      attack effects) deliberately do not apply to it.

class MockActor:
	extends Node2D

	var player_stats: PlayerStats
	var enemy_stats: EnemyStats
	var enemy_runtime: EnemyRuntime
	var player_id: StringName = &""
	var enemy_id: StringName = &""
	var grid_position: Vector2i
	## When true the mock enemy sits on its turn instead of finishing it: that is how
	## this test parks combat in the ENEMY_TURN phase and casts from there.
	var hold_turn: bool = false

	func get_grid_position() -> Vector2i:
		return grid_position

	func take_turn(_player: Node, turn_manager: TurnManager) -> void:
		if hold_turn:
			return
		turn_manager.complete_enemy_turn(self)

	func clamp_current_hp() -> void:
		if enemy_stats != null:
			enemy_stats.clamp_current_hp()

	func handle_defeat() -> void:
		pass


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_tome_rules()
	await _test_magic_row_ui()

	if _failures.is_empty():
		print("Magic tome smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_tome_rules() -> void:
	var caster := MockActor.new()
	caster.player_id = &"player"
	caster.grid_position = Vector2i(0, 0)
	caster.player_stats = PlayerStats.new()
	caster.player_stats.attack = 50
	caster.player_stats.critical_chance = 0.0
	caster.player_stats.max_hp = 100
	caster.player_stats.current_hp = 50
	caster.player_stats.life_steal = 0.5
	var enemy := _make_enemy(&"tome_dummy", Vector2i(10, 6))
	root.add_child(caster)
	root.add_child(enemy)

	var combat := CombatSystem.new()
	root.add_child(combat)
	combat.set_player_actor(caster)
	combat.set_combat_targets([enemy])
	var turn_manager := TurnManager.new()
	root.add_child(turn_manager)
	combat.attach_turn_manager(turn_manager)
	var tome := MagicTome.new()
	root.add_child(tome)
	tome.attach(combat, turn_manager, caster)

	turn_manager.start_combat(caster, [enemy])

	_expect(tome.is_ready(MagicTomeCatalog.MAGIC_MISSILE), "the tome starts ready")
	_expect_eq(tome.get_cooldown(MagicTomeCatalog.MAGIC_MISSILE), 0, "a fresh tome has no cooldown")
	_expect(not combat.can_attack(caster, enemy), "the dummy sits outside weapon range")

	# (1) A spell reaches an enemy that no weapon attack could touch.
	var hp_before: int = enemy.enemy_stats.current_hp
	_expect(tome.cast(MagicTomeCatalog.MAGIC_MISSILE, enemy), "a spell strikes a distant enemy")
	_expect(enemy.enemy_stats.current_hp < hp_before, "the spell dealt damage")

	# (2) ...and it cost neither the action nor the turn.
	_expect(turn_manager.is_player_turn(), "the caster keeps the turn")
	_expect(turn_manager.is_action_available(caster), "the action is still available after a cast")

	# (3) The cooldown is armed in Player Turns.
	_expect_eq(tome.get_cooldown(MagicTomeCatalog.MAGIC_MISSILE), 4, "the cast arms a four-turn cooldown")
	_expect(not tome.can_cast(MagicTomeCatalog.MAGIC_MISSILE), "a recharging spell is not offered")
	_expect(not tome.cast(MagicTomeCatalog.MAGIC_MISSILE, enemy), "a recast is refused while recharging")

	# (4) The enemy phase is the point of the system: casting must work there too.
	enemy.hold_turn = true
	turn_manager.complete_player_turn()
	_expect(turn_manager.is_enemy_turn(), "combat is in the enemy phase")
	_expect(tome.cast(MagicTomeCatalog.ARCANE_NOVA), "an area spell can be cast during the enemy turn")
	_expect(turn_manager.is_enemy_turn(), "casting never advanced the enemy turn")
	_expect_eq(tome.get_cooldown(MagicTomeCatalog.ARCANE_NOVA), 6, "the area spell arms its own cooldown")
	enemy.hold_turn = false

	# (5) A spell is pure damage: no weapon rider rides along with it.
	var caster_hp: int = caster.player_stats.current_hp
	var spell_result: DamageResult = combat.resolve_magic_strike(caster, enemy, 1.0, MagicTomeCatalog.MAGIC_MISSILE)
	_expect_eq(spell_result.final_damage, 40, "spell damage is attack minus defense")
	_expect_eq(spell_result.lifesteal_heal, 0, "a spell steals no life")
	_expect_eq(caster.player_stats.current_hp, caster_hp, "a spell heals nothing")

	# (6) ...while a weapon hit on the same target still does, so the assertion above
	# proves the spell path and not a broken life-steal affix.
	enemy.grid_position = Vector2i(1, 0)
	turn_manager.complete_enemy_turn(enemy)
	_expect(turn_manager.is_player_turn(), "the enemy turn handed the turn back")
	var weapon_result: DamageResult = combat.resolve_attack(caster, enemy)
	_expect(weapon_result.lifesteal_heal > 0, "a weapon hit still steals life")

	# (7) One tick per new Player Turn, exactly as the design states.
	_expect_eq(tome.get_cooldown(MagicTomeCatalog.MAGIC_MISSILE), 3, "Magic Missile ticked once")
	_expect_eq(tome.get_cooldown(MagicTomeCatalog.ARCANE_NOVA), 5, "Arcane Nova ticked once")
	for _tick in 3:
		turn_manager.complete_player_turn()
	_expect(turn_manager.is_player_turn(), "combat returns to the player's turn")
	_expect_eq(tome.get_cooldown(MagicTomeCatalog.MAGIC_MISSILE), 0, "Magic Missile is ready after four player turns")
	_expect(tome.can_cast(MagicTomeCatalog.MAGIC_MISSILE), "the ready spell is offered again")
	_expect_eq(tome.get_cooldown(MagicTomeCatalog.ARCANE_NOVA), 2, "Arcane Nova still has two turns left")

	# (8) No enemy on the field = nothing to strike.
	combat.set_combat_targets([])
	_expect(not tome.can_cast(MagicTomeCatalog.MAGIC_MISSILE), "an empty battlefield offers no cast")
	_expect(not tome.cast(MagicTomeCatalog.MAGIC_MISSILE), "an empty battlefield refuses the cast")

	tome.free()
	turn_manager.free()
	combat.free()
	enemy.free()
	caster.free()


func _test_magic_row_ui() -> void:
	var actions_scene := load("res://scenes/ui/combat_actions.tscn") as PackedScene
	var actions := actions_scene.instantiate() as CombatActions
	root.add_child(actions)
	await process_frame
	_expect(actions != null, "the action cluster instantiates")

	actions.set_magic_states([
		_magic_state(MagicTomeCatalog.MAGIC_MISSILE, "MAGIC MISSILE", 0, true),
		_magic_state(MagicTomeCatalog.ARCANE_NOVA, "ARCANE NOVA", 6, false),
	])
	var row: HBoxContainer = actions.get_node_or_null("MagicRow") as HBoxContainer
	_expect(row != null, "the action cluster has a MAGIC row")
	if row == null:
		actions.free()
		return
	_expect_eq(row.get_child_count(), 2, "the row builds one button per reported spell")
	var missile := row.get_child(0) as Button
	var nova := row.get_child(1) as Button
	_expect(missile.text.contains("READY") and not missile.disabled, "a ready spell reads READY and is pressable")
	_expect(nova.text.contains("CD 6") and nova.disabled, "a recharging spell shows its remaining Player Turns")

	var pressed: Array[StringName] = []
	actions.magic_requested.connect(func(skill_id: StringName) -> void: pressed.append(skill_id))
	missile.emit_signal("pressed")
	_expect(pressed == [MagicTomeCatalog.MAGIC_MISSILE], "a press forwards the spell id")

	# The row is refreshed every HUD frame: it must update, never duplicate.
	actions.set_magic_states([
		_magic_state(MagicTomeCatalog.MAGIC_MISSILE, "MAGIC MISSILE", 4, false),
		_magic_state(MagicTomeCatalog.ARCANE_NOVA, "ARCANE NOVA", 5, false),
	])
	_expect_eq(row.get_child_count(), 2, "a refresh reuses the existing buttons")
	_expect(missile.text.contains("CD 4") and missile.disabled, "the refresh shows the new cooldown")

	actions.free()


func _magic_state(skill_id: StringName, display_name: String, cooldown: int, usable: bool) -> Dictionary:
	return {
		"skill_id": skill_id,
		"display_name": display_name,
		"tooltip": "",
		"cooldown": cooldown,
		"usable": usable,
	}


func _make_enemy(enemy_id: StringName, cell: Vector2i) -> MockActor:
	var enemy := MockActor.new()
	enemy.enemy_id = enemy_id
	enemy.grid_position = cell
	enemy.enemy_stats = EnemyStats.new()
	enemy.enemy_stats.max_hp = 200
	enemy.enemy_stats.current_hp = 200
	enemy.enemy_stats.defense = 10
	return enemy


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _expect_eq(actual: Variant, expected: Variant, description: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [description, str(expected), str(actual)])
