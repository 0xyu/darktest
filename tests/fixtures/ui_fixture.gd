class_name UIFixture
extends RefCounted

## Deterministic, reusable test fixtures for UI development and agent
## automation (MCP / game_eval).
##
## Builds equipment, inventory, and character data without:
##   - any randomness (no RandomNumberGenerator)
##   - any dependency on a real player save
##   - any change to production gameplay logic
##
## All data reuses the production data model (EquipmentInstance,
## EquipmentDefinition, EquipmentAffix, EquipmentInventory, PlayerStats,
## PlayerProgression). No copy of the equipment system is maintained here.
##
## Usage:
##   var inventory := UIFixture.create_inventory()
##   var item := UIFixture.create_equipment(EquipmentRarity.MYTHIC, EquipmentSlot.RING, 40)
##   var character := UIFixture.create_character(10, 2500, 5)
##   UIFixture.apply_character_to_player(player, character)

## Deterministic unique-id counter so several identical generic items can
## coexist in one inventory. Values are never derived from this counter.
static var _next_instance_id: int = 1

# ---------------------------------------------------------------------------
# Equipment
# ---------------------------------------------------------------------------

## Builds a concrete equipment item. When `affixes` is empty, a deterministic
## set of affixes is generated matching the rarity's affix count, scaled to
## `item_level`/`rarity` using the production median value curve.
static func create_equipment(
	rarity: int = EquipmentRarity.COMMON,
	slot: int = EquipmentSlot.WEAPON,
	item_level: int = 1,
	unique_effect_id: StringName = &"",
	affixes: Array[EquipmentAffix] = []
) -> EquipmentInstance:
	var safe_rarity: int = clampi(rarity, EquipmentRarity.COMMON, EquipmentRarity.MYTHIC)
	var safe_slot: int = slot if EquipmentSlot.is_valid(slot) else EquipmentSlot.WEAPON
	var safe_level: int = maxi(item_level, 1)
	var item := _create_equipment_named(
		"fixture_item_%d" % _next_instance_id,
		safe_rarity,
		safe_slot,
		safe_level,
		unique_effect_id,
		affixes if not affixes.is_empty() else _build_default_affixes(safe_level, safe_rarity)
	)
	_next_instance_id += 1
	return item


## Creates a raw affix with an explicit value. `is_percentage` and
## `display_name` are derived from the production stat tables.
static func create_affix(stat_id: StringName, value: float) -> EquipmentAffix:
	var affix := EquipmentAffix.new()
	affix.stat_id = stat_id
	affix.value = value
	affix.is_percentage = EquipmentAffix.is_percentage_stat(stat_id)
	affix.display_name = EquipmentAffix.get_display_name_for_stat(stat_id)
	return affix


## Creates an affix whose value follows the production median curve for the
## given stat, item level, and rarity (no randomness).
static func create_affix_scaled(
	stat_id: StringName,
	item_level: int = 1,
	rarity: int = EquipmentRarity.COMMON
) -> EquipmentAffix:
	return _create_scaled_affix(stat_id, maxi(item_level, 1), clampi(rarity, EquipmentRarity.COMMON, EquipmentRarity.MYTHIC))


## A deterministic consumable potion. Slot stays invalid (-1) so it can never
## be equipped or matched by slot filtering.
static func create_potion(item_level: int = 1, rarity: int = EquipmentRarity.COMMON) -> EquipmentInstance:
	var safe_level: int = maxi(item_level, 1)
	var safe_rarity: int = clampi(rarity, EquipmentRarity.COMMON, EquipmentRarity.MYTHIC)
	var definition := EquipmentDefinition.new()
	definition.definition_id = StringName("fixture_potion_%d" % _next_instance_id)
	definition.slot = -1
	definition.is_consumable = true
	definition.heal_ratio = 0.35
	definition.rarity = safe_rarity
	definition.item_level = safe_level
	definition.display_name = "生命药水"
	definition.description = "回复最大生命的 35%。"

	var instance := EquipmentInstance.new()
	instance.instance_id = StringName("fixture_potion_%d" % _next_instance_id)
	instance.definition = definition
	instance.affixes = []
	_next_instance_id += 1
	return instance


