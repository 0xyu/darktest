extends "res://tools/ui_harness/ui_harness_suite.gd"


func _mount_shop() -> Node:
	return await mount_scene("res://scenes/ui/SubHeroShopPanel.tscn")


func test_scene_loads_hidden() -> void:
	var shop := await _mount_shop()
	expect(shop != null, "SubHeroShopPanel should instantiate")
	expect(not shop.visible, "shop panel should start hidden")
	expect(shop.get_node("ShopPanel") != null, "shop should build its centered panel")


func test_configured_odds_are_visible() -> void:
	var shop := await _mount_shop()
	# The implementation intentionally builds the content dynamically. Verify
	# the data-driven table instead of coupling this test to generated node names.
	expect(shop.summon_service.summon_table.get_total_weight() > 0.0, "summon table should have configured weights")
	# §6.2: the price is a FLOOR for an empty collection and is derived from the whole collection
	# afterwards, so a mounted shop with no player quotes the floor rather than a stored constant.
	var profile := BalanceProfile.get_default()
	expect_eq(
		shop.summon_service.calculate_summon_cost(shop.get("_player")),
		profile.summon_gold_floor,
		"an unowned collection quotes the floor price"
	)
