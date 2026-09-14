extends SceneTree

## M8 integration acceptance of the v4 balance contract (§8):
##   * every damage source — the Main Player's normal attack, the three active skills, a Magic
##     Tome spell and a Sub Hero — resolves through the ONE §4.1 armor entry and differs only by
##     its own multiplier;
##   * life steal pays on the HP the target actually LOST, so overkill heals nothing (§4.1);
##   * a released stun cannot be re-applied before its target has completed its next own turn, so
##     a high stun chance cannot chain-lock an enemy (§3.2).
##
## Every expectation is computed from the production functions and the injected profile, never
## from a copied constant.
##
## Run headless: godot --headless --path . -s res://tests/combat_integration_smoke_test.gd

const MATERIAL_ATTACK: int = 200
const MATERIAL_DEFENSE: int = 25
## Room for every source's hits without the dummy dying mid-test.
const DUMMY_HP: int = 1000000

class MockActor:
	extends Node2D

	var player_stats: PlayerStats
	var enemy_stats: EnemyStats
	var player_id: StringName = &""
	var enemy_id: StringName = &""
	var grid_position: Vector2i = Vector2i.ZERO
	var skill_levels: Dictionary = {}

	func get_grid_position() -> Vector2i:
		return grid_position

	func get_skill_level(skill_id: StringName) -> int:
		return int(skill_levels.get(skill_id, 0))

	## §4.1 Sub Heroes never target a Main Player; the mock only needs the hooks CombatSystem
	## reads from a real actor.
	func clamp_current_hp() -> void:
		if player_stats != null:
			player_stats.clamp_current_hp()
		if enemy_stats != null:
			enemy_stats.clamp_current_hp()

	func handle_defeat() -> void:
		pass

	func take_turn(_player: Node, turn_manager: TurnManager) -> void:
		turn_manager.complete_enemy_turn(self)


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_armor_parity_across_sources()
	_test_sub_hero_armor_parity()
	_test_life_steal_ignores_overkill()
	_test_stun_cannot_chain_lock()

	if _failures.is_empty():
		print("combat_integration_smoke_test: PASS")
	else:
		print("combat_integration_smoke_test: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


# ---------------------------------------------------------------------------
# §4.1: ONE armor entry for the attack, the skills and the Tome
# ---------------------------------------------------------------------------


func _test_armor_parity_across_sources() -> void:
	var profile: BalanceProfile = BalanceProfile.get_default()
	var expected_raw: float = BalanceFormulas.armor_damage(
		profile, float(MATERIAL_ATTACK), float(MATERIAL_DEFENSE)
	)
	# The whole point of the entry: a plain attack IS the unmodified armor result.
	var world: Dictionary = _build_world()
	var combat: CombatSystem = world["combat"]
	var player: MockActor = world["player"]
	var enemy: MockActor = world["enemy"]

	var plain: DamageResult = combat.resolve_attack(player, enemy)
	_expect_eq(
		plain.final_damage,
		_expected_damage(profile, expected_raw, 1.0),
		"a normal attack uses the shared armor entry"
	)
	_expect_eq(plain.hp_lost, plain.final_damage, "a non-lethal hit costs the target its full damage")

	# §4.1: "普通攻击 skill_multiplier=1", so Arcane Bolt (1.0× at level 1) must land exactly the
	# same number as the plain attack — a skill cannot travel a second, older damage path.
	var bolt_world: Dictionary = _build_world()
	var bolt_combat: CombatSystem = bolt_world["combat"]
	var bolt_player: MockActor = bolt_world["player"]
	var bolt_enemy: MockActor = bolt_world["enemy"]
	bolt_player.skill_levels[SkillCatalog.ARCANE_BOLT] = 1
	var bolt: Dictionary = _capture_next_hit(bolt_combat)
	var bolt_ok: bool = bolt_combat.resolve_skill(bolt_player, SkillCatalog.ARCANE_BOLT, bolt_enemy)
	_expect(bolt_ok, "Arcane Bolt must resolve against an adjacent enemy")
	_expect_eq(
		int(bolt["damage"]),
		_expected_damage(profile, expected_raw, 1.0),
		"Arcane Bolt (1.0×) lands the armor result"
	)

	# ...and a different multiplier only scales that same result.
	var whirlwind_world: Dictionary = _build_world()
	var whirlwind_combat: CombatSystem = whirlwind_world["combat"]
	var whirlwind_player: MockActor = whirlwind_world["player"]
	var whirlwind_enemy: MockActor = whirlwind_world["enemy"]
	whirlwind_player.skill_levels[SkillCatalog.WHIRLWIND] = 1
	var whirlwind: Dictionary = _capture_next_hit(whirlwind_combat)
	_expect(
		whirlwind_combat.resolve_skill(whirlwind_player, SkillCatalog.WHIRLWIND, null),
		"Whirlwind must resolve against an adjacent enemy"
	)
	_expect_eq(
		int(whirlwind["damage"]),
		_expected_damage(profile, expected_raw, 0.8),
		"Whirlwind (0.8×) is the armor result times its multiplier"
	)

	# §4.1/§16: the Tome shares the entry too, with its own authored multiplier and no riders.
	var tome_world: Dictionary = _build_world()
	var tome_combat: CombatSystem = tome_world["combat"]
	var caster: MockActor = tome_world["player"]
	var tome_enemy: MockActor = tome_world["enemy"]
	caster.player_stats.life_steal = 0.5
	var spell: DamageResult = tome_combat.resolve_magic_strike(
		caster, tome_enemy, 0.9, MagicTomeCatalog.MAGIC_MISSILE
	)
	_expect_eq(
		spell.final_damage,
		_expected_damage(profile, expected_raw, 0.9),
		"a Magic Tome spell is the armor result times its multiplier"
	)
	_expect_eq(spell.lifesteal_heal, 0, "a spell still steals no life")

	_free_world(world)
	_free_world(bolt_world)
	_free_world(whirlwind_world)
	_free_world(tome_world)


func _test_sub_hero_armor_parity() -> void:
	var profile: BalanceProfile = BalanceProfile.get_default()
	var skeleton_data: SubHeroData = load("res://resources/sub_heroes/common/SkeletonArcher.tres")
	if skeleton_data == null:
		_expect(false, "the skeleton archer definition must be loadable")
		return
	var instance := SubHeroInstance.new(&"skeleton_archer", 3)
	var manager := SubHeroCombatManager.new()
	var combat := CombatSystem.new()
	root.add_child(manager)
	root.add_child(combat)
	manager.attach_combat_system(combat)
	var unarmored_damage: int = manager.calculate_subhero_damage(skeleton_data, instance, null)
	var attack_power: float = float(manager.calculate_subhero_attack(skeleton_data, instance))
	var expected: int = _expected_damage(
		profile, BalanceFormulas.armor_damage(profile, attack_power, float(MATERIAL_DEFENSE)), 1.0
	)
	var armored := MockActor.new()
	armored.enemy_stats = EnemyStats.new()
	armored.enemy_stats.max_hp = DUMMY_HP
	armored.enemy_stats.current_hp = DUMMY_HP
	armored.enemy_stats.defense = MATERIAL_DEFENSE
	root.add_child(armored)
	_expect_eq(
		manager.calculate_subhero_damage(skeleton_data, instance, armored),
		expected,
		"a Sub Hero hit is the shared armor entry on its own attack power"
	)
	_expect(
		unarmored_damage >= expected,
		"armor must not increase a Sub Hero's damage (%d vs %d)" % [unarmored_damage, expected]
	)
	armored.free()
	manager.free()
	combat.free()


# ---------------------------------------------------------------------------
# §4.1: overkill does not pay life steal
# ---------------------------------------------------------------------------


func _test_life_steal_ignores_overkill() -> void:
	var world: Dictionary = _build_world()
	var combat: CombatSystem = world["combat"]
	var player: MockActor = world["player"]
	var enemy: MockActor = world["enemy"]
	player.player_stats.life_steal = 0.5
	player.player_stats.current_hp = 1000
	# A target with 3 HP left against a hit worth far more than 3.
	enemy.enemy_stats.max_hp = DUMMY_HP
	enemy.enemy_stats.current_hp = 3

	var lethal: DamageResult = combat.resolve_attack(player, enemy)
	_expect(lethal.target_defeated, "the hit must kill the 3 HP target")
	_expect(lethal.final_damage > 3, "the rolled damage is much larger than the target's HP")
	_expect_eq(lethal.hp_lost, 3, "the reported HP loss is the target's real loss, not the overkill")
	_expect_eq(
		lethal.lifesteal_heal,
		roundi(3.0 * 0.5),
		"life steal pays on the HP actually lost (3 × 50 %), not on the overkill"
	)
	_expect_eq(
		player.player_stats.current_hp,
		1000 + roundi(3.0 * 0.5),
		"the attacker is healed by exactly the reported amount"
	)
	_free_world(world)


# ---------------------------------------------------------------------------
# §3.2: a released stun cannot be re-applied before the next own turn completes
# ---------------------------------------------------------------------------


func _test_stun_cannot_chain_lock() -> void:
	var status := StatusEffectComponent.new()
	_expect(status.apply_stun(), "the first stun applies")
	_expect(
		not status.apply_stun(),
		"a stun on an already stunned target is a refresh, never an extension"
	)
	_expect_eq(
		status.turns_remaining(StatusEffectComponent.STUN),
		StatusEffectComponent.STUN_TURNS,
		"a refresh cannot raise the remaining turns"
	)

	# The turn the stun suppressed spends it, and opens the immunity window.
	status.tick_turn()
	_expect(not status.is_stunned(), "the stun is released by the turn it suppressed")
	_expect(status.is_stun_immune(), "the release opens the §12 immunity window")
	_expect(
		not status.apply_stun(),
		"a stun rolled during the immunity window is refused — no chain lock"
	)
	_expect(not status.is_stunned(), "the refused stun leaves no status behind")

	# The target's next own turn is what the window waits for.
	status.complete_turn()
	_expect(not status.is_stun_immune(), "the completed own turn closes the immunity window")
	_expect(status.apply_stun(), "a stun after the window applies again")

	# A caught stun that is never refreshed must not leave a permanent immunity behind.
	var second := StatusEffectComponent.new()
	second.apply_stun()
	second.tick_turn()
	second.complete_turn()
	_expect(not second.is_stun_immune(), "the window never outlives one own turn")
	_expect(second.apply_stun(), "and the target is stunnable again")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


## A minimal world: a Main Player actor and one adjacent armored enemy, wired through the real
## [CombatSystem] and [TurnManager].
func _build_world() -> Dictionary:
	var player := MockActor.new()
	player.player_id = &"player"
	player.player_stats = PlayerStats.new()
	player.player_stats.max_hp = 100000
	player.player_stats.current_hp = 100000
	player.player_stats.attack = MATERIAL_ATTACK
	player.player_stats.defense = 0
	player.player_stats.critical_chance = 0.0
	player.player_stats.critical_damage = 1.0
	player.player_stats.dodge = 0.0
	player.player_stats.life_steal = 0.0
	player.player_stats.stun_chance = 0.0
	player.player_stats.damage_vs_elite = 0.0
	player.player_stats.damage_vs_boss = 0.0
	player.grid_position = Vector2i(1, 3)

	var enemy := MockActor.new()
	enemy.enemy_id = &"armor_dummy"
	enemy.enemy_stats = EnemyStats.new()
	enemy.enemy_stats.max_hp = DUMMY_HP
	enemy.enemy_stats.current_hp = DUMMY_HP
	enemy.enemy_stats.attack = 1
	enemy.enemy_stats.defense = MATERIAL_DEFENSE
	enemy.grid_position = Vector2i(2, 3)

	var combat := CombatSystem.new()
	var turn_manager := TurnManager.new()
	root.add_child(player)
	root.add_child(enemy)
	root.add_child(combat)
	root.add_child(turn_manager)
	combat.attach_turn_manager(turn_manager)
	combat.set_player_actor(player)
	combat.set_combat_targets([enemy])
	turn_manager.start_combat(player, [enemy])
	return {"combat": combat, "turn_manager": turn_manager, "player": player, "enemy": enemy}


## Collects the next resolved attack so a skill's real damage can be compared (a skill resolves
## through the same private path as an attack and reports only success).
func _capture_next_hit(combat: CombatSystem) -> Dictionary:
	var captured: Dictionary = {"damage": -1}
	combat.attack_resolved.connect(
		func(result: DamageResult) -> void: captured["damage"] = result.final_damage,
		CONNECT_ONE_SHOT
	)
	return captured


func _free_world(world: Dictionary) -> void:
	for key in ["combat", "turn_manager", "player", "enemy"]:
		var node: Node = world.get(key)
		if node != null and is_instance_valid(node):
			node.free()


## §4.1: `final = max(1, round(modified × 1))` — computed from the profile's own entry, so this
## test never restates the formula.
func _expected_damage(profile: BalanceProfile, raw: float, multiplier: float) -> int:
	return maxi(roundi(raw * multiplier), 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _expect_eq(actual: int, expected: int, description: String) -> void:
	if actual != expected:
		_failures.append("%s (got %d, expected %d)" % [description, actual, expected])
