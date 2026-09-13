class_name EquipmentStatBlock
extends RefCounted

## The ONE aggregation of equipped items into the hero's stat block (§3.1, §3.2), shared by the
## live recompute ([method PlayerController.recompute_stats_from_level_and_equipment]) and by
## every preview — the equipment compare card, the inventory tooltip and the AUTO re-equip
## proxy. Both callers pass the same inputs through the same code, so a preview can never
## disagree with what the hero actually gets (contract §3.2 "用同一重算函数预览").
##
## Nothing here caches or mutates: an item's whole contribution is derived from its own slot,
## rarity and item level plus the affix values it carries, so equipping the same items in a
## different ORDER cannot change a single number.

## The items equipped in each [EquipmentSlot], indexed by slot with null for an empty slot.
## Empty slots are what the weights of §3.1 are normalized against, so the layout has to be
## complete even for a hero who owns nothing.
static func empty_slots() -> Array[EquipmentInstance]:
	var slots: Array[EquipmentInstance] = []
	slots.resize(BalanceProfile.SLOT_COUNT)
	return slots


## Reads the equipped items out of an inventory as a slot-indexed layout.
static func slots_from_inventory(inventory: EquipmentInventory) -> Array[EquipmentInstance]:
	var slots: Array[EquipmentInstance] = empty_slots()
	if inventory == null:
		return slots
	for slot in range(BalanceProfile.SLOT_COUNT):
		slots[slot] = inventory.get_equipped_item(slot)
	return slots


## `slot_factor(s)` of every slot: the EMPTY_SLOT_FACTOR constant for an empty one, otherwise
## `rarity_core(r_s) * item_scale(il_s)` — the inherent growth an item carries by being
## equipped at all, which is also what the item card shows as its core stat (§3.1).
static func slot_factors(profile: BalanceProfile, equipped: Array[EquipmentInstance]) -> Array[float]:
	var factors: Array[float] = []
	for slot in range(BalanceProfile.SLOT_COUNT):
		var item: EquipmentInstance = equipped[slot] if slot < equipped.size() else null
		if item == null:
			factors.append(BalanceFormulas.EMPTY_SLOT_FACTOR)
			continue
		factors.append(BalanceFormulas.slot_factor(profile, item.get_rarity(), item.get_item_level()))
	return factors


## `Flat_X`: every affix value of every equipped item, summed per stat id. A core affix already
## carries its own `item_scale` from roll time and is added exactly once — it is never
## multiplied by `item_scale` or by a damage-phase `equipment_multiplier` a second time (§3.1).
static func flat_totals(equipped: Array[EquipmentInstance]) -> Dictionary:
	var totals: Dictionary = {}
	for item in equipped:
		if item == null:
			continue
		for stat_id in EquipmentAffix.get_stat_ids():
			var value: float = item.get_affix_value(stat_id)
			if is_zero_approx(value):
				continue
			totals[stat_id] = float(totals.get(stat_id, 0.0)) + value
	return totals


## The aggregated block for a level and a loadout.
static func compute(
	profile: BalanceProfile,
	level: int,
	equipped: Array[EquipmentInstance],
	base_stats: Dictionary = {}
) -> Dictionary:
	if profile == null:
		return {}
	return BalanceFormulas.stat_block(
		profile,
		level,
		slot_factors(profile, equipped),
		flat_totals(equipped),
		base_stats
	)


## The aggregated block the hero WOULD have with `candidate` in `slot` — a null candidate
## previews taking the item off (§3.3: a preview is a side-effect-free pure function).
static func preview(
	profile: BalanceProfile,
	level: int,
	equipped: Array[EquipmentInstance],
	base_stats: Dictionary,
	slot: int,
	candidate: EquipmentInstance
) -> Dictionary:
	var swapped: Array[EquipmentInstance] = equipped.duplicate()
	if swapped.size() < BalanceProfile.SLOT_COUNT:
		swapped.resize(BalanceProfile.SLOT_COUNT)
	if slot >= 0 and slot < BalanceProfile.SLOT_COUNT:
		swapped[slot] = candidate
	return compute(profile, level, swapped, base_stats)


## The §3.2 compare payload: the block as it is now, the block with the candidate in place, and
## the per-field delta between them, keyed by [PlayerStats] field.
static func compare(
	profile: BalanceProfile,
	level: int,
	equipped: Array[EquipmentInstance],
	base_stats: Dictionary,
	slot: int,
	candidate: EquipmentInstance
) -> Dictionary:
	var current: Dictionary = compute(profile, level, equipped, base_stats)
	var candidate_block: Dictionary = preview(profile, level, equipped, base_stats, slot, candidate)
	var deltas: Dictionary = {}
	for field in candidate_block:
		deltas[field] = float(candidate_block[field]) - float(current.get(field, 0.0))
	return {
		"current": current,
		"candidate": candidate_block,
		"deltas": deltas,
	}
