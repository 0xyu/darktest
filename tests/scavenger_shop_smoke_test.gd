extends SceneTree

## Scavenger Shop smoke test: the buyback book, the purchase, and the promise that
## buying the Beginner Sword back can never re-arm the Stage 10 drop.
## Run headless: godot --headless --path . -s res://tests/scavenger_shop_smoke_test.gd
##
## Verifies:
##   * a discarded item is recorded, priced and handed back as the SAME instance
##   * a purchase needs gold, refuses items the shop does not hold, and overflows
##     to the warehouse when the bag is full
##   * the real discard path stocks the panel's book (player signal -> panel)
##   * buying back writes nothing to the one-shot store, so the Stage 10 boss stays
##     as dry as it was

const AuthoredContentStateScript = preload("res://scripts/progress/authored_content_state.gd")
const LootSystemScript = preload("res://scripts/systems/loot_system.gd")

const SWORD_PATH := "res://resources/items/beginner_sword.tres"
const LEVEL_010_PATH := "res://resources/levels/level_010.tres"
const STAGE_10_KEY := "forest_010"
const SWORD_ID := &"beginner_sword"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_book_records_and_prices()
	_test_buy_back_returns_the_same_instance()
	_test_buy_back_needs_gold()
	_test_buy_back_refuses_foreign_items()
	_test_bag_full_buy_back_goes_to_storage()
	_test_discard_stocks_the_panel_book()
	_test_buy_back_never_rearms_the_drop()
	_test_only_authored_opted_in_items_are_stocked()
	_test_sell_pays_and_stocks()
	_test_shop_sell_tab_sells_from_the_bag()
	_test_bulk_sell_common_only()

	if _failures.is_empty():
		print("Scavenger Shop smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_book_records_and_prices() -> void:
	var shop := ScavengerShop.new()
	var sword := _make_sword()
	_expect(shop.get_entry_count() == 0, "a fresh shop has an empty book")
	_expect(shop.record(sword, 10), "a discarded item is recorded")
	_expect(shop.get_entry_count() == 1, "the book holds the recorded item")
	_expect(shop.has_entry(sword), "the book holds the very instance it was given")
	_expect(not shop.record(sword), "recording the same instance twice is a no-op")
	_expect(shop.get_entry_count() == 1, "the book still holds exactly one instance")

	# The price is the §19 SellPrice for the stage the item was given up on. The Power Score
	# is a combat-comparison signal and is never a price.
	var expected: int = ItemEconomy.get_sell_price(sword, 10)
	_expect(shop.get_price(sword) == expected, "the price is the §19 SellPrice for that stage")
	_expect(shop.get_price(sword) > 0, "the price is positive")
	_expect(shop.get_price(null) == 0, "an absent item has no price")
	_expect(
		shop.get_price(sword) != maxi(1, roundi(sword.get_equipment_score())),
		"the price is not the Power Score"
	)
	_expect(not ScavengerShop.can_stock(_make_foreign_item()), "a runtime-generated item is not stockable")

	# Newest first, and the book is bounded.
	var filler := _make_sword()
	shop.record(filler)
	_expect(shop.get_entries()[0] == filler, "the newest entry is listed first")
	shop.capacity = 1
	var overflow := _make_sword()
	shop.record(overflow)
	_expect(shop.get_entry_count() == 1, "the book honours its capacity")
	_expect(shop.has_entry(overflow) and not shop.has_entry(filler), "the oldest entry falls off")
	shop.clear()
	_expect(shop.get_entry_count() == 0, "clearing empties the book")


func _test_buy_back_returns_the_same_instance() -> void:
	var shop := ScavengerShop.new()
	var player := _make_player(500)
	var sword := _make_sword()
	shop.record(sword, 10)
	var price: int = shop.get_price(sword)

	var result: Dictionary = shop.buy_back(player, sword)
	_expect(bool(result.get("success", false)), "an affordable item is bought back")
	_expect(player.player_progression.gold == 500 - price, "the price is deducted from gold")
	_expect(int(result.get("cost", -1)) == price, "the result reports what was charged")
	_expect(not bool(result.get("stored", true)), "it returns to the bag, not the warehouse")
	_expect(player.get_inventory().has_item(sword), "the bag holds the item again")
	_expect(not shop.has_entry(sword), "a bought-back item leaves the book")
	_expect(shop.get_entry_count() == 0, "the book drops the entry entirely")

	# Ownership, not a copy: the player gets the instance the shop was holding.
	var returned: EquipmentInstance = result.get("item") as EquipmentInstance
	_expect(returned == sword, "the returned item IS the discarded instance")
	_expect(returned.instance_id == SWORD_ID, "its identity survives the round trip")
	_expect(
		is_equal_approx(returned.get_affix_value(&"attack"), 10.0),
		"its fixed stats survive the round trip"
	)
	player.free()


func _test_buy_back_needs_gold() -> void:
	var shop := ScavengerShop.new()
	var player := _make_player(1)
	var sword := _make_sword()
	shop.record(sword)

	var result: Dictionary = shop.buy_back(player, sword)
	_expect(not bool(result.get("success", true)), "an unaffordable item is refused")
	_expect(str(result.get("reason", "")) == "INSUFFICIENT_GOLD", "the refusal is INSUFFICIENT_GOLD")
	_expect(player.player_progression.gold == 1, "a refused purchase charges nothing")
	_expect(shop.has_entry(sword), "the item stays in the book")
	_expect(not player.get_inventory().has_item(sword), "the item does not reach the bag")
	player.free()


func _test_buy_back_refuses_foreign_items() -> void:
	var shop := ScavengerShop.new()
	var player := _make_player(500)
	var sword := _make_sword()

	var result: Dictionary = shop.buy_back(player, sword)
	_expect(not bool(result.get("success", true)), "an item the shop does not hold is refused")
	_expect(
		str(result.get("reason", "")) == "ITEM_NOT_IN_BUYBACK",
		"the refusal is ITEM_NOT_IN_BUYBACK"
	)
	_expect(player.player_progression.gold == 500, "a refused purchase charges nothing")
	_expect(not player.get_inventory().has_item(sword), "nothing is handed over")
	player.free()


func _test_bag_full_buy_back_goes_to_storage() -> void:
	var shop := ScavengerShop.new()
	var player := _make_player(500)
	var sword := _make_sword()
	var inventory: EquipmentInventory = player.get_inventory()
	inventory.capacity = 1
	# A real rolled item fills the bag, so the capacity case tests capacity and not
	# two copies of the same fixed definition.
	var filler: EquipmentInstance = EquipmentGenerator.new(1).generate_equipment(
		1, EquipmentSlot.WEAPON, EquipmentRarity.COMMON
	)
	_expect(inventory.add_item(filler), "the filler occupies the only bag slot")
	_expect(inventory.get_remaining_capacity() == 0, "the bag is full")
	shop.record(sword)

	var result: Dictionary = shop.buy_back(player, sword)
	_expect(bool(result.get("success", false)), "a full bag does not block a buyback")
	_expect(bool(result.get("stored", false)), "the result reports the warehouse overflow")
	_expect(player.get_storage().has_item(sword), "the item lands in the warehouse")
	_expect(not inventory.get_items().has(sword), "it is not forced into the full bag")
	player.free()


func _test_discard_stocks_the_panel_book() -> void:
	var player := _make_player(500)
	var sword := _make_sword()
	var panel := ScavengerShopPanel.new()
	root.add_child(panel)
	panel.set_player(player)
	_expect(panel.shop != null, "the panel builds its own shop when the scene exports none")
	if panel.shop == null:
		panel.free()
		player.free()
		return

	player.get_inventory().add_item(sword)
	_expect(player.discard_item(sword), "the sword leaves the bag")
	_expect(panel.shop.has_entry(sword), "the real discard path stocks the buyback book")
	_expect(not player.get_inventory().has_item(sword), "the bag no longer holds it")

	# The shop can hand it back on the same terms.
	var result: Dictionary = panel.shop.buy_back(player, sword)
	_expect(bool(result.get("success", false)), "the panel's shop sells it back")
	_expect(player.get_inventory().has_item(sword), "the sword is back in the bag")
	panel.free()
	player.free()


func _test_buy_back_never_rearms_the_drop() -> void:
	# The Stage 10 kill already happened in this save.
	var state: AuthoredContentState = AuthoredContentStateScript.new()
	state.consume(STAGE_10_KEY, SWORD_ID)
	var consumed_before: int = state.get_consumed_count()

	var shop := ScavengerShop.new()
	var player := _make_player(500)
	var sword := _make_sword()
	shop.record(sword)
	var result: Dictionary = shop.buy_back(player, sword)
	_expect(bool(result.get("success", false)), "the sword is bought back with the grant already spent")
	_expect(state.is_consumed(STAGE_10_KEY, SWORD_ID), "the grant record survives a buyback")
	_expect(
		state.get_consumed_count() == consumed_before,
		"a purchase writes nothing at all to the one-shot store"
	)

	# The drop stays dry: the loot rule still sees Stage 10 as already paid out.
	var config: LevelConfig = load(LEVEL_010_PATH)
	_expect(config != null, "level_010.tres loads")
	if config != null:
		var guaranteed: Array[EquipmentDefinition] = config.to_stage_definition().guaranteed_loot
		var loot_system = LootSystemScript.new()
		loot_system.attach_content_state(state)
		var loot: Array[EquipmentInstance] = []
		loot_system.grant_guaranteed_drops(loot, guaranteed, STAGE_10_KEY)
		_expect(loot.is_empty(), "the Stage 10 boss still grants nothing after a buyback")
		loot_system.free()

	player.free()


## Only AUTHORED items that opted in with `can_buy_back` may enter the book: the buyback is
## a safety net for hand-authored rewards, not a second inventory for generated loot.
func _test_only_authored_opted_in_items_are_stocked() -> void:
	var shop := ScavengerShop.new()
	var generated := UIFixture.create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, 10)
	_expect(not ScavengerShop.can_stock(generated), "a generated definition has no resource path")
	_expect(not shop.record(generated, 10), "recording a generated item is refused")
	_expect(shop.get_entry_count() == 0, "the book stays empty")

	var sword := _make_sword()
	_expect(sword.definition.can_buy_back, "the Beginner Sword opts in with can_buy_back")
	_expect(ScavengerShop.can_stock(sword), "an opted-in authored item is stockable")


