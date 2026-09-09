class_name DevelopmentPanel
extends Control

## Developer / QA panel exposing the deterministic UI-testing fixtures
## (res://tests/fixtures/ui_fixture.gd). Hidden by default; toggled by the
## DEV button on the combat HUD. All actions operate on the live player's
## inventory in memory — nothing is persisted to disk.

signal panel_closed
## Emitted after any action mutates the player's data/inventory, so the HUD
## can re-sync panels bound to the (possibly replaced) inventory object.
signal data_changed
## Emitted when the DEV panel's town entry is pressed; the HUD switches the
## main view from CombatView to the town hub (TownView).
signal town_view_requested
## Emitted when an AREA STAGES button is pressed; the HUD forwards it to
## grid_combat, which resolves the authored stage through StageRouter.
signal area_stage_enter_requested(area_id: StringName, stage_number: int)

const UIFixtureScript = preload("res://tests/fixtures/ui_fixture.gd")
const SubHeroCatalogResource = preload("res://scripts/sub_hero/sub_hero_catalog.gd")
const SubHeroInstanceResource = preload("res://scripts/sub_hero/sub_hero_instance.gd")
const SubHeroQualityResource = preload("res://scripts/sub_hero/sub_hero_quality.gd")
const StageDatabaseScript = preload("res://scripts/data/stage_database.gd")
const StageTypeScript = preload("res://scripts/data/stage_type.gd")

const SLOT_COUNT: int = 7  # EquipmentSlot.WEAPON .. AMULET

const RARITY_ORDER: Array[int] = [
	EquipmentRarity.COMMON,
	EquipmentRarity.UNCOMMON,
	EquipmentRarity.RARE,
	EquipmentRarity.EPIC,
	EquipmentRarity.LEGENDARY,
	EquipmentRarity.MYTHIC,
]

const COLOR_TEXT := Color("d8cfdf")
const COLOR_MUTED := Color("8f879d")
const COLOR_GOLD := Color("e8c465")
const COLOR_RED := Color("d46a78")

const COLOR_RARITY := {
	EquipmentRarity.COMMON: Color("b9afc6"),
	EquipmentRarity.UNCOMMON: Color("82d49b"),
	EquipmentRarity.RARE: Color("71a9ed"),
	EquipmentRarity.EPIC: Color("b995ef"),
	EquipmentRarity.LEGENDARY: Color("e8af4f"),
	EquipmentRarity.MYTHIC: Color("f078b2"),
}

## Accent per authored StageType, used by the AREA STAGES demo buttons.
const COLOR_STAGE_TYPE := {
	StageTypeScript.COMBAT: COLOR_TEXT,
	StageTypeScript.EVENT: Color("c9bdb4"),
	StageTypeScript.TOWN: COLOR_GOLD,
	StageTypeScript.BOSS: COLOR_RED,
}

var _player: PlayerController
var _slot_rotation: Dictionary = {}
var _status_label: Label


func _ready() -> void:
	_slot_rotation.clear()
	for rarity in RARITY_ORDER:
		_slot_rotation[rarity] = EquipmentSlot.WEAPON
	_build_ui()


func set_player(player: PlayerController) -> void:
	_player = player


func show_panel() -> void:
	visible = true


func hide_panel() -> void:
	visible = false
	panel_closed.emit()


func toggle_panel() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()


## QA entry point for the town hub. Hides the DEV panel and lets the combat HUD
## know it should switch the main view over to TownView.
func open_town() -> void:
	hide_panel()
	town_view_requested.emit()


# ---------------------------------------------------------------------------
# Actions (wired to UIFixture)
# ---------------------------------------------------------------------------

## Generates one fresh item of the given rarity at the player's level and
## drops it straight into the player's inventory. The equipment slot rotates
## on each click so repeated clicks fill the bag with varied slots.
func _generate_item(rarity: int) -> void:
	var player := _get_player()
	if player == null:
		_set_status("No player available")
		return
	var level: int = player.get_level() if player.has_method("get_level") else 1
	var slot: int = int(_slot_rotation.get(rarity, EquipmentSlot.WEAPON))
	_slot_rotation[rarity] = (slot + 1) % SLOT_COUNT
	var item := UIFixtureScript.create_equipment(rarity, slot, level)
	if player.add_equipment(item):
		_set_status("Added  •  %s (lvl %d, %d affix)" % [
			item.get_display_name(),
			item.get_item_level(),
			item.affixes.size(),
		])
		data_changed.emit()
	else:
		_set_status("Could not add item — inventory full?")


