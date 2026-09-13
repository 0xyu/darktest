extends SceneTree

## Item economy smoke test (gameplay-spec §19).
## Run headless:
##   godot --headless --path . -s res://tests/economy_smoke_test.gd
##
## Verifies:
##   * EconomicValue is monotonic in item level, rarity and affix roll ratio
##   * no buy/sell arbitrage exists for any item
##   * the windfall cap never clips an in-band item, and does clip a windfall
##   * every sellable item is worth at least 1 gold
##   * the sell share of gold income lands in the calibrated band and stays flat
##   * EconomicValue is NOT the Power Score: combat stat size does not move the price
##   * a potion is priced below the equipment it replaced in the same drop roll

const CALIBRATION_STAGES: Array[int] = [1, 4, 7, 10, 50, 100, 200]
const PROFILE_PATH: String = BalanceProfile.DEFAULT_PROFILE_PATH

## The §9/§10/§13 inputs the calibration table is derived from. They mirror the spec on
## purpose — this assertion IS the tripwire that fires when the income side changes without
## the economy being recalibrated against it.
const CALIBRATION_DROP_CHANCE: float = 0.25
const CALIBRATION_EQUIPMENT_SHARE: float = 0.85
const CALIBRATION_BASE_STAGE_GOLD: float = 50.0
const CALIBRATION_ENEMY_GOLD: float = 10.0
const CALIBRATION_BASE_ENEMY_COUNT: int = 1
const CALIBRATION_COUNT_INTERVAL: int = 3
const CALIBRATION_MAX_ENEMY_COUNT: int = 4

## The target band the spec calibrates to. The ramp starts at 5.7 % (stage 1, a single
## enemy per clear) and reaches ≈ 15 % in steady state.
const TARGET_SELL_SHARE_MIN: float = 0.05
const TARGET_SELL_SHARE_MAX: float = 0.17

## The §9 in-band enemy level offset. A dropped item is `max(enemy_level, stage)`, so any
## item up to this many levels above the stage must still be paid in full.
const IN_BAND_LEVEL_OFFSET: int = 3

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_level_monotonicity()
	_test_rarity_monotonicity()
	_test_roll_ratio_monotonicity()
	_test_value_is_not_the_power_score()
	_test_no_arbitrage()
	_test_no_in_band_clipping()
	_test_windfall_is_clipped()
	_test_joint_expectation()
	_test_prices_use_the_shared_scale()
	_test_price_order()
	_test_cap_bound()
	_test_minimum_one_gold()
	_test_potion_pricing()
	_test_calibration_band()

	if _failures.is_empty():
		print("Item economy smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_level_monotonicity() -> void:
	var stage: int = 50
	var previous: float = -1.0
	for level: int in [1, 5, 10, 25, 50]:
		var item := UIFixture.create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, level)
		var value: float = ItemEconomy.get_economic_value(item)
		_expect(value > previous, "value rises with item level (level %d)" % level)
		_expect(
			ItemEconomy.get_sell_price(item, stage) > 0,
			"a level-%d item sells for gold" % level
		)
		previous = value


func _test_rarity_monotonicity() -> void:
	var stage: int = 50
	var previous: float = -1.0
	for rarity: int in [
		EquipmentRarity.COMMON,
		EquipmentRarity.UNCOMMON,
		EquipmentRarity.RARE,
		EquipmentRarity.EPIC,
		EquipmentRarity.LEGENDARY,
		EquipmentRarity.MYTHIC,
	]:
		var item := UIFixture.create_equipment(rarity, EquipmentSlot.WEAPON, 10)
		var value: float = ItemEconomy.get_economic_value(item)
		_expect(value > previous, "value rises with rarity index %d" % rarity)
		previous = value


func _test_roll_ratio_monotonicity() -> void:
	var stage: int = 10
	var worst: EquipmentInstance = _item_with_roll(0.0)
	var middle: EquipmentInstance = _item_with_roll(0.5)
	var best: EquipmentInstance = _item_with_roll(1.0)
	var worst_value: float = ItemEconomy.get_economic_value(worst)
	var middle_value: float = ItemEconomy.get_economic_value(middle)
	var best_value: float = ItemEconomy.get_economic_value(best)
	_expect(
		worst_value < middle_value and middle_value < best_value,
		"a high roll is worth more than a low roll (%f / %f / %f)" % [worst_value, middle_value, best_value]
	)
	_expect(
		ItemEconomy.get_affix_multiplier(worst) == 1.0,
		"the worst roll sits on the affix multiplier floor"
	)
	_expect(
		ItemEconomy.get_affix_multiplier(middle) > 1.0,
		"a neutral roll is above the floor"
	)