## Selling is the town's gold sink source: the player service pays the §19 price, and the
## item lands in the shared book at that same price, so the sale can be undone at cost.
func _test_sell_pays_and_stocks() -> void:
	var player := _make_player(0)
	player.set_current_stage_number(10)
	var sword := _make_sword()
	player.get_inventory().add_item(sword)
	var expected: int = ItemEconomy.get_sell_price(sword, 10)

	var result: Dictionary = player.sell_item(sword)
	_expect(bool(result.get("success", false)), "the sword sells")
	_expect(int(result.get("price", 0)) == expected, "the sale pays the §19 price")
	_expect(player.player_progression.gold == expected, "the gold reaches the player")
	_expect(not player.get_inventory().has_item(sword), "the sword leaves the bag")

	var shop: ScavengerShop = player.get_scavenger_shop()
	_expect(shop.has_entry(sword), "a sale is stocked in the shared buyback book")
	_expect(shop.get_price(sword) == expected, "the book charges what the sale paid")

	var bought_back: Dictionary = shop.buy_back(player, sword)
	_expect(bool(bought_back.get("success", false)), "a sold item can be bought back")
	_expect(player.player_progression.gold == 0, "buying back costs exactly what the sale paid")
	_expect(player.get_inventory().has_item(sword), "the sword returns to the bag")

	# A worn item must come off first, and an item the player does not own cannot be sold.
	_expect(player.equip_item(sword), "the sword can be equipped")
	var equipped_refusal: Dictionary = player.sell_item(sword)
	_expect(
		str(equipped_refusal.get("reason", "")) == "ITEM_EQUIPPED",
		"an equipped item is refused with ITEM_EQUIPPED"
	)
	_expect(player.player_progression.gold == 0, "a refused sale pays nothing")

	# The bag identifies items by `instance_id`, so the foreign item must be a different
	# definition — a second instance of the same sword would match the owned one.
	var unowned_refusal: Dictionary = player.sell_item(_make_foreign_item())
	_expect(str(unowned_refusal.get("reason", "")) == "ITEM_NOT_OWNED", "an unowned item is refused")
	player.free()


