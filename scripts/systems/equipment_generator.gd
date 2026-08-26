class_name EquipmentGenerator
extends RefCounted

## Creates concrete equipment data without applying loot-table rules.
var _random_number_generator := RandomNumberGenerator.new()
var _next_instance_id: int = 1


func _init(random_seed: int = 0) -> void:
	if random_seed == 0:
		_random_number_generator.randomize()
	else:
		_random_number_generator.seed = random_seed


func generate_equipment(item_level: int = 1, slot: int = -1, rarity: int = -1) -> EquipmentInstance:
	var safe_level: int = maxi(item_level, 1)
	var selected_slot: int = slot if EquipmentSlot.is_valid(slot) else _random_number_generator.randi_range(EquipmentSlot.WEAPON, EquipmentSlot.AMULET)
	var selected_rarity: int = rarity if EquipmentRarity.is_valid(rarity) else _random_number_generator.randi_range(EquipmentRarity.COMMON, EquipmentRarity.MYTHIC)
	var definition := EquipmentDefinition.new()
	definition.definition_id = StringName("generated_%d" % _next_instance_id)
	definition.slot = selected_slot
	definition.rarity = selected_rarity
	definition.item_level = safe_level
	definition.display_name = "%s %s" % [EquipmentRarity.get_display_name(selected_rarity), EquipmentSlot.get_display_name(selected_slot)]
	definition.description = "A generated %s equipment item." % EquipmentSlot.get_display_name(selected_slot).to_lower()
	definition.unique_effect_id = _roll_unique_effect_id(selected_rarity)

	var instance := EquipmentInstance.new()
	instance.instance_id = StringName("%s_%d" % [definition.definition_id, _next_instance_id])
	instance.definition = definition
	instance.affixes = roll_affixes(definition)
	_next_instance_id += 1
	return instance


func _roll_unique_effect_id(rarity: int) -> StringName:
	if rarity == EquipmentRarity.MYTHIC:
		return _random_unique_effect_id()
	if rarity == EquipmentRarity.LEGENDARY and _random_number_generator.randf() <= 0.25:
		return _random_unique_effect_id()
	return &""


func _random_unique_effect_id() -> StringName:
	var effect_ids: Array[StringName] = [
		&"every_3rd_attack",
		&"critical_healing",
		&"movement_attack",
		&"back_attack",
		&"poisoned_target",
	]
	return effect_ids[_random_number_generator.randi_range(0, effect_ids.size() - 1)]


func roll_affixes(definition: EquipmentDefinition, requested_count: int = -1) -> Array[EquipmentAffix]:
	var result: Array[EquipmentAffix] = []
	if definition == null:
		return result
	var occupied_stats: Dictionary = {}
	for base_affix in definition.base_affixes:
		if base_affix == null or occupied_stats.has(base_affix.stat_id):
			continue
		result.append(base_affix.duplicate(true) as EquipmentAffix)
		occupied_stats[base_affix.stat_id] = true

	var target_count: int = EquipmentRarity.affix_count(definition.rarity) if requested_count < 0 else maxi(requested_count, 0)
	target_count = mini(target_count, EquipmentAffix.get_stat_ids().size())
	while result.size() < target_count:
		var selected_stat: StringName = _roll_available_stat(occupied_stats)
		if selected_stat == &"":
			break
		result.append(EquipmentAffix.create_rolled(selected_stat, definition.item_level, definition.rarity, _random_number_generator))
		occupied_stats[selected_stat] = true
	return result


func _roll_available_stat(occupied_stats: Dictionary) -> StringName:
	var available_stats: Array[StringName] = []
	var total_weight: float = 0.0
	for stat_id in EquipmentAffix.get_stat_ids():
		if occupied_stats.has(stat_id):
			continue
		var weight: float = EquipmentAffix.get_weight(stat_id)
		if weight <= 0.0:
			continue
		available_stats.append(stat_id)
		total_weight += weight
	if available_stats.is_empty() or total_weight <= 0.0:
		return &""

	var roll: float = _random_number_generator.randf_range(0.0, total_weight)
	var cumulative_weight: float = 0.0
	for stat_id in available_stats:
		cumulative_weight += EquipmentAffix.get_weight(stat_id)
		if roll <= cumulative_weight:
			return stat_id
	return available_stats.back()
