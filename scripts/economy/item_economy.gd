class_name ItemEconomy
extends RefCounted

## The item gold value model (gameplay-spec §19): what an item is worth, what a vendor
## charges for it, and what selling it pays.
##
## Pure and static — no scene tree, no signals, no state. Prices are recomputed from the
## item on every call and never stored, so retuning `EconomyConfig` cannot leave an item
## carrying a stale price. The only persisted economy input is `EquipmentAffix.roll_ratio`,
## which is item data rather than a price.
##
## `EconomicValue` is NOT the Power Score (`EquipmentInstance.get_equipment_score()`) and
## no price may ever be derived from it. The two answer different questions: "is this
## better in combat?" versus "what is this worth in gold?".

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


## `1.18^(item_level - 1)`: the same growth the gold curve uses, which is what keeps
## selling's share of income stage-flat.
static func get_level_multiplier(item_level: int, config: EconomyConfig = null) -> float:
	var resolved: EconomyConfig = _resolve(config)
	return pow(resolved.level_growth_rate, float(maxi(item_level, 1) - 1))


## `clamp(1 + scale × Σ(roll ratio × economic weight), min, max)`. An item with no affixes
## (every consumable, and any definition without authored affixes) lands on the floor.
static func get_affix_multiplier(item: EquipmentInstance, config: EconomyConfig = null) -> float:
	var resolved: EconomyConfig = _resolve(config)
	var total: float = 0.0
	if item != null:
		for affix in item.affixes:
			if affix == null:
				continue
			total += clampf(affix.roll_ratio, 0.0, 1.0) * EquipmentAffix.get_economic_weight(affix.stat_id)
	return clampf(
		1.0 + resolved.affix_value_scale * total,
		resolved.affix_multiplier_min,
		resolved.affix_multiplier_max
	)


## The gold value of one item — the single formula behind every price below.
static func get_economic_value(item: EquipmentInstance, config: EconomyConfig = null) -> float:
	var resolved: EconomyConfig = _resolve(config)
	if item == null or item.definition == null:
		return 0.0
	var base_value: float = resolved.base_potion_value if item.is_consumable() else resolved.base_item_value
	var slot_weight: float = 1.0 if item.is_consumable() else resolved.get_slot_value_weight(item.get_slot())
	var level_multiplier: float = get_level_multiplier(item.get_item_level(), resolved)
	var rarity_multiplier: float = resolved.get_rarity_multiplier(item.get_rarity())
	var affix_multiplier: float = get_affix_multiplier(item, resolved)
	return base_value * level_multiplier * rarity_multiplier * slot_weight * affix_multiplier


## What selling the item pays before the windfall cap.
static func get_raw_sell_price(item: EquipmentInstance, config: EconomyConfig = null) -> float:
	var resolved: EconomyConfig = _resolve(config)
	return get_economic_value(item, resolved) * resolved.vendor_sell_multiplier


## What one average equipment drop of `stage` is worth when sold. The reference the
## windfall cap is measured against.
static func get_stage_expected_sell(stage: int, config: EconomyConfig = null) -> float:
	var resolved: EconomyConfig = _resolve(config)
	var level_multiplier: float = get_level_multiplier(stage, resolved)
	return resolved.base_item_value \
		* level_multiplier \
		* resolved.get_rarity_mean_multiplier() \
		* resolved.get_affix_mean_multiplier() \
		* resolved.vendor_sell_multiplier


## The most a single sale may pay at `stage`. Large enough that every item at the stage —
## or up to the §9 level offset of +3 above it — is paid in full; only genuine windfalls
## are clipped.
static func get_windfall_cap(stage: int, config: EconomyConfig = null) -> float:
	var resolved: EconomyConfig = _resolve(config)
	return resolved.windfall_cap_multiplier * get_stage_expected_sell(stage, resolved)


## What selling `item` pays at `stage`: `floor(min(RawSellPrice, WindfallCap))`, at least
## 1 gold so that no sellable item is ever worthless.
static func get_sell_price(item: EquipmentInstance, stage: int, config: EconomyConfig = null) -> int:
	var resolved: EconomyConfig = _resolve(config)
	var raw: float = get_raw_sell_price(item, resolved)
	return maxi(1, floori(minf(raw, get_windfall_cap(stage, resolved))))


## What a vendor charges for `item`. Structurally above the sell price for every input
## (`0.25 × value < 4.0 × value`), so buy/sell arbitrage is impossible by construction.
static func get_buy_price(item: EquipmentInstance, stage: int, config: EconomyConfig = null) -> int:
	var resolved: EconomyConfig = _resolve(config)
	var value: float = get_economic_value(item, resolved)
	var price: int = maxi(1, floori(value * resolved.vendor_buy_multiplier))
	return maxi(price, get_sell_price(item, stage, resolved) + 1)


## Thousands-separated gold text. Lives here so every price surface renders the same number
## the same way — the button, the shop row and the sale message never disagree.
static func format_gold(value: int) -> String:
	var text_value: String = str(maxi(value, 0))
	var formatted: String = ""
	while text_value.length() > 3:
		formatted = "," + text_value.substr(text_value.length() - 3, 3) + formatted
		text_value = text_value.substr(0, text_value.length() - 3)
	return text_value + formatted