## Drops one deterministic healing potion into the player's bag for quick
## manual testing of the consumable popup flow.
func _generate_potion() -> void:
	var player := _get_player()
	if player == null:
		_set_status("No player available")
		return
	var level: int = player.get_level() if player.has_method("get_level") else 1
	var potion := UIFixtureScript.create_potion(level, EquipmentRarity.COMMON)
	if player.add_equipment(potion):
		_set_status("Added  •  %s (lvl %d)" % [potion.get_display_name(), potion.get_item_level()])
		data_changed.emit()
	else:
		_set_status("Could not add potion — inventory full?")


func _fill_demo_inventory() -> void:
	var player := _get_player()
	if player == null:
		_set_status("No player available")
		return
	var added: int = 0
	for item in UIFixtureScript.create_rarity_set():
		if player.add_equipment(item):
			added += 1
	_set_status("Added %d demo items (one per rarity)" % added)
	data_changed.emit()


func _apply_demo_character() -> void:
	var player := _get_player()
	if player == null:
		_set_status("No player available")
		return
	UIFixtureScript.apply_character_to_player(player)
	var level: int = player.player_progression.level if player.player_progression != null else 0
	_set_status("Demo character applied (level %d, %d items)" % [level, player.get_inventory().get_item_count()])
	data_changed.emit()


func _clear_inventory() -> void:
	var player := _get_player()
	if player == null:
		_set_status("No player available")
		return
	var inventory: EquipmentInventory = player.get_inventory()
	var removed: int = 0
	for item in inventory.get_items():
		if not item.is_equipped and inventory.remove_item(item):
			removed += 1
	_set_status("Removed %d bag item(s)" % removed)
	data_changed.emit()


## Directly grants one Sub Hero for QA/agent testing. This intentionally
## bypasses Gold, summon odds, and the Shop resource table while still using
## the normal ownership service, so duplicate conversion remains testable.
## An empty hero_id selects the first catalog entry deterministically.
func dev_summon_sub_hero(hero_id: StringName = &"", level: int = 1) -> Dictionary:
	var player := _get_player()
	if player == null:
		_set_status("No player available")
		return {"success": false, "reason": "PLAYER_UNAVAILABLE"}
	var data: SubHeroData = SubHeroCatalogResource.get_data(hero_id)
	if data == null and hero_id.is_empty():
		var all_data: Array[SubHeroData] = SubHeroCatalogResource.get_all_data()
		if not all_data.is_empty():
			data = all_data[0]
	if data == null:
		_set_status("Unknown Sub Hero: %s" % String(hero_id))
		return {"success": false, "reason": "UNKNOWN_SUB_HERO", "hero_id": hero_id}
	var result: Dictionary = player.add_sub_hero(SubHeroInstanceResource.new(data.id, maxi(level, 1)))
	result["success"] = true
	result["reason"] = ""
	result["data"] = data
	result["level"] = int(result.get("level", 1))
	_set_status("DEV Sub Hero  •  %s%s" % [
		data.display_name,
		" (duplicate)" if not bool(result.get("is_new", false)) else "",
	])
	data_changed.emit()
	return result


func _get_player() -> PlayerController:
	if _player != null and is_instance_valid(_player):
		return _player
	return null


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.012, 0.01, 0.018, 0.85)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_full_rect(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	content.add_child(_build_header())
	content.add_child(_section_title("TOWN"))
	content.add_child(_build_town_actions())
	content.add_child(_section_title("AREA STAGES"))
	content.add_child(_build_area_stage_actions())
	content.add_child(_section_title("GENERATE ITEM"))
	content.add_child(_build_rarity_grid())
	content.add_child(_section_title("FIXTURES"))
	content.add_child(_build_fixture_actions())
	content.add_child(_section_title("SUB HERO FIXTURES"))
	content.add_child(_build_subhero_actions())
	content.add_child(_section_title("COMBAT FX TEST"))
	content.add_child(_build_fx_actions())

	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.add_theme_color_override("font_color", COLOR_MUTED)
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status_label)


func _add_full_rect(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(node)


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "DEVELOPMENT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(44, 40)
	close.add_theme_font_size_override("font_size", 16)
	close.add_theme_color_override("font_color", COLOR_TEXT)
	close.pressed.connect(hide_panel)
	header.add_child(close)
	return header


func _build_town_actions() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_make_button("OPEN TOWN VIEW", COLOR_GOLD, open_town))
	return box


