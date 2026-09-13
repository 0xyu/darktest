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

## Gold value of a fresh common, level-1, affix-less item. The §6.1 value is 30 (the legacy curve
## used 32): with `G(il)` growth instead of `1.18^(il-1)`, 30 is what keeps a normal equipment
## sale at 5..18 % of the stage's combat Gold.
##
## The AUTHORITATIVE copy of this number is `BalanceProfile.base_item_value`, because the level
## multiplier next to it also comes from the profile; this field remains the config's own value
## for a caller that builds an EconomyConfig outside the profile.
@export_range(0.0, 10000.0, 1.0) var base_item_value: float = 30.0

## The same role for consumables (potions). A potion carries no affix, so its value is
## `base_potion_value × level × rarity`. Set at ~70 % of a common item of the same level:
## a potion is a usable combat resource, so it sells for less than the equipment it
## replaced in the same drop roll — but never for nothing.
@export_range(0.0, 10000.0, 1.0) var base_potion_value: float = 25.0

## Vendor purchase price = `EconomicValue × this`. Well above the sell multiplier by
## design: buying power must never be cheaper than the loot loop that grants it.
@export_range(0.0, 100.0, 0.1) var vendor_buy_multiplier: float = 4.0

## Sell price before the §6.1 cap.
@export_range(0.0, 1.0, 0.01) var vendor_sell_multiplier: float = 0.25

## `SellCap = this * StageExpectedSell` (§6.1). It clips windfalls; it is not an inflation
## control. The behavioural copy lives in `BalanceProfile.sell_cap_stages`, which is the one
## [ItemEconomy] reads, because the expectation next to it is computed from the profile tables.
@export_range(1.0, 1000.0, 1.0) var windfall_cap_stages: float = 100.0

## LEGACY (v3 and earlier): the sale cap as a multiple of the stage's expected sale. Superseded by
## §6.1's `SellCap`, which is the same structure with the corrected multiplier; kept so an old
## `EconomyConfig` resource still loads with the value it was authored with.
@export_range(0.0, 500.0, 1.0) var windfall_cap_multiplier: float = 50.0

## LEGACY (v3 and earlier): item level growth as `rate^(il-1)`. §6.1 replaces it with `G(il)`;
## kept for resource compatibility only — no price reads it any more.
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

## The drop-rarity distribution the §6.1 joint expectation is computed over. It must match §13's
## normal-enemy weights (Common/Uncommon/Rare/Epic/Legendary/Mythic).
##
## The AUTHORITATIVE copy is `BalanceProfile.calibration_rarity_weights`, which is the one every
## price reads — it has to sit beside `mean_roll_ratio` and the affix multiplier bounds that are
## averaged with it. This field stays for a caller that builds a config outside the profile.
@export var calibration_rarity_weights: Array[float] = [0.60, 0.25, 0.10, 0.04, 0.01, 0.0]


func get_rarity_multiplier(rarity: int) -> float:
	if rarity < 0 or rarity >= rarity_multipliers.size():
		return 1.0
	return rarity_multipliers[rarity]


func get_slot_value_weight(slot: int) -> float:
	if slot < 0 or slot >= slot_value_weights.size():
		return 1.0
	return slot_value_weights[slot]