func _test_value_is_not_the_power_score() -> void:
	# Two items with identical economic inputs but wildly different combat stats. The
	# economic value must not move: the Power Score answers "better in combat?", the price
	# answers "worth in gold?" (gameplay-spec §19).
	var cheap := _item_with_affix_value(1.0)
	var strong := _item_with_affix_value(1000.0)
	_expect(
		is_equal_approx(
			ItemEconomy.get_economic_value(cheap),
			ItemEconomy.get_economic_value(strong)
		),
		"affix magnitude does not change the economic value"
	)
	_expect(
		strong.get_equipment_score() > cheap.get_equipment_score(),
		"the two items really do differ in Power Score"
	)
	_expect(
		ItemEconomy.get_sell_price(cheap, 10) == ItemEconomy.get_sell_price(strong, 10),
		"affix magnitude does not change the sell price"
	)


func _test_no_arbitrage() -> void:
	for stage: int in [1, 10, 100]:
		for rarity: int in [
			EquipmentRarity.COMMON,
			EquipmentRarity.UNCOMMON,
			EquipmentRarity.RARE,
			EquipmentRarity.EPIC,
			EquipmentRarity.LEGENDARY,
			EquipmentRarity.MYTHIC,
		]:
			for level: int in [1, stage, stage + IN_BAND_LEVEL_OFFSET, stage + 40]:
				var item := UIFixture.create_equipment(rarity, EquipmentSlot.WEAPON, maxi(level, 1))
				var sell: int = ItemEconomy.get_sell_price(item, stage)
				var buy: int = ItemEconomy.get_buy_price(item, stage)
				_expect(
					sell < buy,
					"selling always pays less than buying back (stage %d, rarity %d, level %d: %d < %d)"
						% [stage, rarity, level, sell, buy]
				)


func _test_no_in_band_clipping() -> void:
	for stage: int in [1, 10, 100, 500]:
		for rarity: int in [EquipmentRarity.COMMON, EquipmentRarity.LEGENDARY, EquipmentRarity.MYTHIC]:
			for offset: int in range(0, IN_BAND_LEVEL_OFFSET + 1):
				var item := UIFixture.create_equipment(rarity, EquipmentSlot.WEAPON, stage + offset)
				var raw: float = ItemEconomy.get_raw_sell_price(item)
				var paid: int = ItemEconomy.get_sell_price(item, stage)
				_expect(
					paid == maxi(1, floori(raw)),
					"an in-band item is paid in full (stage %d, rarity %d, +%d)" % [stage, rarity, offset]
				)


func _test_windfall_is_clipped() -> void:
	var stage: int = 10
	var item := UIFixture.create_equipment(EquipmentRarity.MYTHIC, EquipmentSlot.WEAPON, stage + 40)
	var raw: float = ItemEconomy.get_raw_sell_price(item)
	var cap: float = ItemEconomy.get_sell_cap(stage)
	_expect(raw > cap, "the windfall really is above the cap")
	_expect(
		ItemEconomy.get_sell_price(item, stage) == floori(cap),
		"a windfall is clipped to the cap"
	)


