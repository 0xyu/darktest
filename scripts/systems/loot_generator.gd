class_name LootGenerator
extends RefCounted

const LootTableResource = preload("res://scripts/systems/loot_table.gd")
const EquipmentGeneratorResource = preload("res://scripts/systems/equipment_generator.gd")

## Selects a stage-aware loot table and creates equipment instances from it.
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


func generate_loot(enemy: Node, stage_number: int = 1) -> Array[EquipmentInstance]:
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
		result.append(_equipment_generator.generate_equipment(item_level, -1, rarity))
	return result


func generate_from_table(table, item_level: int = 1) -> Array[EquipmentInstance]:
	var result: Array[EquipmentInstance] = []
	if table == null:
		return result
	var drop_count: int = mini(maxi(table.guaranteed_drop_count, 0), maxi(table.max_drop_count, 0))
	if drop_count == 0 and _random_number_generator.randf() <= clampf(table.drop_chance, 0.0, 1.0):
		drop_count = 1
	for _index in range(drop_count):
		result.append(_equipment_generator.generate_equipment(maxi(item_level, 1), -1, table.roll_rarity(_random_number_generator)))
	return result


func get_loot_table(enemy: Node):
	var enemy_type: int = EnemyType.NORMAL
	var definition_variant: Variant = enemy.get("enemy_definition")
	if definition_variant is EnemyDefinition:
		var definition: EnemyDefinition = definition_variant as EnemyDefinition
		enemy_type = definition.enemy_type
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