## A curated one-of-every-rarity set with fixed instance ids: Common, Uncommon,
## Rare, Epic, Legendary (with unique effect), and Mythic (with unique effect).
static func create_rarity_set() -> Array[EquipmentInstance]:
	return [
		_create_equipment_named("fixture_common_weapon", EquipmentRarity.COMMON, EquipmentSlot.WEAPON, 1, &"", []),
		_create_equipment_named("fixture_uncommon_boots", EquipmentRarity.UNCOMMON, EquipmentSlot.BOOTS, 5, &"", []),
		_create_equipment_named("fixture_rare_armor", EquipmentRarity.RARE, EquipmentSlot.ARMOR, 10, &"", []),
		_create_equipment_named("fixture_epic_helmet", EquipmentRarity.EPIC, EquipmentSlot.HELMET, 20, &"", []),
		_create_equipment_named("fixture_legendary_gloves", EquipmentRarity.LEGENDARY, EquipmentSlot.GLOVES, 30, &"every_3rd_attack", []),
		_create_equipment_named("fixture_mythic_ring", EquipmentRarity.MYTHIC, EquipmentSlot.RING, 40, &"critical_healing", []),
	]


# ---------------------------------------------------------------------------
# Inventory
# ---------------------------------------------------------------------------

## A fresh, empty inventory with the default capacity.
static func create_empty_inventory(capacity: int = EquipmentInventory.DEFAULT_CAPACITY) -> EquipmentInventory:
	var inventory := EquipmentInventory.new()
	inventory.capacity = maxi(capacity, 1)
	return inventory


## A fresh, empty warehouse with the default capacity.
static func create_storage(capacity: int = StorageInventory.DEFAULT_CAPACITY) -> StorageInventory:
	var storage := StorageInventory.new()
	storage.capacity = maxi(capacity, 1)
	return storage


## A deterministic demo inventory guaranteed to contain at least one Common,
## Rare, Epic, Legendary, and Mythic item. The Legendary gloves and Mythic
## ring are equipped so both equipped and bag states are visible in UI.
static func create_inventory() -> EquipmentInventory:
	var inventory := create_empty_inventory()
	var rarity_set := create_rarity_set()
	for item in rarity_set:
		inventory.add_item(item)
	inventory.add_item(create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, 12))
	inventory.add_item(create_equipment(EquipmentRarity.EPIC, EquipmentSlot.AMULET, 22))
	inventory.add_item(create_potion(1, EquipmentRarity.COMMON))
	var legendary: EquipmentInstance = _find_item_by_rarity(rarity_set, EquipmentRarity.LEGENDARY)
	var mythic: EquipmentInstance = _find_item_by_rarity(rarity_set, EquipmentRarity.MYTHIC)
	if legendary != null:
		inventory.equip_item(legendary)
	if mythic != null:
		inventory.equip_item(mythic)
	return inventory


# ---------------------------------------------------------------------------
# Character
# ---------------------------------------------------------------------------

## Builds base PlayerStats with optional property overrides.
static func create_player_stats(overrides: Dictionary = {}) -> PlayerStats:
	var stats := PlayerStats.new()
	_apply_overrides(stats, overrides)
	return stats


## Builds progression data with explicit level, gold, and stage.
static func create_player_progression(
	level: int = 1,
	gold: int = 0,
	current_stage: int = 1
) -> PlayerProgression:
	var progression := PlayerProgression.new()
	progression.level = maxi(level, 1)
	progression.gold = maxi(gold, 0)
	progression.current_stage = maxi(current_stage, 1)
	return progression


## Builds a complete character bundle:
##   { stats: PlayerStats, progression: PlayerProgression, inventory: EquipmentInventory }
## Stats scale with level so higher-level fixtures look like a real character.
static func create_character(
	level: int = 10,
	gold: int = 2500,
	current_stage: int = 5
) -> Dictionary:
	var safe_level: int = maxi(level, 1)
	var stats := create_player_stats({
		"max_hp": 100 + (safe_level - 1) * 20,
		"attack": 10 + (safe_level - 1) * 2,
		"defense": 5 + (safe_level - 1),
	})
	var progression := create_player_progression(safe_level, gold, current_stage)
	return {
		"stats": stats,
		"progression": progression,
		"inventory": create_inventory(),
	}