## §6.1: the §6.1 expected sale is a JOINT expectation `E[RarityMultiplier * AffixMultiplier]` over
## the catalogue, computed by enumeration. Multiplying the two means separately (the legacy
## `1.705 * 1.190`) understates it, because rarity decides the affix COUNT as well as the
## multiplier. The value is asserted against the production enumeration, not a copied constant.
func _test_joint_expectation() -> void:
	var profile := load(PROFILE_PATH) as BalanceProfile
	var config: EconomyConfig = ItemEconomy.get_default_config()
	var rarity_column: Array[float] = ItemEconomy.get_rarity_multiplier_column(config)
	var economic_weights: Array[float] = ItemEconomy.get_economic_weight_column()
	var joint: float = BalanceFormulas.mean_rarity_affix_multiplier(profile, rarity_column, economic_weights)
	_expect(joint > 0.0, "the joint expectation is a positive number, got %f" % joint)
	# The legacy approximation is the product of the two separately-averaged means.
	var rarity_mean: float = 0.0
	for rarity in range(mini(profile.calibration_rarity_weights.size(), rarity_column.size())):
		rarity_mean += profile.calibration_rarity_weights[rarity] * rarity_column[rarity]
	var affix_mean: float = 0.0
	for rarity in range(mini(profile.calibration_rarity_weights.size(), rarity_column.size())):
		affix_mean += profile.calibration_rarity_weights[rarity] \
			* BalanceFormulas.mean_affix_multiplier(profile, economic_weights, EquipmentRarity.affix_count(rarity))
	_expect(
		absf(joint - rarity_mean * affix_mean) > 0.0001,
		"the joint expectation is not the product of the two means (%.6f vs %.6f)" % [joint, rarity_mean * affix_mean]
	)
	# An INDEPENDENT enumeration of the same quantity, written out here so a change to the
	# production dynamic program has to disagree with this test instead of moving with it: every
	# weighted-without-replacement draw of `affix_count` economics weights, clamped per draw.
	var enumerated: float = 0.0
	for rarity in range(mini(profile.calibration_rarity_weights.size(), rarity_column.size())):
		var probability: float = profile.calibration_rarity_weights[rarity]
		if is_zero_approx(probability):
			continue
		enumerated += probability * rarity_column[rarity] \
			* _enumerate_affix_mean(profile, economic_weights, EquipmentRarity.affix_count(rarity))
	_expect(
		absf(joint - enumerated) < 0.000001,
		"the production joint expectation matches an independent enumeration (%.9f vs %.9f)" % [joint, enumerated]
	)
	# The affix multiplier is clamped at its ceiling, so the joint mean is well below the cap.
	_expect(
		joint <= profile.affix_multiplier_max * rarity_mean + 0.0001,
		"the joint mean respects the affix multiplier ceiling"
	)
	# §6.1: every count's mean must be at least the floor and never above the ceiling.
	for count in range(1, 6):
		var mean: float = BalanceFormulas.mean_affix_multiplier(profile, economic_weights, count)
		_expect(
			mean >= profile.affix_multiplier_min - 0.0001 and mean <= profile.affix_multiplier_max + 0.0001,
			"a %d-affix mean stays inside the clamp band (%.4f)" % [count, mean]
		)


## §6.1: prices ride `G(il)`, so the item-level ratio between two items is exactly the `G` ratio —
## the legacy `1.18^(il-1)` curve is gone.
func _test_prices_use_the_shared_scale() -> void:
	var profile := load(PROFILE_PATH) as BalanceProfile
	var low := UIFixture.create_equipment(EquipmentRarity.COMMON, EquipmentSlot.WEAPON, 1)
	var high := UIFixture.create_equipment(EquipmentRarity.COMMON, EquipmentSlot.WEAPON, 11)
	var expected_ratio: float = BalanceFormulas.g(profile, 11.0) / BalanceFormulas.g(profile, 1.0)
	var low_definition: EquipmentDefinition = low.definition
	var high_definition: EquipmentDefinition = high.definition
	_expect(
		high_definition.item_level == 11 and low_definition.item_level == 1,
		"the fixture really holds il 11 and il 1 (got %d and %d)" % [high_definition.item_level, low_definition.item_level]
	)
	_expect(
		ItemEconomy.get_level_multiplier(11) == BalanceFormulas.g(profile, 11.0),
		"the level multiplier IS G(il): %.6f vs %.6f" % [ItemEconomy.get_level_multiplier(11), BalanceFormulas.g(profile, 11.0)]
	)
	var actual_ratio: float = ItemEconomy.get_economic_value(high) / ItemEconomy.get_economic_value(low)
	_expect(
		absf(actual_ratio - expected_ratio) < 0.0001,
		"value grows as G(il): ratio %.6f vs %.6f" % [actual_ratio, expected_ratio]
	)


