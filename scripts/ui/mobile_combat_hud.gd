class_name MobileCombatHUD
extends CanvasLayer

## Portrait-first HUD for the existing combat scene.
## The HUD only forwards input to the existing player and turn systems.
signal move_requested(direction: Vector2i)
signal attack_requested
signal skill_requested(skill_id: StringName)
signal item_requested
signal end_turn_requested
signal next_stage_requested
signal auto_toggle_requested
signal farming_toggle_requested
signal game_speed_requested(speed: int)

@onready var _stage_manager: Node = get_parent().get_node_or_null("StageManager")
@onready var _turn_manager: Node = get_parent().get_node_or_null("TurnManager")
@onready var _player: Node = get_parent().get_node_or_null("Player")

@onready var _header_row: HeaderRow = get_node_or_null("Root/SafeArea/MainContent/Content/MainLayout/TopPanel/Margin/Content/Header") as HeaderRow
@onready var _encounter_label: Label = %EncounterLabel
@onready var _sub_hero_row: Control = %SubHeroRow
@onready var _player_hp_bar: ProgressBar = %PlayerHPBar
@onready var _player_hp_value: Label = %PlayerHPValue
@onready var _combat_info_label: Label = %CombatInfoLabel
@onready var _event_label: Label = %EventLabel
@onready var _skills_button: Button = %SkillsButton
@onready var _speed_x1_button: Button = %SpeedX1Button
@onready var _speed_x2_button: Button = %SpeedX2Button
@onready var _speed_fastest_button: Button = %SpeedFastestButton
@onready var _shop_button: Button = %ShopButton
@onready var _bestiary_button: Button = %BestiaryButton
@onready var _dev_button: Button = %DevButton
@onready var _critical_label: Label = %CriticalLabel
@onready var _state_banner: PanelContainer = %StateBanner
@onready var _state_label: Label = %StateLabel
@onready var _inventory_panel: EquipmentInventoryPanel = %InventoryPanel
@onready var _bestiary_panel: EnemyBestiaryPanel = %EnemyBestiaryPanel
@onready var _development_panel: DevelopmentPanel = %DevelopmentPanel
@onready var _skill_panel: SkillPanel = %SkillPanel
@onready var _combat_log: CombatLogPanel = %CombatLogPanel
@onready var _combat_section: Control = %CombatSection
@onready var _shop_panel: SubHeroShopPanel = %SubHeroShopPanel
# Keep this reference as Control so a cold headless harness does not depend on
# the newly-added panel class being present in Godot's global class cache.
@onready var _assignment_panel: Control = %SubHeroAssignmentPanel

@onready var _main_navigation: MainNavigation = %MainNavigation
@onready var _enemy_summary_panel: EnemySummaryPanel = %EnemySummaryPanel
@onready var _combat_actions: CombatActions = %CombatActions


var _critical_time_remaining: float = 0.0
## Cached toggle state so the HUD can gate the NEXT STAGE button without
## reaching into the AutoCombatController (kept for isolated headless tests).
var _auto_enabled_cache: bool = false
var _farming_enabled_cache: bool = false


