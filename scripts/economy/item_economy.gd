class_name ItemEconomy
extends RefCounted

## The item gold value model (§6.1): what an item is worth, what a vendor charges for it, and what
## selling it pays.
##
## Pure and static — no scene tree, no signals, no state. Prices are recomputed from the item on
## every call and never stored, so retuning the profile cannot leave an item carrying a stale
## price. The only persisted economy input is `EquipmentAffix.roll_ratio`, which is item data
## rather than a price.
##
## `EconomicValue` is NOT the Power Score (`EquipmentInstance.get_equipment_score()`) and no price
## may ever be derived from it. The two answer different questions: "is this better in combat?"
## versus "what is this worth in gold?".
##
## R2 moved the level curve onto the shared `G(il)` scale and replaced the windfall cap's two
## separately-averaged means with the §6.1 JOINT expectation: rarity decides both the rarity
## multiplier AND the affix count, so `E[Rarity] * E[Affix]` misprices the catalogue.

static var _default_config: EconomyConfig = null


## The shared tuning instance. A caller may pass its own config instead.
static func get_default_config() -> EconomyConfig:
	if _default_config == null:
		_default_config = EconomyConfig.new()
	return _default_config


static func _resolve(config: EconomyConfig) -> EconomyConfig:
	if config != null:
		return config
	return get_default_config()


static func _resolve_profile(profile: BalanceProfile) -> BalanceProfile:
	return profile if profile != null else BalanceProfile.get_default()


## §6.1 `item_level_multiplier = G(il)`: prices share the ONE scale with the gold curve, instead
## of the legacy `1.18^(il-1)` that drifted away from it.
static func get_level_multiplier(item_level: int, profile: BalanceProfile = null) -> float:
	return BalanceFormulas.item_level_multiplier(_resolve_profile(profile), maxi(item_level, 1))


## The rarity multipliers of the profile's own economy table are supplied by [EconomyConfig]; the
## §6.1 joint expectation needs them as a plain column.
static func get_rarity_multiplier_column(config: EconomyConfig) -> Array[float]:
	var result: Array[float] = []
	for rarity in range(config.rarity_multipliers.size()):
		result.append(config.get_rarity_multiplier(rarity))
	return result


## The catalogue's economic weight column, in catalogue order — the same order
## `EquipmentAffix.get_economic_weight` answers for `EquipmentAffix.get_stat_ids()`.
static func get_economic_weight_column() -> Array[float]:
	var result: Array[float] = []
	for stat_id in EquipmentAffix.get_stat_ids():
		result.append(EquipmentAffix.get_economic_weight(stat_id))
	return result


## `clamp(1 + scale * SUM(roll_ratio * economic_weight), min, max)`. An item with no affixes
## (every consumable, and any definition without authored affixes) lands on the floor.
static func get_affix_multiplier(
	item: EquipmentInstance,
	config: EconomyConfig = null,
	profile: BalanceProfile = null
) -> float:
	var resolved: EconomyConfig = _resolve(config)
	var resolved_profile: BalanceProfile = _resolve_profile(profile)
	var total: float = 0.0
	if item != null:
		for affix in item.affixes:
			if affix == null:
				continue
			total += clampf(affix.roll_ratio, 0.0, 1.0) * EquipmentAffix.get_economic_weight(affix.stat_id)
	return clampf(
		1.0 + resolved.affix_value_scale * total,
		resolved_profile.affix_multiplier_min,
		resolved_profile.affix_multiplier_max
	)


## The gold value of one item — the single formula behind every price below:
## `base * G(il) * rarity * slot * affix`.
static func get_economic_value(
	item: EquipmentInstance,
	config: EconomyConfig = null,
	profile: BalanceProfile = null
) -> float:
	var resolved: EconomyConfig = _resolve(config)
	if item == null or item.definition == null:
		return 0.0
	var base_value: float = resolved.base_potion_value if item.is_consumable() else resolved.base_item_value
	var slot_weight: float = 1.0 if item.is_consumable() else resolved.get_slot_value_weight(item.get_slot())
	var level_multiplier: float = get_level_multiplier(item.get_item_level(), profile)
	var rarity_multiplier: float = resolved.get_rarity_multiplier(item.get_rarity())
	var affix_multiplier: float = get_affix_multiplier(item, resolved, profile)
	return base_value * level_multiplier * rarity_multiplier * slot_weight * affix_multiplier