## Builds a "enter this authored area stage" demo list straight from the area's
## StageDatabase (stage_type driven, never stage-number hard-coded). Only the
## showcase nodes are shown: stage 1 plus every stage that differs from the
## area's shared default rule (Forest -> 01 COMBAT / 06 EVENT / 08 TOWN / 10 BOSS).
func _build_area_stage_actions() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var database: Resource = StageDatabaseScript.load_area(&"forest")
	if database == null:
		var empty := Label.new()
		empty.text = "No area authored"
		empty.add_theme_color_override("font_color", COLOR_MUTED)
		grid.add_child(empty)
		return grid
	var default_type: int = int(database.get("default_stage_type"))
	for number in range(1, int(database.get("stage_count")) + 1):
		var stage: Resource = database.call("get_stage", number)
		if stage == null:
			continue
		var stage_type: int = int(stage.get("stage_type"))
		if number != 1 and stage_type == default_type:
			continue
		var label: String = "FOREST %02d · %s" % [number, StageTypeScript.get_display_name(stage_type)]
		var accent: Color = COLOR_STAGE_TYPE.get(stage_type, COLOR_TEXT)
		grid.add_child(_make_button(label, accent, _enter_area_stage.bind(&"forest", number)))
	return grid


## QA entry point for an authored area stage: hides the DEV panel and lets the
## HUD/grid_combat resolve the stage through StageRouter.
func _enter_area_stage(area_id: StringName, stage_number: int) -> void:
	hide_panel()
	area_stage_enter_requested.emit(area_id, stage_number)


func _build_rarity_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for rarity in RARITY_ORDER:
		var color: Color = COLOR_RARITY.get(rarity, COLOR_TEXT)
		grid.add_child(_make_button(EquipmentRarity.get_display_name(rarity), color, _generate_item.bind(rarity)))
	return grid


func _build_fixture_actions() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_make_button("ADD POTION", Color("82d49b"), _generate_potion))
	box.add_child(_make_button("FILL DEMO INVENTORY", Color("c9bdb4"), _fill_demo_inventory))
	box.add_child(_make_button("APPLY DEMO CHARACTER", Color("e8af4f"), _apply_demo_character))
	box.add_child(_make_button("CLEAR BAG", COLOR_RED, _clear_inventory))
	return box


func _build_subhero_actions() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for data in SubHeroCatalogResource.get_all_data():
		var accent: Color = SubHeroQualityResource.get_color(data.quality)
		grid.add_child(_make_button("ADD %s" % data.display_name, accent, dev_summon_sub_hero.bind(data.id)))
	return grid


## Combat presentation test buttons: play each feedback case against the live
## combat scene via CombatPresentationSystem.test_effect() (visuals only — no
## damage, turn or grid state is touched).
func _build_fx_actions() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var cases: Array = [
		["FX NORMAL", &"normal", COLOR_TEXT],
		["FX CRITICAL", &"critical", COLOR_GOLD],
		["FX HEAVY", &"heavy", COLOR_RED],
		["FX MISS", &"miss", COLOR_MUTED],
		["FX BLOCK", &"block", Color("9fb6c9")],
		["FX FIRE", &"fire", Color("e07840")],
		["FX LIGHTNING", &"lightning", Color("d8c8ff")],
		["FX HEAL", &"heal", Color("82d49b")],
		["FX DEATH", &"death", Color("b06ae0")],
	]
	for entry in cases:
		grid.add_child(_make_button(entry[0], entry[2], _test_combat_fx.bind(entry[1])))
	return grid


func _test_combat_fx(case: StringName) -> void:
	var presentation := _get_presentation_system()
	if presentation == null:
		_set_status("Combat presentation unavailable")
		return
	presentation.test_effect(case)
	_set_status("FX  •  %s" % String(case).to_upper())


func _get_presentation_system() -> CombatPresentationSystem:
	var tree := get_tree()
	if tree == null:
		return null
	# Main scene boots as Main/grid_combat; running grid_combat.tscn directly has no
	# Main wrapper.
	var node := tree.root.get_node_or_null(^"Main/grid_combat/CombatPresentation")
	if node == null:
		node = tree.root.get_node_or_null(^"grid_combat/CombatPresentation")
	return node as CombatPresentationSystem


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLOR_GOLD)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _make_button(text: String, accent: Color, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.145, 0.125, 0.196), accent.darkened(0.5), 1))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.231, 0.192, 0.29), accent, 2))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.341, 0.259, 0.149), accent.lightened(0.2), 2))
	button.pressed.connect(callback)
	return button


func _button_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10.0
	style.content_margin_top = 7.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 7.0
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.062, 0.10, 0.98)
	style.border_color = Color("6c5331")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style