func _ready() -> void:
	_combat_actions.attack_requested.connect(func() -> void: attack_requested.emit())
	_combat_actions.skill_requested.connect(func(skill_id: StringName) -> void: skill_requested.emit(skill_id))
	_combat_actions.item_requested.connect(func() -> void: item_requested.emit())
	_combat_actions.end_turn_requested.connect(func() -> void: end_turn_requested.emit())
	_combat_actions.next_stage_requested.connect(func() -> void: next_stage_requested.emit())
	_combat_actions.auto_toggle_requested.connect(func() -> void: auto_toggle_requested.emit())
	_combat_actions.farming_toggle_requested.connect(func() -> void: farming_toggle_requested.emit())
	_skills_button.pressed.connect(_on_skills_button_pressed)
	_speed_x1_button.pressed.connect(func() -> void: game_speed_requested.emit(0))
	_speed_x2_button.pressed.connect(func() -> void: game_speed_requested.emit(1))
	_speed_fastest_button.pressed.connect(func() -> void: game_speed_requested.emit(2))
	_shop_button.pressed.connect(_on_shop_button_pressed)
	_bestiary_button.pressed.connect(_on_bestiary_button_pressed)
	_dev_button.pressed.connect(_on_dev_button_pressed)
	_main_navigation.character_pressed.connect(_on_character_navigation_pressed)
	_main_navigation.inventory_pressed.connect(_on_inventory_navigation_pressed)
	_main_navigation.shop_pressed.connect(_on_shop_button_pressed)
	_inventory_panel.set_player(_player)
	_development_panel.set_player(_player)
	_development_panel.data_changed.connect(_on_dev_data_changed)
	_skill_panel.set_player(_player)
	_shop_panel.set_player(_player)
	_shop_panel.data_changed.connect(_on_shop_data_changed)
	_assignment_panel.set_player(_player)
	_assignment_panel.data_changed.connect(_on_assignment_data_changed)
	if _sub_hero_row.has_signal("slot_selected"):
		_sub_hero_row.slot_selected.connect(_on_sub_hero_slot_selected)
	_inventory_panel.visibility_changed.connect(_on_overlay_panel_visibility_changed)
	_bestiary_panel.visibility_changed.connect(_on_overlay_panel_visibility_changed)
	_development_panel.visibility_changed.connect(_on_overlay_panel_visibility_changed)
	_skill_panel.visibility_changed.connect(_on_overlay_panel_visibility_changed)
	_shop_panel.visibility_changed.connect(_on_overlay_panel_visibility_changed)
	_assignment_panel.visibility_changed.connect(_on_overlay_panel_visibility_changed)
	if _player != null and _player.has_signal("sub_hero_collection_changed"):
		_player.sub_hero_collection_changed.connect(_on_sub_hero_state_changed)
	if _player != null and _player.has_signal("sub_hero_slots_changed"):
		_player.sub_hero_slots_changed.connect(_on_sub_hero_state_changed)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_refresh_sub_hero_slots()
	_refresh()


func _process(delta: float) -> void:
	# State changes can come from combat signals, enemy AI, or stage generation.
	# A lightweight refresh keeps the HUD in sync without coupling it to gameplay.
	if _critical_time_remaining > 0.0:
		_critical_time_remaining = maxf(_critical_time_remaining - delta, 0.0)
		_critical_label.modulate.a = clampf(_critical_time_remaining / 0.8, 0.0, 1.0)
		if is_zero_approx(_critical_time_remaining):
			_critical_label.visible = false
	_refresh()


func _on_viewport_size_changed() -> void:
	_refresh()

func _on_shop_button_pressed() -> void:
	_shop_panel.toggle_panel()

func _on_character_navigation_pressed() -> void:
	_inventory_panel.show_inventory()


func _on_inventory_navigation_pressed() -> void:
	_inventory_panel.toggle_inventory()


func _on_bestiary_button_pressed() -> void:
	_bestiary_panel.toggle_bestiary()


func _on_dev_button_pressed() -> void:
	_development_panel.toggle_panel()


func _on_skills_button_pressed() -> void:
	_skill_panel.toggle_panel()


## The combat log only belongs on the combat screen. Hide it while any overlay
## panel (inventory / bestiary / development) is open so it never covers them.
## visibility_changed fires on every show/hide path (button, ui_cancel, ...).
func _on_overlay_panel_visibility_changed() -> void:
	if _combat_log == null:
		return
	_combat_log.visible = not (
	_inventory_panel.visible or _development_panel.visible
		or _skill_panel.visible or _shop_panel.visible or _assignment_panel.visible
	)


func _on_dev_data_changed() -> void:
	# The dev panel can replace the player's inventory object (demo character),
	# which orphans panels still bound to the old object. Re-bind and refresh.
	_inventory_panel.set_player(_player)
	_skill_panel.set_player(_player)
	_shop_panel.set_player(_player)
	_assignment_panel.set_player(_player)
	_refresh()