## §6.1: the release order of the price rules for every input in the matrix.
func _test_price_order() -> void:
	for stage: int in [1, 10, 100, 1000]:
		for rarity: int in [EquipmentRarity.COMMON, EquipmentRarity.LEGENDARY, EquipmentRarity.MYTHIC]:
			for level: int in [1, stage, stage + 3, stage + 40]:
				var item := UIFixture.create_equipment(rarity, EquipmentSlot.WEAPON, maxi(level, 1))
				var sell: int = ItemEconomy.get_sell_price(item, stage)
				var buy: int = ItemEconomy.get_buy_price(item, stage)
				_expect(sell >= 1, "a sell price is at least 1 gold (stage %d, rarity %d, level %d)" % [stage, rarity, level])
				_expect(
					buy >= floori(ItemEconomy.get_economic_value(item) * 4.0),
					"buy is at least 4x the value (stage %d, rarity %d, level %d)" % [stage, rarity, level]
				)
				_expect(
					buy >= sell + 1,
					"buy never undercuts selling (stage %d, rarity %d, level %d: %d vs %d)" % [stage, rarity, level, buy, sell]
				)
	# Prices are monotonic inside one stage: same rarity, rising item level.
	for stage: int in [10, 100, 1000]:
		var previous_buy: int = 0
		var previous_sell: int = 0
		for offset: int in range(0, 4):
			var item := UIFixture.create_equipment(EquipmentRarity.RARE, EquipmentSlot.HELMET, stage + offset)
			var buy: int = ItemEconomy.get_buy_price(item, stage)
			var sell: int = ItemEconomy.get_sell_price(item, stage)
			_expect(buy > previous_buy, "buy rises with item level at stage %d (+%d)" % [stage, offset])
			_expect(sell >= previous_sell, "sell never falls as item level rises at stage %d (+%d)" % [stage, offset])
			previous_buy = buy
			previous_sell = sell


## §6.1: the cap must not clip the highest-roll item of the stage's own band. With the affix
## multiplier bounded by the profile and the level offset +3 taken into account, `SellCap` is
## `sell_cap_stages` times the stage mean, and the contract's conservative bound is
## `sell_cap_stages >= 35 * max_affix_multiplier * G(4) / joint_mean`.
func _test_cap_bound() -> void:
	var profile := load(PROFILE_PATH) as BalanceProfile
	var config: EconomyConfig = ItemEconomy.get_default_config()
	var joint: float = BalanceFormulas.mean_rarity_affix_multiplier(
		profile,
		ItemEconomy.get_rarity_multiplier_column(config),
		ItemEconomy.get_economic_weight_column()
	)
	var highest_rarity: float = config.get_rarity_multiplier(EquipmentRarity.MYTHIC)
	var level_offset_ratio: float = BalanceFormulas.g(profile, 4.0) / BalanceFormulas.g(profile, 1.0)
	var bound: float = highest_rarity * profile.affix_multiplier_max * level_offset_ratio / joint
	_expect(
		profile.sell_cap_stages >= bound,
		"the sale cap bound is satisfied: %.3f >= %.3f" % [profile.sell_cap_stages, bound]
	)



func _test_minimum_one_gold() -> void:
	var item := UIFixture.create_equipment(EquipmentRarity.COMMON, EquipmentSlot.RING, 1)
	_expect(ItemEconomy.get_sell_price(item, 1) >= 1, "a level-1 common sells for at least 1 gold")
	var potion := UIFixture.create_potion(1, EquipmentRarity.COMMON)
	_expect(ItemEconomy.get_sell_price(potion, 1) >= 1, "a level-1 potion sells for at least 1 gold")


func _test_potion_pricing() -> void:
	var potion := UIFixture.create_potion(5, EquipmentRarity.UNCOMMON)
	var equipment := UIFixture.create_equipment(EquipmentRarity.UNCOMMON, EquipmentSlot.WEAPON, 5)
	_expect(
		ItemEconomy.get_economic_value(potion) < ItemEconomy.get_economic_value(equipment),
		"a potion is worth less than the equipment it replaced in the same roll"
	)
	_expect(
		ItemEconomy.get_affix_multiplier(potion) == 1.0,
		"a consumable carries no affixes and lands on the multiplier floor"
	)
	_expect(
		ItemEconomy.get_economic_value(UIFixture.create_potion(10, EquipmentRarity.COMMON))
			> ItemEconomy.get_economic_value(UIFixture.create_potion(1, EquipmentRarity.COMMON)),
		"a higher-level potion is worth more"
	)