## Wires a character bundle onto a live PlayerController using public APIs.
## Safe to call on a player that already had equipment: prior equipment
## bonuses are cleared before the fixture stats and inventory are applied.
static func apply_character_to_player(player: PlayerController, character: Dictionary = {}) -> void:
	if player == null:
		return
	var bundle: Dictionary = character if not character.is_empty() else create_character()
	var fixture_stats: PlayerStats = bundle.get("stats") as PlayerStats
	if fixture_stats == null:
		fixture_stats = create_player_stats()
	var fixture_progression: PlayerProgression = bundle.get("progression") as PlayerProgression
	if fixture_progression == null:
		fixture_progression = create_player_progression()
	var fixture_inventory: EquipmentInventory = bundle.get("inventory") as EquipmentInventory
	if fixture_inventory == null:
		fixture_inventory = create_inventory()

	# Clear any equipment bonuses the player may have applied from a prior
	# inventory before swapping in fresh fixture data.
	player.set_equipment_inventory(create_empty_inventory())
	player.player_stats = fixture_stats
	player.player_progression = fixture_progression
	player.set_equipment_inventory(fixture_inventory)


# ---------------------------------------------------------------------------
# Internals (deterministic, no RNG)
# ---------------------------------------------------------------------------

static func _create_equipment_named(
	base_id: String,
	rarity: int,
	slot: int,
	item_level: int,
	unique_effect_id: StringName,
	affixes: Array[EquipmentAffix]
) -> EquipmentInstance:
	var definition := EquipmentDefinition.new()
	definition.definition_id = StringName(base_id)
	definition.slot = slot
	definition.rarity = rarity
	definition.item_level = item_level
	definition.display_name = "%s %s" % [
		EquipmentRarity.get_display_name(rarity),
		EquipmentSlot.get_display_name(slot),
	]
	definition.description = "Deterministic fixture %s for the %s slot." % [
		EquipmentRarity.get_display_name(rarity).to_lower(),
		EquipmentSlot.get_display_name(slot).to_lower(),
	]
	definition.unique_effect_id = unique_effect_id

	var instance := EquipmentInstance.new()
	instance.instance_id = StringName(base_id)
	instance.definition = definition
	instance.affixes = affixes if not affixes.is_empty() else _build_default_affixes(item_level, rarity)
	return instance


static func _build_default_affixes(item_level: int, rarity: int) -> Array[EquipmentAffix]:
	var result: Array[EquipmentAffix] = []
	var stat_ids: Array[StringName] = EquipmentAffix.get_stat_ids()
	var count: int = clampi(EquipmentRarity.affix_count(rarity), 1, stat_ids.size())
	for index in count:
		result.append(_create_scaled_affix(stat_ids[index], item_level, rarity))
	return result


static func _create_scaled_affix(stat_id: StringName, item_level: int, rarity: int) -> EquipmentAffix:
	return create_affix(stat_id, _median_affix_value(stat_id, item_level, rarity))


## Median of the production `EquipmentAffix.roll_value` curve (random
## multiplier pinned to 1.0). Mirrors the same rounding rules.
static func _median_affix_value(stat_id: StringName, item_level: int, rarity: int) -> float:
	var safe_level: int = maxi(item_level, 1)
	var safe_rarity: int = clampi(rarity, EquipmentRarity.COMMON, EquipmentRarity.MYTHIC)
	var level_multiplier: float = 1.0 + float(safe_level - 1) * 0.08
	var rarity_multiplier: float = 1.0 + float(safe_rarity) * 0.35
	var rolled_value: float = EquipmentAffix.get_base_value(stat_id) * level_multiplier * rarity_multiplier
	if EquipmentAffix.is_percentage_stat(stat_id):
		return maxf(roundf(rolled_value * 100.0) / 100.0, 0.01)
	return maxf(float(roundi(rolled_value)), 1.0)


static func _find_item_by_rarity(items: Array[EquipmentInstance], rarity: int) -> EquipmentInstance:
	for item in items:
		if item != null and item.get_rarity() == rarity:
			return item
	return null


static func _apply_overrides(obj: Object, overrides: Dictionary) -> void:
	for key in overrides:
		obj.set(key, overrides[key])