func _on_shop_data_changed() -> void:
	_refresh_sub_hero_slots()
	_refresh()


func _on_assignment_data_changed() -> void:
	_refresh_sub_hero_slots()
	_refresh()


func _on_sub_hero_slot_selected(slot_index: int) -> void:
	_assignment_panel.show_for_slot(slot_index)


func _on_sub_hero_state_changed() -> void:
	_refresh_sub_hero_slots()


func _refresh_sub_hero_slots() -> void:
	if _player != null and _player.has_method("get_active_sub_hero_entries"):
		set_sub_hero_slots(_player.get_active_sub_hero_entries())


func _on_move_up_pressed() -> void:
	move_requested.emit(Vector2i.UP)


func _on_move_left_pressed() -> void:
	move_requested.emit(Vector2i.LEFT)


func _on_move_down_pressed() -> void:
	move_requested.emit(Vector2i.DOWN)


func _on_move_right_pressed() -> void:
	move_requested.emit(Vector2i.RIGHT)


func _refresh() -> void:
	if _stage_manager == null or _turn_manager == null or _player == null:
		return
	var stage_state: StageState = _stage_manager.get("stage_state") as StageState
	if stage_state == null:
		return

	if _header_row != null:
		_header_row.stage_number = stage_state.stage_number
		_header_row.turn_phase = _turn_manager.get_phase()
	_encounter_label.text = _get_encounter_text(stage_state)
	if _enemy_summary_panel != null:
		var spawned_enemies: Array[EnemyController] = _stage_manager.get_spawned_enemies() if _stage_manager.has_method("get_spawned_enemies") else []
		_enemy_summary_panel.update_enemies(spawned_enemies)
	_event_label.text = str(get_parent().get("_last_move_text"))
	var inventory: EquipmentInventory = _player.get_inventory() if _player.has_method("get_inventory") else null
	_skills_button.text = "SKILLS %d" % _player.get_skill_points()

	var player_stats: PlayerStats = _player.get("player_stats") as PlayerStats
	var player_progression: PlayerProgression = _player.get("player_progression") as PlayerProgression
	var player_level: int = player_progression.level if player_progression != null else 1
	var current_hp: int = player_stats.current_hp if player_stats != null else 0
	var max_hp: int = player_stats.max_hp if player_stats != null else 0
	var experience_ratio: float = player_progression.get_experience_ratio() if player_progression != null else 0.0
	_main_navigation.set_player_status(current_hp, max_hp, player_level, 0, 0, experience_ratio)
	if player_progression != null and _header_row != null:
		_header_row.gold = player_progression.gold
	if player_stats != null:
		_player_hp_bar.max_value = maxi(player_stats.max_hp, 1)
		_player_hp_bar.value = clampi(player_stats.current_hp, 0, maxi(player_stats.max_hp, 1))
		_player_hp_value.text = "%d / %d" % [player_stats.current_hp, player_stats.max_hp]
		var cell: Vector2i = _player.get("grid_position")
		var movement_remaining: int = int(_player.get("movement_points_remaining"))
		_combat_info_label.text = "MP %d / %d   •   CELL %d, %d" % [movement_remaining, player_stats.movement_points, cell.x + 1, cell.y + 1]

	_update_buttons(player_stats)


func _get_target() -> Node:
	if _player.has_method("get_target"):
		var target: Node = _player.call("get_target") as Node
		if target != null and is_instance_valid(target) and not bool(target.get("_is_defeated")):
			return target
	return null