func _test_calibration_band() -> void:
	var config: EconomyConfig = ItemEconomy.get_default_config()
	for stage: int in CALIBRATION_STAGES:
		var share: float = _sell_share(stage, config)
		_expect(
			share >= TARGET_SELL_SHARE_MIN and share <= TARGET_SELL_SHARE_MAX,
			"the sell share at stage %d is inside the target band (%.1f %%)" % [stage, share * 100.0]
		)
	# The share is stage-flat in steady state: both sides grow as the same curve.
	var steady: float = _sell_share(1000, config)
	_expect(
		absf(steady - _sell_share(100, config)) < 0.001,
		"the sell share stops drifting once the encounter size is capped (%.3f vs %.3f)"
			% [steady, _sell_share(100, config)]
	)


## An INDEPENDENT enumeration of `E[AffixMultiplier]` for one affix count: every ORDERED draw of
## distinct affixes without replacement, weighted by its exact sequential probability, with the clamp
## applied per draw. Written from the definition rather than the production recurrence so the two
## have to agree. `12` affixes choose `5` with order is 95 040 sequences, which is cheap enough to
## enumerate exactly.
func _enumerate_affix_mean(profile: BalanceProfile, weights: Array[float], count: int) -> float:
	var total: float = 0.0
	for weight in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return 0.0
	var draws: int = mini(count, weights.size())
	var sums: Array[float] = []
	_enumerate_sequences(profile, weights, total, draws, 0.0, 0, 1.0, sums)
	var expected: float = 0.0
	for weighted_sum in sums:
		expected += weighted_sum
	return expected


## Accumulates `probability * clamp(multiplier)` over every ordered sequence of `remaining` draws.
## `probability` is the sequential without-replacement weight of the prefix, `sum_weight` the
## economic weight already drawn, and `used_mask` keeps the draws distinct.
func _enumerate_sequences(
	profile: BalanceProfile,
	weights: Array[float],
	total: float,
	remaining: int,
	sum_weight: float,
	used_mask: int,
	probability: float,
	out: Array[float]
) -> void:
	if remaining <= 0 or probability <= 0.0:
		return
	for index in range(weights.size()):
		if used_mask & (1 << index):
			continue
		var weight: float = maxf(weights[index], 0.0)
		var remaining_total: float = total - sum_weight
		if remaining_total <= 0.0:
			continue
		var next_probability: float = probability * weight / remaining_total
		var next_sum: float = sum_weight + weight
		if remaining == 1:
			out.append(next_probability * clampf(
				1.0 + profile.affix_value_scale * profile.mean_roll_ratio * next_sum,
				profile.affix_multiplier_min,
				profile.affix_multiplier_max
			))
		else:
			_enumerate_sequences(
				profile,
				weights,
				total,
				remaining - 1,
				next_sum,
				used_mask | (1 << index),
				next_probability,
				out
			)


func _popcount(mask: int) -> int:
	var count: int = 0
	var value: int = mask
	while value > 0:
		count += value & 1
		value >>= 1
	return count


func _item_with_roll(roll_ratio: float) -> EquipmentInstance:
	var affix := UIFixture.create_affix(&"attack", 5.0)
	affix.roll_ratio = roll_ratio
	var affixes: Array[EquipmentAffix] = [affix]
	return UIFixture.create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, 10, &"", affixes)


func _item_with_affix_value(value: float) -> EquipmentInstance:
	var affix := UIFixture.create_affix(&"attack", value)
	affix.roll_ratio = 0.5
	var affixes: Array[EquipmentAffix] = [affix]
	return UIFixture.create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, 10, &"", affixes)


func _enemy_count(stage: int) -> int:
	var growth_steps: int = int(floor(float(maxi(stage, 1) - 1) / float(CALIBRATION_COUNT_INTERVAL)))
	return clampi(CALIBRATION_BASE_ENEMY_COUNT + growth_steps, 1, CALIBRATION_MAX_ENEMY_COUNT)


func _clear_gold(stage: int, config: EconomyConfig) -> float:
	var level_multiplier: float = ItemEconomy.get_level_multiplier(stage)
	var per_clear: float = CALIBRATION_BASE_STAGE_GOLD + CALIBRATION_ENEMY_GOLD * float(_enemy_count(stage))
	return per_clear * level_multiplier


func _sell_share(stage: int, config: EconomyConfig) -> float:
	var drops: float = float(_enemy_count(stage)) * CALIBRATION_DROP_CHANCE * CALIBRATION_EQUIPMENT_SHARE
	return drops * ItemEconomy.get_stage_expected_sell(stage, config) / _clear_gold(stage, config)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