## The shop's SELL tab lists the player's own items and sells them through the same service
## the warehouse popup uses: one price, one book, two town surfaces.
func _test_shop_sell_tab_sells_from_the_bag() -> void:
	var player := _make_player(0)
	player.set_current_stage_number(10)
	var panel := ScavengerShopPanel.new()
	root.add_child(panel)
	panel.set_player(player)
	var sword := _make_sword()
	player.get_inventory().add_item(sword)

	panel.call("_on_tab_pressed", ScavengerShopPanel.Tab.SELL)
	var listed: Array = panel.call("_get_active_entries")
	_expect(listed.has(sword), "the SELL tab lists the item in the bag")

	panel.call("_on_sell_pressed", sword, false)
	_expect(not player.get_inventory().has_item(sword), "the SELL tab takes the item out of the bag")
	_expect(
		player.player_progression.gold == ItemEconomy.get_sell_price(sword, 10),
		"the SELL tab pays the §19 price"
	)
	_expect(player.get_scavenger_shop().has_entry(sword), "the SELL tab stocks the shared book")

	panel.call("_on_tab_pressed", ScavengerShopPanel.Tab.BUYBACK)
	var buyback_entries: Array = panel.call("_get_active_entries")
	_expect(buyback_entries.has(sword), "the sold item shows up under BUYBACK")
	panel.free()
	player.free()


