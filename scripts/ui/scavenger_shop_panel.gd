class_name ScavengerShopPanel
extends Control

## The Scavenger Shop: a town facility with two tabs — SELL, which prices the player's own
## bag and warehouse at the §19 `SellPrice`, and BUYBACK, which holds what the player gave
## up so a mistake stays recoverable.
##
## Split of responsibilities
## -------------------------
## The panel owns no rules. It renders the shop's entries, forwards a purchase to
## ScavengerShop and shows the failure the service reports — the same split the
## Sub Hero shop uses (panel renders, service decides).
##
## Why a buyback exists next to a one-per-save drop
## ------------------------------------------------
## The Beginner Sword is granted once per save by the Stage 10 boss. Discarding it
## would otherwise destroy the player's only copy, so a discard puts it here and the
## shop sells it back. Buying it back only returns OWNERSHIP: the "already granted"
## record belongs to the loot path's one-shot store, which this panel and its
## service never write, so the boss cannot be re-armed by a purchase.

signal panel_closed
signal data_changed

const ScavengerShopResource = preload("res://scripts/shop/scavenger_shop.gd")

## The shop's tabs. The row is built from this table, so a tab is a data addition instead
## of a panel rewrite. SELL is listed first because it is the action a player comes here
## for; BUYBACK opens by default to preserve the original entry point.
const TABS: Array[String] = ["SELL", "BUYBACK"]

enum Tab { SELL, BUYBACK }

const COLOR_PANEL := Color("120f1b")
const COLOR_PANEL_ALT := Color("1a1524")
const COLOR_TEXT := Color("eee7d8")
const COLOR_MUTED := Color("9d93ae")
const COLOR_GOLD := Color("e8c465")
const COLOR_GOLD_BRIGHT := Color("f4d28b")
const COLOR_RED := Color("d46a78")
const COLOR_GREEN := Color("89c797")
const COLOR_BORDER := Color("604a2b")

@export var shop: ScavengerShop

var _player: Node
var _panel: PanelContainer
var _gold_label: Label
var _status_label: Label
var _rows_content: VBoxContainer
var _tab_buttons: Array[Button] = []
var _active_tab: int = Tab.BUYBACK
var _bulk_row: HBoxContainer
var _bulk_sell_button: Button
var _bulk_confirm: ConfirmationDialog


func _ready() -> void:
	if shop == null:
		shop = ScavengerShopResource.new()
	_build_ui()
	_layout_panel()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_panel()


## Binds the player whose discards stock the book. Re-binding is safe: a DEV panel
## entry can replace the player's inventory object, so the old signal is dropped.
func set_player(player: Node) -> void:
	if _player != null and is_instance_valid(_player) \
			and _player.has_signal("equipment_discarded") \
			and _player.is_connected("equipment_discarded", _on_equipment_discarded):
		_player.disconnect("equipment_discarded", _on_equipment_discarded)
	_player = player
	_adopt_player_shop()
	if _player != null and is_instance_valid(_player) and _player.has_signal("equipment_discarded") \
			and not _player.is_connected("equipment_discarded", _on_equipment_discarded):
		_player.connect("equipment_discarded", _on_equipment_discarded)
	_refresh()


## Adopts the player's shared buyback book (gameplay-spec §19). The Scavenger Shop and the
## warehouse stock ONE book, so an item given up in either place is recoverable here.
func _adopt_player_shop() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("get_scavenger_shop"):
		return
	var player_shop: ScavengerShop = _player.call("get_scavenger_shop")
	if player_shop != null:
		shop = player_shop


func show_panel() -> void:
	_refresh()
	visible = true


func hide_panel() -> void:
	visible = false
	panel_closed.emit()


func toggle_panel() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.015, 0.04, 0.82)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL, COLOR_BORDER, 2, 10))
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	content.add_child(_build_header())

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color("8c5e26")
	content.add_child(rule)

	content.add_child(_build_tab_row())

	_bulk_row = _build_bulk_row()
	content.add_child(_bulk_row)

	var hint := Label.new()
	hint.text = "Sell what you no longer need — and buy back what you gave up."
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	hint.add_theme_font_size_override("font_size", 10)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_rows_content = VBoxContainer.new()
	_rows_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows_content)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", COLOR_MUTED)
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 30)
	content.add_child(_status_label)

	add_child(_build_bulk_confirm())


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 44)
	header.add_theme_constant_override("separation", 8)

	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.add_theme_constant_override("separation", 0)
	header.add_child(title_block)

	var title := Label.new()
	title.text = "SCAVENGER SHOP"
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 18)
	title_block.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "拾荒商店 · 回收"
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	subtitle.add_theme_font_size_override("font_size", 10)
	title_block.add_child(subtitle)

	_gold_label = Label.new()
	_gold_label.text = "GOLD 0"
	_gold_label.add_theme_color_override("font_color", COLOR_GOLD_BRIGHT)
	_gold_label.add_theme_font_size_override("font_size", 13)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_gold_label)

	var close_button := _make_button("✕", false)
	close_button.custom_minimum_size = Vector2(40, 34)
	close_button.pressed.connect(hide_panel)
	header.add_child(close_button)
	return header


