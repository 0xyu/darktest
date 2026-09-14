class_name LootGenerator
extends RefCounted

const LootTableResource = preload("res://scripts/systems/loot_table.gd")
const EquipmentGeneratorResource = preload("res://scripts/systems/equipment_generator.gd")

## Selects a stage-aware loot table and creates equipment instances from it.
## A dropped item becomes a consumable potion at this chance instead of gear.
const CONSUMABLE_DROP_CHANCE: float = 0.15

## The share of successful drops that becomes a potion on THIS generator. Settable so a balance pass
## can measure the potion SUPPLY without editing the class — the M5 simulation's supply sensitivity
## does exactly that — while the shipped default stays the spec's
## [constant CONSUMABLE_DROP_CHANCE].
var consumable_drop_chance: float = CONSUMABLE_DROP_CHANCE
var normal_table
var elite_table
var special_table
var mini_boss_table

var _random_number_generator := RandomNumberGenerator.new()
var _equipment_generator


func _init(random_seed: int = 0) -> void:
	if random_seed == 0:
		_random_number_generator.randomize()
	else:
		_random_number_generator.seed = random_seed
	normal_table = LootTableResource.create_normal()
	elite_table = LootTableResource.create_elite()
	special_table = LootTableResource.create_special()
	mini_boss_table = LootTableResource.create_mini_boss()
	_equipment_generator = EquipmentGeneratorResource.new(random_seed)


## Generates the loot one enemy pays.
##
## `preferred_slots` is the §8 M5 "保底掉落的槽位覆盖" rule: when the caller knows which equipment
## slots the player has EMPTY, an equipment drop is generated for one of them instead of a random
## slot. Covering seven slots with random slots is a coupon-collector problem (~30 drops), while the
## first nine stages only offer ~18 kills — which is why the early game used to arrive at the S10
## challenge with empty slots. An empty list restores the plain random slot.
func generate_loot(
	enemy: Node,
	stage_number: int = 1,
	preferred_slots: Array[int] = []
) -> Array[EquipmentInstance]:
	var result: Array[EquipmentInstance] = []
	if enemy == null or not is_instance_valid(enemy):
		return result
	var table = get_loot_table(enemy)
	if table == null:
		return result
	var drop_count: int = mini(maxi(table.guaranteed_drop_count, 0), maxi(table.max_drop_count, 0))
	if drop_count == 0 and _random_number_generator.randf() <= clampf(table.drop_chance, 0.0, 1.0):
		drop_count = 1
	for _index in range(drop_count):
		var item_level: int = _get_item_level(enemy, stage_number)
		var rarity: int = table.roll_rarity(_random_number_generator)
		result.append(_generate_drop(item_level, rarity, _pick_slot(preferred_slots)))
	return result


func generate_from_table(
	table,
	item_level: int = 1,
	preferred_slots: Array[int] = []
) -> Array[EquipmentInstance]:
	var result: Array[EquipmentInstance] = []
	if table == null:
		return result
	var drop_count: int = mini(maxi(table.guaranteed_drop_count, 0), maxi(table.max_drop_count, 0))
	if drop_count == 0 and _random_number_generator.randf() <= clampf(table.drop_chance, 0.0, 1.0):
		drop_count = 1
	for _index in range(drop_count):
		result.append(_generate_drop(
			maxi(item_level, 1),
			table.roll_rarity(_random_number_generator),
			_pick_slot(preferred_slots)
		))
	return result


## One of the slots the drop may cover, or -1 for "let the generator roll a slot".
func _pick_slot(preferred_slots: Array[int]) -> int:
	var candidates: Array[int] = []
	for slot in preferred_slots:
		if EquipmentSlot.is_valid(slot) and not candidates.has(slot):
			candidates.append(slot)
	if candidates.is_empty():
		return -1
	return candidates[_random_number_generator.randi_range(0, candidates.size() - 1)]


func _generate_drop(item_level: int, rarity: int, slot: int = -1) -> EquipmentInstance:
	if _random_number_generator.randf() <= consumable_drop_chance:
		return _equipment_generator.generate_potion(item_level, rarity)
	return _equipment_generator.generate_equipment(item_level, slot, rarity)


func get_loot_table(enemy: Node):
	var enemy_type: int = EnemyType.NORMAL
	if enemy is EnemyController and (enemy as EnemyController).enemy_data != null:
		enemy_type = (enemy as EnemyController).enemy_data.enemy_type
	return get_loot_table_for_enemy_type(enemy_type)


func get_loot_table_for_enemy_type(enemy_type: int):
	match enemy_type:
		EnemyType.MINI_BOSS:
			return mini_boss_table
		EnemyType.ELITE:
			return elite_table
		EnemyType.SPECIAL, EnemyType.TREASURE, EnemyType.GOLD, EnemyType.CURSED:
			return special_table
		_:
			return normal_table


func _get_item_level(enemy: Node, stage_number: int) -> int:
	var enemy_level: int = 1
	if enemy is EnemyController:
		var enemy_controller: EnemyController = enemy as EnemyController
		enemy_level = enemy_controller.enemy_level
	else:
		var enemy_stats_variant: Variant = enemy.get("enemy_stats")
		if enemy_stats_variant is EnemyStats:
			var enemy_stats: EnemyStats = enemy_stats_variant as EnemyStats
			enemy_level = enemy_stats.level
	return maxi(maxi(enemy_level, 1), maxi(stage_number, 1))
