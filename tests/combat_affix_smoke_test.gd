extends SceneTree

## §12 "every affix affects combat", §4 refused attacks, §7 potions — driven on the
## real game scene, so an affix that stops reaching CombatSystem (or an action that
## silently starts costing the turn again) fails here.
##
## Run headless: godot --headless --path . -s res://tests/combat_affix_smoke_test.gd

const GameScene = preload("res://scenes/world/grid_combat.tscn")

## Where each §12 affix must land on `PlayerStats`, checked against the aggregation's
## own stat-id → field table. A newcomer to the catalogue without an entry there
## fails the test rather than shipping as a decorative affix.
const STAT_FIELDS := {
	&"attack": "attack",
	&"defense": "defense",
	&"hp": "max_hp",
	&"critical_chance": "critical_chance",
	&"critical_damage": "critical_damage",
	&"dodge": "dodge",
	&"movement": "movement_points",
	&"attack_range": "attack_range",
	&"life_steal": "life_steal",
	&"damage_vs_elite": "damage_vs_elite",
	&"damage_vs_boss": "damage_vs_boss",
	&"stun_chance": "stun_chance",
}

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_affix_catalogue()
	_test_affix_text_and_negative_values()
	_test_status_component()

	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame

	var player: PlayerController = game.get_node("Player")
	var turn_manager: TurnManager = game.get_node("TurnManager")
	var stage_manager: StageManager = game.get_node("StageManager")

	_test_stat_mapping(player)
	_test_potion_replenishment(game, player)
	await _test_affixes_in_combat(player, turn_manager, stage_manager)
	await _test_action_economy(game, player, turn_manager, stage_manager)

	game.queue_free()
	if _failures.is_empty():
		print("combat_affix_smoke_test: PASS")
	else:
		print("combat_affix_smoke_test: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


# ---------------------------------------------------------------------------
# §12 affix catalogue
# ---------------------------------------------------------------------------


func _test_affix_catalogue() -> void:
	var stat_ids: Array[StringName] = EquipmentAffix.get_stat_ids()
	_expect(not stat_ids.is_empty(), "the affix catalogue must not be empty")
	for stat_id in stat_ids:
		_expect(EquipmentAffix.get_base_value(stat_id) > 0.0, "affix '%s' needs a base value" % stat_id)
		_expect(EquipmentAffix.get_weight(stat_id) > 0.0, "affix '%s' must be rollable" % stat_id)
		_expect(EquipmentAffix.get_economic_weight(stat_id) > 0.0, "affix '%s' needs an economic weight" % stat_id)
		_expect(
			EquipmentAffix.get_display_name_for_stat(stat_id) != "Unknown Affix",
			"affix '%s' needs a display name" % stat_id,
		)
		_expect(STAT_FIELDS.has(stat_id), "affix '%s' is not mapped to a PlayerStats field" % stat_id)
	_expect(EquipmentAffix.is_known_stat(&"attack"), "a catalogued stat must be known")
	_expect(not EquipmentAffix.is_known_stat(&"hit_points"), "a misspelled stat id must not be known")


func _test_affix_text_and_negative_values() -> void:
	# §12: an authored affix may be negative ("HP -10") and must render with its sign.
	_expect(EquipmentAffix.format_value(20.0, false) == "+20", "a flat affix renders as +20")
	_expect(EquipmentAffix.format_value(-10.0, false) == "-10", "a negative flat affix keeps its sign")
	_expect(EquipmentAffix.format_value(0.25, true) == "+25%", "a percentage affix renders as +25%")
	_expect(EquipmentAffix.format_value(-0.03, true) == "-3%", "a negative percentage keeps its sign")

	var affix := EquipmentAffix.new()
	affix.stat_id = &"stun_chance"
	affix.value = 0.25
	affix.is_percentage = EquipmentAffix.is_percentage_stat(&"stun_chance")
	_expect(affix.is_percentage, "stun chance must be a percentage affix")
	_expect(affix.get_label() == "Stun Chance", "an unnamed affix inherits its catalogue label")
	affix.display_name = "Concussive"
	_expect(affix.get_label() == "Concussive", "an authored affix name wins over the catalogue label")

	# A rolled affix stays positive; only authored values may be cursed.
	var rolled := EquipmentAffix.create_rolled(&"stun_chance", 1, EquipmentRarity.COMMON, RandomNumberGenerator.new())
	_expect(rolled.value > 0.0, "a rolled affix is always positive")
	_expect(rolled.value <= 1.0, "a rolled affix must stay a usable ratio")


func _test_status_component() -> void:
	var status := StatusEffectComponent.new()
	var applied: Array[StringName] = []
	status.applied.connect(func(status_id: StringName, _turns: int) -> void: applied.append(status_id))
	_expect(not status.is_stunned(), "a fresh actor is not stunned")
	_expect(status.apply_stun(), "the first stun applies")
	_expect(status.is_stunned(), "an applied stun is active")
	_expect(status.turns_remaining(StatusEffectComponent.STUN) == StatusEffectComponent.STUN_TURNS, "the stun lasts its configured turns")
	_expect(not status.apply_stun(), "refreshing an active stun reports nothing new")
	_expect(applied.size() == 1, "a refresh must not be announced twice")
	status.tick_turn()
	_expect(not status.is_stunned(), "the stun expires after its turns are spent")
	_expect(status.turns_remaining(StatusEffectComponent.STUN) == 0, "an expired status holds no turns")


# ---------------------------------------------------------------------------
# The controller's affix -> stat mapping
# ---------------------------------------------------------------------------


func _test_stat_mapping(_player: PlayerController) -> void:
	# R1 aggregates instead of adjusting: an affix reaches the stats through
	# [method BalanceFormulas.stat_block], which is the ONE place a stat id becomes a
	# PlayerStats field. A stat id the mapping table does not know would be rolled, displayed and
	# priced while never reaching combat, so every id of the catalogue is checked here.
	var profile: BalanceProfile = BalanceProfile.get_default()
	var slot_factors: Array[float] = EquipmentStatBlock.slot_factors(profile, EquipmentStatBlock.empty_slots())
	var base_stats: Dictionary = {
		&"critical_chance": profile.base_critical_chance,
		&"critical_damage": profile.base_critical_damage,
		&"movement_points": 3,
		&"attack_range": 1,
	}
	var plain: Dictionary = BalanceFormulas.stat_block(profile, 1, slot_factors, {}, base_stats)
	for stat_id in EquipmentAffix.get_stat_ids():
		var field: String = STAT_FIELDS[stat_id]
		var raised: Dictionary = BalanceFormulas.stat_block(profile, 1, slot_factors, {stat_id: 1.0}, base_stats)
		_expect(
			float(raised[field]) > float(plain[field]),
			"affix '%s' must move PlayerStats.%s (the aggregation does not apply it)" % [stat_id, field],
		)

	# §12 negative authored values travel the same path as a positive one, and neither may
	# produce a negative HP, a negative DEF or a healing attack (contract §3.1).
	var cursed_hp: Dictionary = BalanceFormulas.stat_block(profile, 1, slot_factors, {&"hp": -100000.0}, base_stats)
	_expect(int(cursed_hp[&"max_hp"]) == 1, "a cursed HP affix floors max HP at 1, got %d" % int(cursed_hp[&"max_hp"]))
	var cursed_defense: Dictionary = BalanceFormulas.stat_block(profile, 1, slot_factors, {&"defense": -100000.0}, base_stats)
	_expect(int(cursed_defense[&"defense"]) == 0, "a cursed defense affix floors defense at 0, got %d" % int(cursed_defense[&"defense"]))
	_expect(int(cursed_defense[&"attack"]) >= 1, "a cursed set must still leave a usable attack")


# ---------------------------------------------------------------------------
# §12 affixes that must change a fight
# ---------------------------------------------------------------------------


func _test_affixes_in_combat(
	player: PlayerController,
	turn_manager: TurnManager,
	stage_manager: StageManager,
) -> void:
	var enemy := _first_live_enemy(stage_manager)
	if enemy == null:
		_expect(false, "the stage should have spawned at least one enemy")
		return

	# A private CombatSystem with no turn manager: authorization is not the subject
	# here, the affix effects are.
	var combat := CombatSystem.new()
	root.add_child(combat)

	var stats: PlayerStats = player.player_stats
	stats.max_hp = 10000
	stats.current_hp = 5000
	stats.critical_chance = 0.0
	stats.dodge = 0.0
	stats.life_steal = 0.0
	stats.damage_vs_elite = 0.0
	stats.damage_vs_boss = 0.0
	stats.stun_chance = 0.0
	# A stage-1 enemy is worth a couple of v4 hero hits, and the sequence below attacks it several
	# times: give it a MAXIMUM that survives the whole run, because `set_current_hp` clamps to the
	# current maximum (raising only the current HP would be capped back down).
	enemy.enemy_stats.max_hp = 1000000
	enemy.set_current_hp(1000000)
	enemy.grid_position = player.get_grid_position() + Vector2i(1, 0)
	_expect(enemy.enemy_runtime.current_hp > 0, "the test enemy must be alive")

	var baseline := combat.resolve_attack(player, enemy)
	_expect(not baseline.is_miss and baseline.final_damage > 0, "a plain in-range attack must land")

	# --- Dodge: the target evades the strike and takes no damage at all ---
	stats.dodge = 1.0
	var player_hp_before: int = stats.current_hp
	var dodged := combat.resolve_attack(enemy, player)
	_expect(dodged.is_miss, "a dodging target takes no hit")
	_expect(dodged.is_dodge, "the miss must be reported as a dodge, not a refusal")
	_expect(not dodged.is_refused, "a dodge is a resolved attack, not a refused one")
	_expect(stats.current_hp == player_hp_before, "a dodged attack must not damage the player")
	stats.dodge = 0.0

	# --- Life Steal: damage dealt comes back as HP, capped at maximum ---
	stats.life_steal = 0.5
	stats.current_hp = 5000
	var stolen := combat.resolve_attack(player, enemy)
	_expect(stolen.lifesteal_heal > 0, "life steal must heal the attacker")
	_expect(
		stats.current_hp == 5000 + stolen.lifesteal_heal,
		"life steal must restore exactly the reported amount",
	)
	stats.current_hp = stats.max_hp
	var capped := combat.resolve_attack(player, enemy)
	_expect(capped.lifesteal_heal == 0, "life steal at full HP must report no healing")
	stats.life_steal = 0.0

	# --- Damage vs Boss / vs Elite: only the named tier gets the bonus ---
	stats.current_hp = 5000
	stats.damage_vs_boss = 0.5
	enemy.is_mini_boss = true
	var boss_hit := combat.resolve_attack(player, enemy)
	_expect(
		boss_hit.final_damage > baseline.final_damage,
		"damage_vs_boss must raise damage against a mini boss (%d vs %d)" % [
			boss_hit.final_damage, baseline.final_damage,
		],
	)
	enemy.is_mini_boss = false
	stats.damage_vs_boss = 0.0
	var normal_hit := combat.resolve_attack(player, enemy)
	_expect(
		normal_hit.final_damage == baseline.final_damage,
		"a boss affix must not inflate damage against a normal enemy",
	)

	stats.damage_vs_elite = 0.5
	var elite_data := EnemyData.new()
	elite_data.enemy_type = EnemyType.ELITE
	enemy.enemy_data = elite_data
	_expect(enemy.get_enemy_type() == EnemyType.ELITE, "the test enemy should report the elite tier")
	var elite_hit := combat.resolve_attack(player, enemy)
	_expect(
		elite_hit.final_damage > normal_hit.final_damage,
		"damage_vs_elite must raise damage against an elite (%d vs %d)" % [
			elite_hit.final_damage, normal_hit.final_damage,
		],
	)
	stats.damage_vs_elite = 0.0

	# --- Stun: a landed hit can cost the enemy its whole turn ---
	stats.stun_chance = 1.0
	var stunned_hit := combat.resolve_attack(player, enemy)
	_expect(stunned_hit.applied_status_id == StatusEffectComponent.STUN, "a landed stun must be reported on the result")
	_expect(enemy.is_stunned(), "the enemy must carry the stun")
	stats.stun_chance = 0.0

	var skip_count: Array[int] = [0]
	var attack_count: Array[int] = [0]
	enemy.stunned_turn_skipped.connect(func(_enemy: EnemyController) -> void: skip_count[0] += 1)
	enemy.attack_requested.connect(func(_enemy: EnemyController, _target: Node) -> void: attack_count[0] += 1)
	enemy.take_turn(player, turn_manager)
	_expect(skip_count[0] == 1, "a stunned enemy must skip its turn")
	_expect(attack_count[0] == 0, "a stunned enemy must not attack")
	_expect(not enemy.is_stunned(), "a 1-turn stun is spent by the turn it suppressed")

	enemy.take_turn(player, turn_manager)
	_expect(skip_count[0] == 1, "an enemy that is no longer stunned takes a normal turn")

	combat.queue_free()


# ---------------------------------------------------------------------------
# §4 and §7: what an action costs
# ---------------------------------------------------------------------------


func _test_action_economy(
	game: Node,
	player: PlayerController,
	turn_manager: TurnManager,
	stage_manager: StageManager,
) -> void:
	_expect(turn_manager.get_phase() == TurnState.PLAYER_TURN, "the stage should open on the player's turn")

	# --- §4: a refused attack must not spend the action or end the turn ---
	var enemy := _first_live_enemy(stage_manager)
	if enemy == null:
		_expect(false, "the stage should still have a live enemy")
		return
	enemy.grid_position = Vector2i(10, 0)
	var combat_system: CombatSystem = game.get_node("CombatSystem")
	var refused := combat_system.resolve_attack(player, enemy)
	_expect(refused.is_refused, "an out-of-range attack must be refused")
	_expect(refused.is_miss, "a refused attack deals no damage")
	_expect(not refused.is_dodge, "a refusal is not a dodge")

	player.attack_requested.emit(player, enemy)
	await process_frame
	_expect(turn_manager.get_phase() == TurnState.PLAYER_TURN, "a refused attack must not end the player's turn")
	_expect(turn_manager.is_action_available(player), "a refused attack must not spend the action")

	# --- §7: a potion drunk from the bag costs the action and ends the turn ---
	player.player_stats.max_hp = 400
	player.player_stats.current_hp = 100
	var potion := _make_potion()
	_expect(player.add_equipment(potion), "the test potion must fit in the bag")
	_expect(player.use_item(potion), "a potion must be usable below full HP")
	_expect(player.player_stats.current_hp > 100, "using a potion must heal")
	_expect(
		turn_manager.get_phase() != TurnState.PLAYER_TURN,
		"using a bag potion in combat must end the player's turn",
	)


func _test_potion_replenishment(game: Node, player: PlayerController) -> void:
	var before: int = player.get_healing_item_count()
	_expect(player.add_healing_items(2) == before + 2, "loot must be able to restock the potion counter")

	# §7: potions are found as loot, and a looted potion restocks the counter that
	# the HUD button and AUTO drink from instead of filling a bag slot.
	var potion := _make_potion()
	var bag_before: int = player.get_inventory().get_item_count()
	var loot: Array[EquipmentInstance] = [potion]
	game._on_loot_dropped(null, loot)
	_expect(
		player.get_healing_item_count() == before + 3,
		"a looted potion must restock the potion counter (got %d, expected %d)" % [
			player.get_healing_item_count(), before + 3,
		],
	)
	_expect(
		player.get_inventory().get_item_count() == bag_before,
		"a looted potion must not also fill a bag slot",
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_potion() -> EquipmentInstance:
	var definition := EquipmentDefinition.new()
	definition.definition_id = &"smoke_test_potion"
	definition.display_name = "Test Potion"
	definition.is_consumable = true
	definition.heal_ratio = 0.35
	return EquipmentInstance.create_from_definition(definition)


func _first_live_enemy(stage_manager: StageManager) -> EnemyController:
	for enemy in stage_manager.get_spawned_enemies():
		if enemy != null and is_instance_valid(enemy) and not enemy.is_defeated():
			return enemy
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
