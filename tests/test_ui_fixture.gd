extends McpTestSuite

## Verifies the deterministic UI fixture system. See
## res://tests/fixtures/ui_fixture.gd.
##
## The fixture is referenced through a preload rather than the `UIFixture`
## global class name so discovery works even before the editor has rebuilt
## its in-memory global class table after a fresh scan.

const UIFixtureScript := preload("res://tests/fixtures/ui_fixture.gd")

func suite_name() -> String:
	return "ui_fixture"


func test_headless_load() -> void:
	var fixture_script = load("res://tests/fixtures/ui_fixture.gd")
	assert_true(fixture_script != null, "ui_fixture.gd should load")
	var inventory = fixture_script.create_inventory()
	assert_true(inventory is EquipmentInventory, "create_inventory should return EquipmentInventory")
	assert_true(inventory.get_item_count() > 0, "create_inventory should be populated")


func test_rarity_set_has_all_required_rarities() -> void:
	var items := UIFixtureScript.create_rarity_set()
	assert_true(items.size() >= 5, "rarity set should have at least 5 items")
	var rarities := {}
	for item in items:
		rarities[item.get_rarity()] = true
	for required_rarity in [
		EquipmentRarity.COMMON,
		EquipmentRarity.RARE,
		EquipmentRarity.EPIC,
		EquipmentRarity.LEGENDARY,
		EquipmentRarity.MYTHIC,
	]:
		assert_true(
			rarities.has(required_rarity),
			"rarity set missing %s" % EquipmentRarity.get_display_name(required_rarity)
		)
	# Every rarity-set item must carry the affix count its rarity implies.
	for item in items:
		var expected_count: int = EquipmentRarity.affix_count(item.get_rarity())
		assert_eq(
			item.affixes.size(),
			expected_count,
			"%s should have %d affixes" % [item.get_display_name(), expected_count]
		)


func test_inventory_has_required_rarities() -> void:
	var inventory := UIFixtureScript.create_inventory()
	var rarities := {}
	for item in inventory.get_items():
		rarities[item.get_rarity()] = true
	for required_rarity in [
		EquipmentRarity.COMMON,
		EquipmentRarity.RARE,
		EquipmentRarity.EPIC,
		EquipmentRarity.LEGENDARY,
		EquipmentRarity.MYTHIC,
	]:
		assert_true(
			rarities.has(required_rarity),
			"inventory missing %s" % EquipmentRarity.get_display_name(required_rarity)
		)


func test_equipment_values_are_deterministic() -> void:
	var first := UIFixtureScript.create_equipment(EquipmentRarity.LEGENDARY, EquipmentSlot.HELMET, 25, &"movement_attack")
	var second := UIFixtureScript.create_equipment(EquipmentRarity.LEGENDARY, EquipmentSlot.HELMET, 25, &"movement_attack")
	assert_eq(first.get_display_name(), second.get_display_name())
	assert_eq(first.get_rarity(), second.get_rarity())
	assert_eq(first.get_item_level(), second.get_item_level())
	assert_eq(first.affixes.size(), second.affixes.size())
	for index in first.affixes.size():
		assert_eq(first.affixes[index].stat_id, second.affixes[index].stat_id, "affix %d stat_id" % index)
		assert_eq(first.affixes[index].value, second.affixes[index].value, "affix %d value" % index)
		assert_eq(first.affixes[index].is_percentage, second.affixes[index].is_percentage, "affix %d type" % index)


func test_no_rng_dependency() -> void:
	var baseline := UIFixtureScript.create_equipment(EquipmentRarity.MYTHIC, EquipmentSlot.RING, 40, &"critical_healing")
	for _sample_index in 10:
		var sample := UIFixtureScript.create_equipment(EquipmentRarity.MYTHIC, EquipmentSlot.RING, 40, &"critical_healing")
		assert_eq(sample.affixes.size(), baseline.affixes.size())
		for affix_index in sample.affixes.size():
			assert_eq(
				sample.affixes[affix_index].value,
				baseline.affixes[affix_index].value,
				"affix %d value drifted across calls" % affix_index
			)


