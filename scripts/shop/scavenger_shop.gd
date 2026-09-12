class_name ScavengerShop
extends Resource

## The Scavenger Shop's BUYBACK BOOK: what the player gave up, and what the shop
## charges to hand it back.
##
## Why it exists
## -------------
## The Beginner Sword is a one-per-save reward, so a mis-clicked "Discard" — or a sale the
## player instantly regrets — would otherwise destroy the only copy they can ever own.
## Giving an item up therefore records it here, and the shop sells it back for gold.
##
## What may be stocked (gameplay-spec §19)
## ---------------------------------------
## Only AUTHORED items whose definition opts in with `EquipmentDefinition.can_buy_back`.
## A runtime-generated definition has no resource path and is never stocked: the book is a
## safety net for hand-authored rewards, not a second inventory.
##
## The price is the §19 `SellPrice`
## --------------------------------
## An entry stores the price it was stocked at, computed once by `ItemEconomy` from the
## stage the player gave it up on. The book never prices an item itself and never uses the
## Power Score: one item carries one value, and that value belongs to the economy, not to
## the compare signal (`EquipmentInstance.get_equipment_score()`).
##
## Buying back NEVER touches the drop
## ---------------------------------
## "The Stage 10 boss drops it once per save" lives in the loot path's one-shot
## store (AuthoredContentState): only LootSystem writes it. This service records
## and returns OWNERSHIP and cannot grant, reset or re-arm a guaranteed drop — so
## buying the sword back leaves the boss exactly as dry as it already was. The two
## stores answer different questions: "has this stage paid out?" versus "what does
## the shop still hold?".
##
## Session-scoped, deliberately
## ----------------------------
## This build persists progress and one-shot content, not equipment (see
## docs/implementation-status.md). A book that outlived the bag it feeds would be
## the only surviving copy of an item nobody owns, so it lives exactly as long as
## the session does.
##
## Ownership
## ---------
## The book holds the EquipmentInstance OBJECTS it was given, untouched: an item
## bought back is the same instance, with the same id and the same stats, not a
## re-rolled copy.

## How many given-up items the shop keeps. The oldest entry falls off the end.
@export_range(1, 99, 1) var capacity: int = 12

var _entries: Array[EquipmentInstance] = []
var _prices: Dictionary = {}


## Records an item the player gave up on `stage`, priced by the §19 model. Recording the
## same instance twice is a no-op: it is one item, not two.
func record(item: EquipmentInstance, stage: int = 1) -> bool:
	if not can_stock(item):
		return false
	if has_entry(item):
		return false
	_entries.push_front(item)
	_prices[item] = ItemEconomy.get_sell_price(item, maxi(stage, 1))
	while _entries.size() > maxi(capacity, 1):
		var evicted: EquipmentInstance = _entries.pop_back()
		_prices.erase(evicted)
	return true


## Whether the book may stock `item` at all: the definition must be AUTHORED (a `.tres`
## resource) and must have opted in with `can_buy_back`.
static func can_stock(item: EquipmentInstance) -> bool:
	if item == null or item.definition == null:
		return false
	if not item.definition.can_buy_back:
		return false
	return not item.definition.resource_path.is_empty()


## The book, newest first. A copy: the shop's own list is not the UI's to edit.
func get_entries() -> Array[EquipmentInstance]:
	return _entries.duplicate()


func has_entry(item: EquipmentInstance) -> bool:
	return item != null and _entries.has(item)


func get_entry_count() -> int:
	return _entries.size()


## What the shop charges to hand `item` back: the price it was stocked at, which is the
## §19 `SellPrice` of the stage the player gave it up on. 0 when the book does not hold it.
func get_price(item: EquipmentInstance) -> int:
	if item == null or not has_entry(item):
		return 0
	return int(_prices.get(item, 0))


func clear() -> void:
	_entries.clear()
	_prices.clear()


## Sells one entry back to the player: gold is spent first, then the item returns
## to the bag (or the warehouse when the bag is full). When neither can take it,
## the gold is refunded and nothing changes.
##
## Result keys are UI-friendly and contain no Control objects:
## {success, reason, cost, item, stored}.
func buy_back(player: Node, item: EquipmentInstance) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return _failure("PLAYER_UNAVAILABLE", item)
	if item == null or not has_entry(item):
		return _failure("ITEM_NOT_IN_BUYBACK", item)
	var progression: PlayerProgression = player.get("player_progression") as PlayerProgression
	if progression == null:
		return _failure("PROGRESSION_UNAVAILABLE", item)
	var cost: int = get_price(item)
	if progression.gold < cost:
		return _failure("INSUFFICIENT_GOLD", item, cost)
	if not progression.spend_gold(cost):
		return _failure("INSUFFICIENT_GOLD", item, cost)

	var stored: bool = false
	var added: bool = player.add_equipment(item) if player.has_method("add_equipment") else false
	if not added and player.has_method("add_to_storage"):
		stored = player.add_to_storage(item)
	if not added and not stored:
		progression.add_gold(cost)
		return _failure("INVENTORY_UNAVAILABLE", item, cost)

	_entries.erase(item)
	_prices.erase(item)
	return {
		"success": true,
		"reason": "",
		"cost": cost,
		"item": item,
		"stored": stored,
	}


func _failure(reason: String, item: EquipmentInstance, cost: int = -1) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
		"cost": cost,
		"item": item,
		"stored": false,
	}
