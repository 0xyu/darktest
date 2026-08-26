extends SceneTree

const LootGeneratorResource = preload("res://scripts/systems/loot_generator.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var generator = LootGeneratorResource.new(1601)
	var normal_table = generator.get_loot_table_for_enemy_type(EnemyType.NORMAL)
	_expect(normal_table.drop_chance == 0.25, "normal enemies have a configured equipment drop chance")
	_expect(normal_table.rarity_weights[EquipmentRarity.COMMON] == 60.0, "normal common rarity weight is sixty percent")
	_expect(normal_table.rarity_weights[EquipmentRarity.UNCOMMON] == 25.0, "normal uncommon rarity weight is twenty-five percent")
	_expect(normal_table.rarity_weights[EquipmentRarity.RARE] == 10.0, "normal rare rarity weight is ten percent")
	_expect(normal_table.rarity_weights[EquipmentRarity.EPIC] == 4.0, "normal epic rarity weight is four percent")
	_expect(normal_table.rarity_weights[EquipmentRarity.LEGENDARY] == 1.0, "normal legendary rarity weight is one percent")
	_expect(normal_table.get_total_weight() == 100.0, "normal rarity weights total one hundred")

	var elite_table = generator.get_loot_table_for_enemy_type(EnemyType.ELITE)
	var special_table = generator.get_loot_table_for_enemy_type(EnemyType.SPECIAL)
	var boss_table = generator.get_loot_table_for_enemy_type(EnemyType.MINI_BOSS)
	_expect(elite_table.minimum_rarity == EquipmentRarity.UNCOMMON, "elite loot starts at Uncommon")
	_expect(special_table.minimum_rarity == EquipmentRarity.RARE, "special loot starts at Rare")
	_expect(boss_table.guaranteed_drop_count == 1, "Mini Boss loot guarantees equipment")
	_expect(boss_table.minimum_rarity == EquipmentRarity.RARE, "Mini Boss loot starts at Rare")
	_expect(boss_table.rarity_weights[EquipmentRarity.LEGENDARY] > normal_table.rarity_weights[EquipmentRarity.LEGENDARY], "boss loot has a better Legendary opportunity")

	var normal_definition := EnemyDefinition.new()
	normal_definition.enemy_type = EnemyType.NORMAL
	normal_definition.base_stats = EnemyStats.new()
	var normal_enemy := EnemyController.new()
	normal_enemy.enemy_definition = normal_definition
	normal_enemy.enemy_level = 12
	normal_table.drop_chance = 1.0
	var normal_loot: Array[EquipmentInstance] = generator.generate_loot(normal_enemy, 12)
	_expect(normal_loot.size() == 1, "a successful normal drop creates one equipment item")
	if not normal_loot.is_empty():
		_expect(normal_loot[0].get_item_level() == 12, "loot item level follows the current stage")
		_expect(normal_loot[0].get_rarity() >= EquipmentRarity.COMMON and normal_loot[0].get_rarity() <= EquipmentRarity.LEGENDARY, "normal loot stays within its configured rarity range")

	var boss_definition := EnemyDefinition.new()
	boss_definition.enemy_type = EnemyType.MINI_BOSS
	boss_definition.base_stats = EnemyStats.new()
	var boss_enemy := EnemyController.new()
	boss_enemy.enemy_definition = boss_definition
	boss_enemy.enemy_level = 20
	var boss_loot: Array[EquipmentInstance] = generator.generate_loot(boss_enemy, 20)
	_expect(boss_loot.size() == 1, "Mini Boss always creates its guaranteed equipment drop")
	if not boss_loot.is_empty():
		_expect(boss_loot[0].get_rarity() >= EquipmentRarity.RARE, "Mini Boss drop respects the Rare minimum")
	normal_enemy.free()
	boss_enemy.free()

	if _failures.is_empty():
		print("Phase 16 smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