## What selling the item pays before the cap.
static func get_raw_sell_price(
	item: EquipmentInstance,
	config: EconomyConfig = null,
	profile: BalanceProfile = null
) -> float:
	var resolved: EconomyConfig = _resolve(config)
	return get_economic_value(item, resolved, profile) * resolved.vendor_sell_multiplier


## §6.1 `StageExpectedSell = 30 * G(S) * E[RarityMultiplier * AffixMultiplier] * 0.25`: what one
## average equipment drop of `stage` is worth when sold. The joint expectation is ENUMERATED from
## the catalogue (see [method BalanceFormulas.mean_rarity_affix_multiplier]) rather than sampled,
## so the value is exact for these finite tables.
static func get_stage_expected_sell(
	stage: int,
	config: EconomyConfig = null,
	profile: BalanceProfile = null
) -> float:
	var resolved: EconomyConfig = _resolve(config)
	var resolved_profile: BalanceProfile = _resolve_profile(profile)
	var level_multiplier: float = get_level_multiplier(stage, resolved_profile)
	var joint: float = BalanceFormulas.mean_rarity_affix_multiplier(
		resolved_profile,
		get_rarity_multiplier_column(resolved),
		get_economic_weight_column()
	)
	return resolved.base_item_value \
		* level_multiplier \
		* joint \
		* resolved.vendor_sell_multiplier


## §6.1 `SellCap = sell_cap_stages * StageExpectedSell`. It clips genuine windfalls — an item far
## above the stage's own band — and is never the reason an in-band item is underpaid.
static func get_sell_cap(
	stage: int,
	config: EconomyConfig = null,
	profile: BalanceProfile = null
) -> float:
	var resolved: EconomyConfig = _resolve(config)
	return _resolve_profile(profile).sell_cap_stages * get_stage_expected_sell(stage, resolved, profile)


## §6.1 `Sell = max(1, floor(min(Value * 0.25, 100 * StageExpectedSell)))`. `stage` is the CURRENT
## legal stage, so returning to a low stage caps sales lower instead of re-pricing the item onto
## the new curve.
static func get_sell_price(
	item: EquipmentInstance,
	stage: int,
	config: EconomyConfig = null,
	profile: BalanceProfile = null
) -> int:
	var resolved: EconomyConfig = _resolve(config)
	var raw: float = get_raw_sell_price(item, resolved, profile)
	return maxi(1, floori(minf(raw, get_sell_cap(stage, resolved, profile))))


## §6.1 `Buy = max(floor(Value * 4), Sell + 1, 1)`. Structurally above the sell price for every
## input, so buy/sell arbitrage is impossible by construction.
static func get_buy_price(
	item: EquipmentInstance,
	stage: int,
	config: EconomyConfig = null,
	profile: BalanceProfile = null
) -> int:
	var resolved: EconomyConfig = _resolve(config)
	var value: float = get_economic_value(item, resolved, profile)
	var price: int = maxi(1, floori(value * resolved.vendor_buy_multiplier))
	return maxi(price, get_sell_price(item, stage, resolved, profile) + 1)


## Thousands-separated gold text. Lives here so every price surface renders the same number
## the same way — the button, the shop row and the sale message never disagree.
static func format_gold(value: int) -> String:
	var text_value: String = str(maxi(value, 0))
	var formatted: String = ""
	while text_value.length() > 3:
		formatted = "," + text_value.substr(text_value.length() - 3, 3) + formatted
		text_value = text_value.substr(0, text_value.length() - 3)
	return text_value + formatted