func _build_tab_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for tab_index in TABS.size():
		var button := _make_button(TABS[tab_index], tab_index == _active_tab)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_tab_pressed.bind(tab_index))
		row.add_child(button)
		_tab_buttons.append(button)
	return row


## The SELL tab's bulk action. It is a FILTER over the same list the rows render, not a second
## selling rule: every target still goes through the player's `sell_item`, so one sale is one
## price, one gold credit and one buyback entry, exactly as a single press would give.
func _build_bulk_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bulk_sell_button = _make_button("SELL ALL COMMON", false)
	_bulk_sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bulk_sell_button.custom_minimum_size = Vector2(0, 30)
	_bulk_sell_button.pressed.connect(_on_bulk_sell_pressed)
	row.add_child(_bulk_sell_button)
	return row


## A bulk sale is the one irreversible-feeling press in the shop, so it is confirmed once
## with the count and the gold it will pay instead of firing on a mis-click.
func _build_bulk_confirm() -> ConfirmationDialog:
	_bulk_confirm = ConfirmationDialog.new()
	_bulk_confirm.title = "SELL ALL COMMON"
	_bulk_confirm.dialog_autowrap = true
	_bulk_confirm.ok_button_text = "SELL"
	_bulk_confirm.cancel_button_text = "CANCEL"
	_bulk_confirm.confirmed.connect(_on_bulk_sell_confirmed)
	return _bulk_confirm


func _layout_panel() -> void:
	if _panel == null:
		return
	var half_width: float = minf(300.0, maxf(size.x * 0.5 - 20.0, 140.0))
	var half_height: float = minf(300.0, maxf(size.y * 0.5 - 20.0, 180.0))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -half_width
	_panel.offset_top = -half_height
	_panel.offset_right = half_width
	_panel.offset_bottom = half_height


func _on_tab_pressed(tab_index: int) -> void:
	if _active_tab == tab_index:
		return
	_active_tab = tab_index
	for index in _tab_buttons.size():
		var button: Button = _tab_buttons[index]
		_style_tab_button(button, index == _active_tab)
	_refresh()


## A discarded or sold item becomes buyback stock, priced at the stage it was given up on.
## The panel is the only listener, so no discard path has to know the shop exists for the
## item to become recoverable.
func _on_equipment_discarded(item: EquipmentInstance) -> void:
	if shop == null or not shop.record(item, _current_stage()):
		return
	_refresh()
	_set_status("%s is waiting in buyback." % item.get_display_name(), COLOR_GOLD)


func _on_buy_pressed(item: EquipmentInstance) -> void:
	if shop == null or _player == null:
		_set_status("Shop unavailable.", COLOR_RED)
		return
	var result: Dictionary = shop.buy_back(_player, item)
	if not bool(result.get("success", false)):
		_set_status(_get_failure_text(str(result.get("reason", ""))), COLOR_RED)
		_refresh()
		return
	var bought: EquipmentInstance = result.get("item") as EquipmentInstance
	var bought_name: String = bought.get_display_name() if bought != null else "Item"
	var where: String = "warehouse" if bool(result.get("stored", false)) else "bag"
	_set_status(
		"Bought back %s for %d G (%s)." % [bought_name, int(result.get("cost", 0)), where],
		COLOR_GREEN
	)
	_refresh()
	data_changed.emit()