func _update_buttons(player_stats: PlayerStats) -> void:
	var player_turn: bool = _turn_manager.get_phase() == TurnState.PLAYER_TURN
	var input_enabled: bool = bool(_player.get("is_selected")) and bool(_player.call("is_input_enabled"))
	var can_attack: bool = player_turn and input_enabled and _get_target() != null
	_combat_actions.set_attack_usable(can_attack)
	var can_use_skill: bool = player_turn and input_enabled
	_combat_actions.set_skill_usable(SkillCatalog.WHIRLWIND, can_use_skill and _can_use_skill(SkillCatalog.WHIRLWIND))
	_combat_actions.set_skill_usable(SkillCatalog.ARCANE_BOLT, can_use_skill and _can_use_skill(SkillCatalog.ARCANE_BOLT))
	_combat_actions.set_skill_usable(SkillCatalog.EXECUTION_STRIKE, can_use_skill and _can_use_skill(SkillCatalog.EXECUTION_STRIKE))
	var potion_count: int = _player.get_healing_item_count() if _player.has_method("get_healing_item_count") else 0
	var can_use_item: bool = player_turn and input_enabled and potion_count > 0
	if player_stats != null:
		can_use_item = can_use_item and player_stats.current_hp < player_stats.max_hp
	_combat_actions.set_item_button(potion_count, can_use_item)

	var phase: int = _turn_manager.get_phase()
	_combat_actions.set_end_turn_state(phase, player_turn)
	_combat_actions.set_auto_controls(phase)
	_combat_actions.set_next_stage_state(phase, _next_stage_enabled(phase))
	# Victory is a brief status effect, not a modal result screen. Keep the
	# compact banner mouse-transparent so it never covers combat controls.
	_state_banner.visible = phase == TurnState.VICTORY or phase == TurnState.DEFEAT
	_state_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_label.text = "VICTORY" if phase == TurnState.VICTORY else "DEFEAT"
	_state_label.modulate = Color("89c797") if phase == TurnState.VICTORY else Color("d46a78")
	if player_stats == null:
		_combat_actions.disable_player_actions()


## The NEXT STAGE button is enabled only after a full clear while the player
## stands on the stage exit cell, outside FARMING (which re-spawns in place)
## and outside AUTO (which advances on its own after walking to the exit).
func _next_stage_enabled(phase: int) -> bool:
	if phase != TurnState.VICTORY:
		return false
	if _stage_manager == null or not _stage_manager.has_method("is_player_on_stage_exit"):
		return false
	var stage_state_variant: Variant = _stage_manager.get("stage_state")
	if stage_state_variant == null or not bool((stage_state_variant as StageState).get("is_complete")):
		return false
	if _farming_enabled_cache or _auto_enabled_cache:
		return false
	return bool(_stage_manager.call("is_player_on_stage_exit"))


func _can_use_skill(skill_id: StringName) -> bool:
	var combat_scene: Node = get_parent()
	return combat_scene.has_method("can_use_skill") and bool(combat_scene.call("can_use_skill", skill_id))


func set_auto_mode(enabled: bool) -> void:
	_auto_enabled_cache = enabled
	if _combat_actions != null:
		_combat_actions.set_auto_mode(enabled)


func set_farming_mode(enabled: bool) -> void:
	_farming_enabled_cache = enabled
	if _combat_actions != null:
		_combat_actions.set_farming_mode(enabled)


func set_game_speed(speed: int) -> void:
	if _speed_x1_button == null:
		return
	var buttons: Array[Button] = [_speed_x1_button, _speed_x2_button, _speed_fastest_button]
	for index in buttons.size():
		var selected: bool = index == speed
		buttons[index].modulate = Color("89c797") if selected else Color("f0e7d2")


## Binds the three visible combat slots. Ownership/assignment remains outside
## the HUD; entries are dictionaries containing `data` and `instance`.
func set_sub_hero_slots(entries: Array[Dictionary]) -> void:
	if _sub_hero_row != null:
		_sub_hero_row.call("set_slots", entries)


func clear_sub_hero_slots() -> void:
	if _sub_hero_row != null:
		_sub_hero_row.call("clear_slots")


