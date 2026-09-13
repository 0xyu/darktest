extends SceneTree

## R1 acceptance for the hero aggregation (contract §3.1, §3.2, §3.3):
##
##   * reverse-order equipment: the same items equipped in the opposite order give the SAME stats
##   * mixed equipment: one item per slot, each with its own rarity and item level, each slot
##     contributing its OWN factor — an average item level is never substituted
##   * empty slots, the naked reference `b_X * G(L)^0.4`, and L / il moving independently
##   * the §3.2 effective caps, and utility affixes that do not grow with the item level
##   * the §3.3 HP projection, including the swap a living hero must be refused
##
## Every number here is read from the authoritative profile — retuning the .tres retests the
## aggregation instead of the test restating it.

const PROFILE_PATH: String = "res://resources/balance/balance_profile_default.tres"
const MAX_REPORTED_ROWS: int = 6

var _profile: BalanceProfile
var _failures: Array[String] = []
var _checks: int = 0
var _reported: int = 0
var _serial: int = 0


func _init() -> void:
	_profile = load(PROFILE_PATH) as BalanceProfile
	if _profile == null:
		push_error("cannot load %s" % PROFILE_PATH)
		quit(1)
		return
	_test_naked_and_independent_scales()
	_test_mixed_equipment()
	_test_reverse_order_equipment()
	_test_utility_caps()
	_test_utility_rolls_do_not_scale_with_item_level()
	_test_hp_projection()
	_report()


# ---------------------------------------------------------------------------
# §3.1 scale
# ---------------------------------------------------------------------------


func _test_naked_and_independent_scales() -> void:
	var naked: Dictionary = EquipmentStatBlock.compute(_profile, 1, EquipmentStatBlock.empty_slots())
	_check(
		int(naked[&"max_hp"]) == 121 and int(naked[&"attack"]) == 52 and int(naked[&"defense"]) == 5,
		"a naked level-1 hero is b_X itself: %d/%d/%d" % [naked[&"max_hp"], naked[&"attack"], naked[&"defense"]]
	)
	for level in [1, 10, 100, 1000]:
		var block: Dictionary = EquipmentStatBlock.compute(_profile, level, EquipmentStatBlock.empty_slots())
		var expected: float = _profile.base_hp * BalanceFormulas.level_scale(_profile, level)
		_check(
			_close(float(block[&"max_hp"]), expected, 0.51),
			"naked HP at L%d is b_HP*G(L)^0.4 = %.2f, got %d" % [level, expected, block[&"max_hp"]]
		)

	# The level and the item level move INDEPENDENTLY: same gear, one level higher, is exactly
	# the level share of the growth.
	var gear: Array[EquipmentInstance] = EquipmentStatBlock.empty_slots()
	gear[EquipmentSlot.WEAPON] = _item(EquipmentSlot.WEAPON, EquipmentRarity.COMMON, 100)
	var at_hundred: Dictionary = EquipmentStatBlock.compute(_profile, 100, gear)
	var at_hundred_one: Dictionary = EquipmentStatBlock.compute(_profile, 101, gear)
	var level_ratio: float = float(at_hundred_one[&"attack"]) / float(at_hundred[&"attack"])
	var expected_ratio: float = BalanceFormulas.level_scale(_profile, 101) / BalanceFormulas.level_scale(_profile, 100)
	_check(_close(level_ratio, expected_ratio, 0.001), "one level is worth G(101)^0.4/G(100)^0.4 = %.5f, got %.5f" % [expected_ratio, level_ratio])

	var item_ratio: float = BalanceFormulas.item_scale(_profile, 101) / BalanceFormulas.item_scale(_profile, 100)
	_check(item_ratio > 1.0, "item_scale grows with the item level (%.5f per level at il=100)" % item_ratio)


# ---------------------------------------------------------------------------
# §3.1 mixed equipment
# ---------------------------------------------------------------------------