## Sells an item from the SELL tab at its §19 price. The player service owns the price, the
## gold and the buyback stocking; the panel only reports the outcome.
func _on_sell_pressed(item: EquipmentInstance, from_storage: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		_set_status("Shop unavailable.", COLOR_RED)
		return
	var result: Dictionary = _player.call("sell_item", item, from_storage)
	if not bool(result.get("success", false)):
		_set_status(_get_sell_failure_text(str(result.get("reason", ""))), COLOR_RED)
		_refresh()
		return
	_set_status(
		"Sold %s for %s G." % [item.get_display_name(), ItemEconomy.format_gold(int(result.get("price", 0)))],
		COLOR_GREEN
	)
	_refresh()
	data_changed.emit()


## The SELL tab's bulk press: nothing is sold until the player confirms the count and the
## gold it pays.
func _on_bulk_sell_pressed() -> void:
	var targets: Array[Dictionary] = _get_common_sell_targets()
	if targets.is_empty():
		_set_status("No common gear in the bag or the warehouse.", COLOR_MUTED)
		return
	var total: int = 0
	for target in targets:
		total += _get_row_price(target["item"] as EquipmentInstance, true)
	if _bulk_confirm == null:
		_on_bulk_sell_confirmed()
		return
	_bulk_confirm.dialog_text = (
		"Sell %d common item%s for %s G?\n\nRecoverable gear lands in BUYBACK, which holds the most recent %d."
		% [
			targets.size(),
			"" if targets.size() == 1 else "s",
			ItemEconomy.format_gold(total),
			shop.capacity if shop != null else 0,
		]
	)
	_bulk_confirm.popup_centered()


## Sells every confirmed target through the same `sell_item` a single row uses — the player
## service prices it, pays the gold and stocks the buyback, so a bulk sale is N ordinary
## sales and never a second code path with its own arithmetic.
func _on_bulk_sell_confirmed() -> void:
	if _player == null or not is_instance_valid(_player):
		_set_status("Shop unavailable.", COLOR_RED)
		return
	var sold: int = 0
	var total: int = 0
	var skipped: int = 0
	for target in _get_common_sell_targets():
		var item: EquipmentInstance = target["item"]
		var result: Dictionary = _player.call("sell_item", item, bool(target["from_storage"]))
		if bool(result.get("success", false)):
			sold += 1
			total += int(result.get("price", 0))
		else:
			skipped += 1
	if sold == 0:
		_set_status("Nothing common could be sold.", COLOR_RED)
		_refresh()
		return
	_set_status(
		"Sold %d common item%s for %s G.%s" % [
			sold,
			"" if sold == 1 else "s",
			ItemEconomy.format_gold(total),
			"" if skipped == 0 else " %d skipped." % skipped,
		],
		COLOR_GREEN
	)
	_refresh()
	data_changed.emit()


## What the bulk action may sell: COMMON ("white") gear only, and never worn gear — the
## shop's own rule is that a worn item comes off first, and a bulk press must not undress
## the player. Bag first, then warehouse, so the sale order matches the SELL tab's list.
func _get_common_sell_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if _player == null or not is_instance_valid(_player):
		return targets
	for item in _player.call("get_inventory").get_bag_items():
		if _is_common_sellable(item):
			targets.append({"item": item, "from_storage": false})
	for item in _player.call("get_storage").get_items():
		if _is_common_sellable(item):
			targets.append({"item": item, "from_storage": true})
	return targets


func _is_common_sellable(item: EquipmentInstance) -> bool:
	if item == null or item.is_equipped:
		return false
	return item.get_rarity() == EquipmentRarity.COMMON


func _update_bulk_row() -> void:
	if _bulk_row == null:
		return
	var sell_mode: bool = _active_tab == Tab.SELL
	_bulk_row.visible = sell_mode
	if not sell_mode or _bulk_sell_button == null:
		return
	var count: int = _get_common_sell_targets().size()
	_bulk_sell_button.disabled = count == 0
	_bulk_sell_button.text = (
		"一键卖白装 · SELL ALL COMMON (%d)" % count
		if count > 0
		else "一键卖白装 · NO COMMON GEAR"
	)


func _get_sell_failure_text(reason: String) -> String:
	match reason:
		"ITEM_EQUIPPED":
			return "Unequip it before selling."
		"ITEM_NOT_OWNED":
			return "That item is no longer yours."
		_:
			return "That item cannot be sold."


func _refresh() -> void:
	if _gold_label != null:
		_gold_label.text = "GOLD %d" % _get_gold()
	_update_bulk_row()
	_render_rows()


func _render_rows() -> void:
	if _rows_content == null:
		return
	for child in _rows_content.get_children():
		child.queue_free()
	var entries: Array[EquipmentInstance] = _get_active_entries()
	var sell_mode: bool = _active_tab == Tab.SELL
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = (
			"Nothing to sell — your bag and the warehouse are empty."
			if sell_mode
			else "Buyback is empty. Discard something and it will show up here."
		)
		empty_label.add_theme_color_override("font_color", COLOR_MUTED)
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows_content.add_child(empty_label)
		return
	for item in entries:
		if item != null:
			_rows_content.add_child(_make_entry_row(item, sell_mode))


## The SELL tab lists the player's OWN items (bag, then warehouse); BUYBACK lists what the
## shop holds. The panel still owns no rules — it only decides which list to render.
func _get_active_entries() -> Array[EquipmentInstance]:
	var entries: Array[EquipmentInstance] = []
	if _active_tab != Tab.SELL:
		return shop.get_entries() if shop != null else entries
	if _player == null or not is_instance_valid(_player):
		return entries
	var inventory: Variant = _player.call("get_inventory")
	var storage: Variant = _player.call("get_storage")
	for item in inventory.get_bag_items():
		entries.append(item)
	for item in storage.get_items():
		entries.append(item)
	return entries


## The stage every price is measured against (gameplay-spec §19). The player carries it;
## without a player the shop falls back to stage 1.
func _current_stage() -> int:
	if _player == null or not is_instance_valid(_player):
		return 1
	return maxi(int(_player.get("current_stage_number")), 1)


func _make_entry_row(item: EquipmentInstance, sell_mode: bool = false) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL_ALT, Color("3f344c"), 1, 6))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(margin)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	margin.add_child(line)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 0)
	line.add_child(identity)

	var name_label := Label.new()
	name_label.text = item.get_display_name()
	name_label.add_theme_color_override("font_color", _get_rarity_color(item.get_rarity()))
	name_label.add_theme_font_size_override("font_size", 13)
	identity.add_child(name_label)

	var detail := Label.new()
	detail.text = "%s · %s · Power %d" % [
		EquipmentSlot.get_display_name(item.get_slot()),
		EquipmentRarity.get_display_name(item.get_rarity()),
		roundi(item.get_equipment_score()),
	]
	detail.add_theme_color_override("font_color", COLOR_MUTED)
	detail.add_theme_font_size_override("font_size", 9)
	identity.add_child(detail)

	var price_label := Label.new()
	price_label.text = "%s G" % ItemEconomy.format_gold(_get_row_price(item, sell_mode))
	price_label.add_theme_color_override("font_color", COLOR_GOLD_BRIGHT)
	price_label.add_theme_font_size_override("font_size", 12)
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(price_label)

	var action_button := _make_button("SELL" if sell_mode else "BUY BACK", true)
	action_button.custom_minimum_size = Vector2(88, 30)
	if sell_mode:
		var from_storage: bool = _player != null and is_instance_valid(_player) \
			and _player.call("get_storage").has_item(item)
		action_button.pressed.connect(_on_sell_pressed.bind(item, from_storage))
	else:
		action_button.pressed.connect(_on_buy_pressed.bind(item))
	line.add_child(action_button)
	return row