func test_rarity_set_is_repeatable() -> void:
	var set_a := UIFixtureScript.create_rarity_set()
	var set_b := UIFixtureScript.create_rarity_set()
	assert_eq(set_a.size(), set_b.size())
	for index in set_a.size():
		assert_eq(set_a[index].instance_id, set_b[index].instance_id, "item %d instance_id" % index)
		assert_eq(set_a[index].affixes.size(), set_b[index].affixes.size(), "item %d affix count" % index)
		assert_eq(set_a[index].get_equipment_score(), set_b[index].get_equipment_score(), "item %d score" % index)


func test_inventory_is_repeatable() -> void:
	var inventory_a := UIFixtureScript.create_inventory()
	var inventory_b := UIFixtureScript.create_inventory()
	assert_eq(inventory_a.get_item_count(), inventory_b.get_item_count())
	assert_eq(inventory_a.get_equipped_items().size(), inventory_b.get_equipped_items().size())
	assert_gt(inventory_a.get_equipped_items().size(), 0, "demo inventory should have equipped items")
	# Rarity set (6) + two generic extras must all fit — a duplicate
	# instance_id would silently drop an item and change the count.
	var expected_count: int = UIFixtureScript.create_rarity_set().size() + 2
	assert_eq(inventory_a.get_item_count(), expected_count, "all generated items should be added")


func test_generated_items_have_unique_ids() -> void:
	var inventory := UIFixtureScript.create_empty_inventory()
	var first := UIFixtureScript.create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, 10)
	var second := UIFixtureScript.create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, 10)
	assert_ne(first.instance_id, second.instance_id, "repeated generic items need distinct ids")
	assert_true(inventory.add_item(first), "first generated item should be accepted")
	assert_true(inventory.add_item(second), "second generated item should be accepted")
	assert_eq(inventory.get_item_count(), 2)


func test_affix_count_matches_rarity() -> void:
	var expected_counts := {
		EquipmentRarity.COMMON: 1,
		EquipmentRarity.RARE: 3,
		EquipmentRarity.EPIC: 4,
		EquipmentRarity.LEGENDARY: 5,
		EquipmentRarity.MYTHIC: 5,
	}
	for rarity in expected_counts:
		var item := UIFixtureScript.create_equipment(rarity)
		assert_eq(
			item.affixes.size(),
			expected_counts[rarity],
			"affix count for %s" % EquipmentRarity.get_display_name(rarity)
		)


func test_custom_affixes_are_respected() -> void:
	var affix := UIFixtureScript.create_affix(&"attack", 42.0)
	var item := UIFixtureScript.create_equipment(EquipmentRarity.COMMON, EquipmentSlot.WEAPON, 1, &"", [affix])
	assert_eq(item.affixes.size(), 1)
	assert_eq(item.get_affix_value(&"attack"), 42.0)


func test_character_fixture() -> void:
	var character := UIFixtureScript.create_character(15, 999, 7)
	assert_true(character.stats is PlayerStats)
	assert_true(character.progression is PlayerProgression)
	assert_true(character.inventory is EquipmentInventory)
	assert_eq(character.progression.level, 15)
	assert_eq(character.progression.gold, 999)
	assert_eq(character.progression.current_stage, 7)
	assert_true(character.inventory.get_item_count() >= 5, "character inventory should contain the rarity set")
	assert_gt(character.stats.max_hp, 100, "stats should scale with level")


func test_apply_character_to_player() -> void:
	var player := PlayerController.new()
	track(player)
	UIFixtureScript.apply_character_to_player(player)
	assert_true(player.get_inventory().get_item_count() >= 5)
	assert_eq(player.player_progression.level, 10, "default character level should apply")
	# Equipped fixture items must raise derived stats above base stats.
	var base_attack: int = UIFixtureScript.create_player_stats().attack
	assert_true(player.player_stats.attack > base_attack, "equipped fixture bonuses should raise attack")