func _test_mixed_equipment() -> void:
	# Seven slots, seven different rarities and item levels, all empty of affixes so the block is
	# exactly `level_scale(L) * b_X * M_X`.
	var gear: Array[EquipmentInstance] = EquipmentStatBlock.empty_slots()
	var rarities: Array[int] = [0, 1, 2, 3, 4, 5, 2]
	var levels: Array[int] = [3, 40, 7, 1000, 55, 12, 300]
	for slot in range(BalanceProfile.SLOT_COUNT):
		gear[slot] = _item(slot, rarities[slot], levels[slot])
	var level: int = 250
	var block: Dictionary = EquipmentStatBlock.compute(_profile, level, gear)

	for stat_id in BalanceProfile.STAT_IDS:
		var weights: Array[float] = _profile.get_slot_weights(stat_id)
		var expected_multiplier: float = 0.0
		for slot in range(BalanceProfile.SLOT_COUNT):
			expected_multiplier += weights[slot] * BalanceFormulas.slot_factor(_profile, rarities[slot], levels[slot])
		var expected: float = BalanceFormulas.player_stat_value(_profile, stat_id, level, expected_multiplier)
		var field: StringName = BalanceFormulas.PLAYER_STAT_FIELDS[stat_id]
		_check(
			_close(float(block[field]), expected, 0.51),
			"mixed %s is sum_s(w*rarity_core*item_scale) = %.2f, got %d" % [stat_id, expected, block[field]]
		)

	# One item changed and nothing else: the block moves by that slot's weight only.
	var swapped: Array[EquipmentInstance] = gear.duplicate()
	swapped[EquipmentSlot.RING] = _item(EquipmentSlot.RING, EquipmentRarity.MYTHIC, levels[EquipmentSlot.RING] + 500)
	var after: Dictionary = _block_delta(block, EquipmentStatBlock.compute(_profile, level, swapped))
	_check(after[&"attack"] > 0, "upgrading the ring raises attack by %d" % after[&"attack"])
	_check(after[&"defense"] > 0, "upgrading the ring raises defense by %d" % after[&"defense"])
	_check(after[&"max_hp"] > 0, "upgrading the ring raises max HP by %d" % after[&"max_hp"])

	# §3.1: an average item level is NOT a substitute. The same seven items at the mean level are
	# a different hero, and the check is that the two disagree.
	var mean_level: int = 0
	for item_level in levels:
		mean_level += item_level
	mean_level /= levels.size()
	var averaged: Array[EquipmentInstance] = EquipmentStatBlock.empty_slots()
	for slot in range(BalanceProfile.SLOT_COUNT):
		averaged[slot] = _item(slot, rarities[slot], mean_level)
	_check(
		int(EquipmentStatBlock.compute(_profile, level, averaged)[&"max_hp"]) != int(block[&"max_hp"]),
		"a mean item level must not reproduce the per-slot loadout"
	)


# ---------------------------------------------------------------------------
# §3.1/§3.3 reverse-order equipment
# ---------------------------------------------------------------------------