## The SELL tab's bulk action sells COMMON ("white") gear only — from the bag and the
## warehouse — and refuses to strip gear the player is wearing. Every sale is an ordinary
## `sell_item`, so the gold, the price and the buyback entry are the single-sale ones.
func _test_bulk_sell_common_only() -> void:
	var player := _make_player(0)
	player.set_current_stage_number(10)
	var panel := ScavengerShopPanel.new()
	root.add_child(panel)
	panel.set_player(player)
	panel.call("_on_tab_pressed", ScavengerShopPanel.Tab.SELL)

	# The bag target is the authored Beginner Sword (Common, `can_buy_back`), so the sale's
	# buyback stocking is observable; the warehouse target is generated loot, which sells but
	# is never stocked (ScavengerShop.can_stock).
	var bag_common := _make_sword()
	var worn_common := UIFixture.create_equipment(EquipmentRarity.COMMON, EquipmentSlot.ARMOR, 10)
	var rare := UIFixture.create_equipment(EquipmentRarity.RARE, EquipmentSlot.WEAPON, 10)
	var stored_common := UIFixture.create_equipment(EquipmentRarity.COMMON, EquipmentSlot.HELMET, 10)
	player.get_inventory().add_item(bag_common)
	player.get_inventory().add_item(worn_common)
	player.get_inventory().add_item(rare)
	player.add_to_storage(stored_common)
	_expect(player.equip_item(worn_common), "a common item can be worn for the test")

	var listed: Array = []
	for target in panel.call("_get_common_sell_targets"):
		listed.append(target["item"])
	_expect(listed.size() == 2, "only unworn common gear is a bulk target")
	_expect(
		listed.has(bag_common) and listed.has(stored_common),
		"commons in the bag and in the warehouse are both targets"
	)
	_expect(not listed.has(rare), "a rare item is never a bulk target")
	_expect(not listed.has(worn_common), "worn gear is never a bulk target")

	var expected_gold: int = (
		ItemEconomy.get_sell_price(bag_common, 10) + ItemEconomy.get_sell_price(stored_common, 10)
	)
	panel.call("_on_bulk_sell_confirmed")
	_expect(player.player_progression.gold == expected_gold, "the bulk sale pays every §19 price")
	_expect(not player.get_inventory().has_item(bag_common), "the bag common is sold")
	_expect(not player.get_storage().has_item(stored_common), "the stored common is sold")
	_expect(player.get_inventory().has_item(rare), "the rare item survives the bulk sale")
	_expect(player.get_inventory().has_item(worn_common), "the worn common survives the bulk sale")
	var shop: ScavengerShop = player.get_scavenger_shop()
	_expect(shop.has_entry(bag_common), "a recoverable bulk sale is stocked in BUYBACK")
	_expect(not shop.has_entry(stored_common), "generated loot sells but is never stocked")
	_expect(
		(panel.call("_get_common_sell_targets") as Array).is_empty(),
		"the bulk action has nothing left to sell"
	)
	panel.free()
	player.free()


func _make_foreign_item() -> EquipmentInstance:
	return UIFixture.create_equipment(EquipmentRarity.COMMON, EquipmentSlot.WEAPON, 1)


func _make_player(gold: int) -> PlayerController:
	var player := PlayerController.new()
	player.player_progression.gold = gold
	return player


func _make_sword() -> EquipmentInstance:
	var definition: EquipmentDefinition = load(SWORD_PATH)
	return EquipmentInstance.create_from_definition(definition)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