## Keeps the support row immediately below the battlefield and the combat log
## in the remaining gap before the bottom controls.
func layout_battle_support(grid_bottom: float, viewport_size: Vector2) -> void:
	if _sub_hero_row == null:
		return
	const SUB_HERO_HORIZONTAL_MARGIN: float = 24.0
	const GRID_TO_SUB_HERO_GAP: float = 8.0
	const SUPPORT_TO_LOG_GAP: float = 4.0
	const COMBAT_LOG_HEIGHT: float = 120.0

	_sub_hero_row.anchor_left = 0.0
	_sub_hero_row.anchor_top = 0.0
	_sub_hero_row.anchor_right = 1.0
	_sub_hero_row.anchor_bottom = 0.0
	_sub_hero_row.offset_left = SUB_HERO_HORIZONTAL_MARGIN
	_sub_hero_row.offset_right = -SUB_HERO_HORIZONTAL_MARGIN
	var row_top: float = grid_bottom + GRID_TO_SUB_HERO_GAP
	var row_height: float = maxf(_sub_hero_row.get_combined_minimum_size().y, 1.0)
	_sub_hero_row.offset_top = row_top
	_sub_hero_row.offset_bottom = row_top + row_height

	if _combat_log == null:
		return
	var bottom_panel_top: float = viewport_size.y - 300.0
	var log_bottom: float = bottom_panel_top - SUPPORT_TO_LOG_GAP
	var log_top: float = minf(row_top + row_height + SUPPORT_TO_LOG_GAP, log_bottom - COMBAT_LOG_HEIGHT)
	_combat_log.anchor_left = 0.0
	_combat_log.anchor_top = 0.0
	_combat_log.anchor_right = 0.62
	_combat_log.anchor_bottom = 0.0
	_combat_log.offset_left = 16.0
	_combat_log.offset_right = 0.0
	_combat_log.offset_top = log_top
	_combat_log.offset_bottom = log_bottom


## Returns the expanded battlefield area reserved by the combat layout.
func get_combat_section_rect() -> Rect2:
	if _combat_section == null:
		return Rect2()
	return Rect2(_combat_section.global_position, _combat_section.size)


func show_sub_hero_attack_feedback(hero_id: StringName, damage: int) -> bool:
	if _sub_hero_row == null:
		return false
	return bool(_sub_hero_row.call("show_attack_feedback", hero_id, damage))


func start_sub_hero_cooldown(hero_id: StringName, duration: float) -> bool:
	if _sub_hero_row == null:
		return false
	return bool(_sub_hero_row.call("start_cooldown", hero_id, duration))


func reset_sub_hero_cooldowns() -> void:
	if _sub_hero_row != null:
		_sub_hero_row.call("reset_cooldowns")


func get_sub_hero_attack_origin(hero_id: StringName) -> Vector2:
	if _sub_hero_row == null:
		return Vector2.ZERO
	return _sub_hero_row.call("get_slot_center", hero_id)


func present_loot(items: Array[EquipmentInstance], new_best_items: Array[EquipmentInstance] = [], source_name: String = "") -> void:
	var loot_presentation: LootPresentation = %LootPresentation
	loot_presentation.present_loot(items, new_best_items, source_name)


func show_critical_indicator(damage: int) -> void:
	_critical_label.text = "CRITICAL HIT  •  %d" % damage
	_critical_label.visible = true
	_critical_label.modulate = Color("f2c15e")
	_critical_time_remaining = 0.8


## Appends a localized event to the bottom-left combat log.
func log_event(key: String, values: Dictionary = {}) -> void:
	if _combat_log != null:
		_combat_log.append(key, values)


## Switches the combat log's language ("en" / "zh_Hant").
func set_log_locale(locale: String) -> void:
	if _combat_log != null:
		_combat_log.set_locale(locale)


func _get_encounter_text(stage_state: StageState) -> String:
	var encounter: String = "NORMAL ENCOUNTER"
	if stage_state.is_mini_boss_stage:
		encounter = "MINI BOSS"
	elif stage_state.is_special_encounter:
		encounter = "SPECIAL ENCOUNTER"
	return "%s   •   FOES %d / %d" % [encounter, stage_state.defeated_enemy_count, stage_state.spawned_enemy_count]