func _test_reverse_order_equipment() -> void:
	var loadout: Array[EquipmentInstance] = [
		_item(EquipmentSlot.WEAPON, EquipmentRarity.MYTHIC, 420, &"attack", 30.0),
		_item(EquipmentSlot.HELMET, EquipmentRarity.COMMON, 12, &"hp", 90.0),
		_item(EquipmentSlot.ARMOR, EquipmentRarity.LEGENDARY, 200, &"defense", 12.0),
		_item(EquipmentSlot.BOOTS, EquipmentRarity.RARE, 75, &"movement", 1.0),
		_item(EquipmentSlot.AMULET, EquipmentRarity.EPIC, 150, &"critical_chance", 0.06),
	]
	var forward := EquipmentInventory.new()
	for item in loadout:
		forward.add_item(item)
	for item in loadout:
		_check(forward.equip_item(item), "the forward order equips %s" % item.get_display_name())

	var reversed := EquipmentInventory.new()
	var mirrored: Array[EquipmentInstance] = []
	for index in range(loadout.size() - 1, -1, -1):
		mirrored.append(_mirror(loadout[index]))
	for item in mirrored:
		reversed.add_item(item)
	for item in mirrored:
		_check(reversed.equip_item(item), "the reverse order equips %s" % item.get_display_name())

	var base_stats: Dictionary = {&"movement_points": 3, &"attack_range": 1}
	var forward_block: Dictionary = EquipmentStatBlock.compute(
		_profile,
		300,
		EquipmentStatBlock.slots_from_inventory(forward),
		base_stats
	)
	var reversed_block: Dictionary = EquipmentStatBlock.compute(
		_profile,
		300,
		EquipmentStatBlock.slots_from_inventory(reversed),
		base_stats
	)
	for field in forward_block:
		_check(
			is_equal_approx(float(forward_block[field]), float(reversed_block[field])),
			"reverse order changes nothing: %s %s vs %s" % [field, forward_block[field], reversed_block[field]]
		)

	# The hero that actually fights with those two inventories is the same hero: same order
	# independence through PlayerController, which is the path a real swap takes.
	var forward_player := _player(300, forward)
	var reversed_player := _player(300, reversed)
	var forward_stats: Dictionary = _snapshot(forward_player.player_stats)
	var reversed_stats: Dictionary = _snapshot(reversed_player.player_stats)
	for field in forward_stats:
		_check(
			forward_stats[field] == reversed_stats[field],
			"a hero who equipped in the opposite order has the same %s (%s vs %s)" % [field, forward_stats[field], reversed_stats[field]]
		)
	_check(
		forward_player.player_stats.max_hp == forward_player.player_stats.current_hp,
		"a hero equipped at full health stays at full health"
	)
	_check(
		forward_player.get_stat_block()[&"max_hp"] == forward_player.player_stats.max_hp,
		"the preview reads the same block the hero fights with"
	)
	forward_player.free()
	reversed_player.free()

	# §3.3: a swap that would floor a LIVING hero below 1 HP is refused instead of being healed
	# back up with max(1); a dead hero may change gear freely.
	var armored := EquipmentInventory.new()
	var plate: EquipmentInstance = _item(EquipmentSlot.ARMOR, EquipmentRarity.MYTHIC, 1000)
	armored.add_item(plate)
	var hero := _player(1, armored)
	_check(armored.equip_item(plate), "the heavy armor is equipped")
	hero.player_stats.current_hp = 1
	var refused: EquipmentInstance = hero.unequip_item(EquipmentSlot.ARMOR)
	_check(refused == null, "taking the armor off at 1/%d HP is refused" % hero.player_stats.max_hp)
	_check(hero.get_equipped_item(EquipmentSlot.ARMOR) == plate, "the refused swap left the armor equipped")
	hero.player_stats.current_hp = 0
	_check(hero.unequip_item(EquipmentSlot.ARMOR) == plate, "a dead hero may still change gear")
	hero.free()


# ---------------------------------------------------------------------------
# §3.2 utility caps and rolling
# ---------------------------------------------------------------------------