## What the row shows: BUYBACK shows the price the item was stocked at, SELL shows what
## selling it right now would pay (§19).
func _get_row_price(item: EquipmentInstance, sell_mode: bool) -> int:
	if sell_mode:
		return ItemEconomy.get_sell_price(item, _current_stage())
	return shop.get_price(item) if shop != null else 0


func _set_status(text: String, color: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _get_gold() -> int:
	if _player == null or not is_instance_valid(_player):
		return 0
	var progression: PlayerProgression = _player.get("player_progression") as PlayerProgression
	if progression == null:
		return 0
	return progression.gold


func _get_failure_text(reason: String) -> String:
	match reason:
		"INSUFFICIENT_GOLD":
			return "Not enough gold."
		"ITEM_NOT_IN_BUYBACK":
			return "That item is no longer in buyback."
		"INVENTORY_UNAVAILABLE":
			return "Bag and warehouse are both full."
		"PLAYER_UNAVAILABLE", "PROGRESSION_UNAVAILABLE":
			return "Shop unavailable."
		_:
			return "Purchase failed (%s)." % reason


func _get_rarity_color(rarity: int) -> Color:
	match rarity:
		EquipmentRarity.UNCOMMON:
			return COLOR_GREEN
		EquipmentRarity.RARE:
			return Color("71a9ed")
		EquipmentRarity.EPIC:
			return Color("b995ef")
		EquipmentRarity.LEGENDARY:
			return Color("e8af4f")
		EquipmentRarity.MYTHIC:
			return Color("f078b2")
		_:
			return Color("b9afc6")


func _make_button(text: String, highlighted: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_font_size_override("font_size", 12)
	_style_tab_button(button, highlighted)
	return button


## Buyback entries are buttons too, so one highlight rule covers tabs and actions.
func _style_tab_button(button: Button, highlighted: bool) -> void:
	var accent: Color = COLOR_GOLD if highlighted else Color("3f344c")
	var background: Color = Color("241a30") if highlighted else Color("0e0c14")
	button.add_theme_stylebox_override("normal", _make_style(background, accent, 1, 6))
	button.add_theme_stylebox_override("hover", _make_style(Color("2b2036"), COLOR_GOLD, 2, 6))
	button.add_theme_stylebox_override("pressed", _make_style(Color("443022"), COLOR_GOLD_BRIGHT, 2, 6))
	button.add_theme_stylebox_override("disabled", _make_style(Color("0b0a10"), Color("2a2334"), 1, 6))
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED)


func _make_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style
