class_name EconomyConfig
extends Resource

## Every tunable of the item economy (gameplay-spec §19).
##
## One place only: shop, vendor and UI code consume these values and never restate them.
## The derived getters exist so the spec's calibration targets are COMPUTED from the same
## tables the game rolls from, instead of being copied a second time.
##
## Economic values are not combat values. Nothing here may feed damage, HP, defense or the
## Power Score (`EquipmentInstance.get_equipment_score()`): the Power Score answers "is
## this better in combat?", the economic value answers "what is this worth in gold?".

## Gold value of a fresh common, level-1, affix-less item. DERIVED, not chosen: it is
## solved from the target sell share at the calibration stage, so selling stays a
## secondary income source (~15 % of gold income in steady state). See spec §19,
## "BaseItemValue is derived, not authored".
@export_range(0.0, 10000.0, 1.0) var base_item_value: float = 32.0

## The same role for consumables (potions). A potion carries no affix, so its value is
## `base_potion_value × level × rarity`. Set at ~70 % of a common item of the same level:
## a potion is a usable combat resource, so it sells for less than the equipment it
## replaced in the same drop roll — but never for nothing.
@export_range(0.0, 10000.0, 1.0) var base_potion_value: float = 25.0

## Vendor purchase price = `EconomicValue × this`. Well above the sell multiplier by
## design: buying power must never be cheaper than the loot loop that grants it.
@export_range(0.0, 100.0, 0.1) var vendor_buy_multiplier: float = 4.0

## Sell price before the windfall cap.
@export_range(0.0, 1.0, 0.01) var vendor_sell_multiplier: float = 0.25

## `WindfallCap = this × StageExpectedSell`. DERIVED, not chosen: it must exceed the most
## valuable in-band item (Mythic × the highest in-band level offset) divided by the stage
## mean, which is ≈ 45, so that no item at the stage — or up to 3 levels above it — is ever
## clipped. The cap clips windfalls; it is not an inflation control (see spec §19).
@export_range(0.0, 500.0, 1.0) var windfall_cap_multiplier: float = 50.0

## Item level → value growth. Must stay equal to the gold curve (§10), otherwise selling's
## share of income stops being stage-flat.
@export_range(1.0, 2.0, 0.01) var level_growth_rate: float = 1.18

## `AffixMultiplier = clamp(1 + scale × Σ(roll ratio × economic weight), min, max)`.
@export_range(0.0, 1.0, 0.01) var affix_value_scale: float = 0.15
@export_range(1.0, 10.0, 0.1) var affix_multiplier_min: float = 1.0
@export_range(1.0, 10.0, 0.1) var affix_multiplier_max: float = 3.0

## Economic rarity multipliers, indexed by `EquipmentRarity`. Economic only — they must
## never be reused as combat-power multipliers.
@export var rarity_multipliers: Array[float] = [1.0, 1.5, 3.0, 7.0, 15.0, 35.0]

## Per-slot economic weights, indexed by `EquipmentSlot`. All 1.0 in v1: the table exists
## so a slot can diverge later without changing the formula.
@export var slot_value_weights: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]

## The drop-rarity distribution used ONLY to derive the calibration means below. It must
## match §13's normal-enemy weights (Common/Uncommon/Rare/Epic/Legendary/Mythic).
@export var calibration_rarity_weights: Array[float] = [0.60, 0.25, 0.10, 0.04, 0.01, 0.0]

## The mean roll ratio of a rolled affix: `random(0.80 .. 1.20)` is uniform, so half of the
## band is the expectation. Used only for the calibration means.
const MEAN_ROLL_RATIO: float = 0.5


func get_rarity_multiplier(rarity: int) -> float:
	if rarity < 0 or rarity >= rarity_multipliers.size():
		return 1.0
	return rarity_multipliers[rarity]


func get_slot_value_weight(slot: int) -> float:
	if slot < 0 or slot >= slot_value_weights.size():
		return 1.0
	return slot_value_weights[slot]


## `E[rarity multiplier]` over the calibration distribution — 1.705 with the defaults.
## The reference a stage's expected sale is measured against.
func get_rarity_mean_multiplier() -> float:
	var total: float = 0.0
	var count: int = mini(calibration_rarity_weights.size(), rarity_multipliers.size())
	for rarity in range(count):
		total += calibration_rarity_weights[rarity] * rarity_multipliers[rarity]
	return total


## `E[affix multiplier]` over the calibration distribution — 1.183 with the defaults.
## Rarity decides how many affixes an item rolls (`EquipmentRarity.affix_count`), so this
## is derived from that table rather than assumed.
func get_affix_mean_multiplier() -> float:
	var mean_count: float = 0.0
	for rarity in range(calibration_rarity_weights.size()):
		mean_count += calibration_rarity_weights[rarity] * float(EquipmentRarity.affix_count(rarity))
	return 1.0 + affix_value_scale * mean_count * EquipmentAffix.get_economic_weight_mean() * MEAN_ROLL_RATIO