func _test_utility_caps() -> void:
	var slots: Array[float] = BalanceFormulas.full_slot_factors(_profile, EquipmentRarity.COMMON, 1)
	var base_stats: Dictionary = {&"movement_points": 3, &"attack_range": 1}

	var trivial: Dictionary = BalanceFormulas.stat_block(_profile, 1, slots, {}, base_stats)
	_check(
		is_equal_approx(float(trivial[&"critical_chance"]), _profile.base_critical_chance)
		and is_equal_approx(float(trivial[&"critical_damage"]), _profile.base_critical_damage),
		"the utility baseline is the §3.2 critical baseline (%.2f / %.2f)" % [trivial[&"critical_chance"], trivial[&"critical_damage"]]
	)

	var overloaded: Dictionary = BalanceFormulas.stat_block(_profile, 1, slots, {
		&"critical_chance": 5.0,
		&"critical_damage": 5.0,
		&"dodge": 5.0,
		&"life_steal": 5.0,
		&"stun_chance": 5.0,
		&"damage_vs_elite": 5.0,
		&"damage_vs_boss": 5.0,
		&"movement": 50.0,
		&"attack_range": 50.0,
	}, base_stats)
	_check(is_equal_approx(float(overloaded[&"critical_chance"]), _profile.critical_chance_cap), "critical chance caps at %.0f%%" % (_profile.critical_chance_cap * 100.0))
	_check(is_equal_approx(float(overloaded[&"critical_damage"]), _profile.critical_damage_max), "critical damage caps at %.0f%%" % (_profile.critical_damage_max * 100.0))
	_check(is_equal_approx(float(overloaded[&"dodge"]), _profile.dodge_cap), "dodge caps at %.0f%%" % (_profile.dodge_cap * 100.0))
	_check(is_equal_approx(float(overloaded[&"life_steal"]), _profile.life_steal_cap), "life steal caps at %.0f%%" % (_profile.life_steal_cap * 100.0))
	_check(is_equal_approx(float(overloaded[&"stun_chance"]), _profile.stun_chance_cap), "stun caps at %.0f%%" % (_profile.stun_chance_cap * 100.0))
	_check(is_equal_approx(float(overloaded[&"damage_vs_elite"]), _profile.tier_damage_cap), "elite damage caps at +%.0f%%" % (_profile.tier_damage_cap * 100.0))
	_check(is_equal_approx(float(overloaded[&"damage_vs_boss"]), _profile.tier_damage_cap), "boss damage caps at +%.0f%%" % (_profile.tier_damage_cap * 100.0))
	_check(int(overloaded[&"movement_points"]) == 3 + _profile.movement_bonus_cap, "movement caps at base + %d" % _profile.movement_bonus_cap)
	_check(int(overloaded[&"attack_range"]) == 1 + _profile.attack_range_bonus_cap, "attack range caps at base + %d" % _profile.attack_range_bonus_cap)

	var negative: Dictionary = BalanceFormulas.stat_block(_profile, 1, slots, {
		&"dodge": -5.0,
		&"life_steal": -5.0,
		&"stun_chance": -5.0,
		&"damage_vs_elite": -5.0,
		&"movement": -50.0,
		&"attack_range": -50.0,
	}, base_stats)
	_check(float(negative[&"dodge"]) == 0.0 and float(negative[&"life_steal"]) == 0.0, "probabilities have a floor of 0")
	_check(float(negative[&"damage_vs_elite"]) == 0.0, "tier damage has a floor of 0")
	_check(int(negative[&"movement_points"]) == 0, "movement floors at 0, got %d" % int(negative[&"movement_points"]))
	_check(int(negative[&"attack_range"]) == 1, "attack range floors at 1, got %d" % int(negative[&"attack_range"]))


func _test_utility_rolls_do_not_scale_with_item_level() -> void:
	# §3.2: a probability is a catalogue base times rarity strength times roll — never a function
	# of the item level, while a core affix carries item_scale.
	for stat_id in [&"critical_chance", &"critical_damage", &"dodge", &"life_steal", &"stun_chance", &"damage_vs_elite", &"movement", &"attack_range"]:
		var low: float = EquipmentAffix.compute_value(stat_id, 1, EquipmentRarity.COMMON, 1.0, _profile)
		var high: float = EquipmentAffix.compute_value(stat_id, 1000, EquipmentRarity.COMMON, 1.0, _profile)
		_check(
			is_equal_approx(low, high),
			"utility affix '%s' ignores the item level (%.4f vs %.4f)" % [stat_id, low, high]
		)
	for stat_id in BalanceProfile.STAT_IDS:
		var base: float = EquipmentAffix.get_base_value(stat_id, _profile)
		var expected_base: float = _profile.get_base_stat(stat_id) * _profile.affix_core_base_share
		_check(
			is_equal_approx(base, expected_base),
			"the %s affix base is 10%% of b_X (%.2f), got %.2f" % [stat_id, expected_base, base]
		)
		var low_core: float = EquipmentAffix.compute_value(stat_id, 1, EquipmentRarity.COMMON, 1.0, _profile)
		var high_core: float = EquipmentAffix.compute_value(stat_id, 1000, EquipmentRarity.COMMON, 1.0, _profile)
		_check(
			_close(high_core / low_core, BalanceFormulas.item_scale(_profile, 1000), 0.001),
			"the %s affix carries item_scale(il) (ratio %.1f)" % [stat_id, high_core / low_core]
		)

	var rolled: EquipmentAffix = EquipmentAffix.create_rolled(
		&"attack",
		500,
		EquipmentRarity.LEGENDARY,
		RandomNumberGenerator.new(),
		_profile
	)
	_check(rolled != null and rolled.value > 0.0, "a rolled affix is positive")
	_check(rolled != null and rolled.roll_ratio >= 0.0 and rolled.roll_ratio <= 1.0, "the roll identity stays a 0..1 ratio")


# ---------------------------------------------------------------------------
# §3.3 HP projection
# ---------------------------------------------------------------------------


func _test_hp_projection() -> void:
	_check(BalanceFormulas.project_current_hp(100, 50, 100) == 50, "an unchanged maximum keeps the current HP (idempotent rebuild)")
	_check(BalanceFormulas.project_current_hp(200, 100, 100) == 50, "a halved maximum halves the current HP")
	_check(BalanceFormulas.project_current_hp(100, 100, 200) == 200, "a doubled maximum doubles a full health bar")
	_check(BalanceFormulas.project_current_hp(200, 0, 100) == 0, "a dead hero stays dead")
	_check(BalanceFormulas.project_current_hp(10000, 1, 100) == 0, "a living hero may project to 0, which the caller refuses")
	_check(BalanceFormulas.project_current_hp(100, 99, 200) == 198, "the projection floors instead of rounding up")


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


## The per-field difference between two aggregated blocks, keyed by PlayerStats field.
func _block_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var deltas: Dictionary = {}
	for field in after:
		deltas[field] = float(after[field]) - float(before.get(field, 0.0))
	return deltas


func _item(
	slot: int,
	rarity: int,
	item_level: int,
	stat_id: StringName = &"",
	value: float = 0.0
) -> EquipmentInstance:
	_serial += 1
	var definition := EquipmentDefinition.new()
	definition.definition_id = StringName("r1_fixture_%d" % _serial)
	definition.slot = slot
	definition.rarity = rarity
	definition.item_level = item_level
	definition.display_name = "Fixture %d" % _serial
	var instance := EquipmentInstance.new()
	instance.instance_id = definition.definition_id
	instance.definition = definition
	if stat_id != &"":
		var affix := EquipmentAffix.new()
		affix.stat_id = stat_id
		affix.value = value
		affix.is_percentage = EquipmentAffix.is_percentage_stat(stat_id)
		affix.display_name = EquipmentAffix.get_display_name_for_stat(stat_id)
		instance.affixes.append(affix)
	return instance


## The same item again under a new identity, so one loadout can be built in two orders without
## either inventory owning the other's instance.
func _mirror(item: EquipmentInstance) -> EquipmentInstance:
	var copy: EquipmentInstance = _item(
		item.get_slot(),
		item.get_rarity(),
		item.get_item_level(),
		item.affixes[0].stat_id if not item.affixes.is_empty() else &"",
		item.affixes[0].value if not item.affixes.is_empty() else 0.0
	)
	return copy


func _player(level: int, inventory: EquipmentInventory) -> PlayerController:
	var player := PlayerController.new()
	player.player_progression.level = level
	player.set_equipment_inventory(inventory)
	return player


func _snapshot(stats: PlayerStats) -> Dictionary:
	return {
		"max_hp": stats.max_hp,
		"current_hp": stats.current_hp,
		"attack": stats.attack,
		"defense": stats.defense,
		"critical_chance": stats.critical_chance,
		"critical_damage": stats.critical_damage,
		"dodge": stats.dodge,
		"life_steal": stats.life_steal,
		"stun_chance": stats.stun_chance,
		"damage_vs_elite": stats.damage_vs_elite,
		"damage_vs_boss": stats.damage_vs_boss,
		"movement_points": stats.movement_points,
		"attack_range": stats.attack_range,
	}


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(description)
	if _reported < MAX_REPORTED_ROWS:
		_reported += 1
		push_error(description)


func _close(value: float, expected: float, tolerance: float) -> bool:
	return absf(value - expected) <= tolerance


func _report() -> void:
	if _failures.is_empty():
		print("Balance aggregation smoke test passed (%d checks)." % _checks)
		quit(0)
		return
	print("Balance aggregation smoke test FAILED: %d of %d checks." % [_failures.size(), _checks])
	quit(1)
