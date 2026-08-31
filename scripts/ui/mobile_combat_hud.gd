class_name MobileCombatHUD
extends CanvasLayer

## Portrait-first HUD for the existing combat scene.
## The HUD only forwards input to the existing player and turn systems.
signal move_requested(direction: Vector2i)
signal attack_requested
signal skill_requested(skill_id: StringName)
signal item_requested
signal end_turn_requested
signal auto_toggle_requested
signal auto_stage_toggle_requested
signal game_speed_requested(speed: int)

const AUTO_OFF_ICON: Texture2D = preload("res://assets/ui/hud/2_options_off.png")
const AUTO_ON_ICON: Texture2D = preload("res://assets/ui/hud/2_options_on.png")

@onready var _stage_manager: Node = get_parent().get_node_or_null("StageManager")
@onready var _turn_manager: Node = get_parent().get_node_or_null("TurnManager")
@onready var _player: Node = get_parent().get_node_or_null("Player")

@onready var _stage_label: Label = %StageLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _encounter_label: Label = %EncounterLabel
@onready var _enemy_summary_row: HBoxContainer = %EnemySummaryRow
@onready var _sub_hero_row: Control = %SubHeroRow
@onready var _player_hp_bar: ProgressBar = %PlayerHPBar
@onready var _player_hp_value: Label = %PlayerHPValue
@onready var _target_label: Label = %TargetLabel
@onready var _target_hp_bar: ProgressBar = %TargetHPBar
@onready var _target_hp_value: Label = %TargetHPValue
@onready var _combat_info_label: Label = %CombatInfoLabel
@onready var _event_label: Label = %EventLabel
@onready var _attack_button: Button = %AttackButton
@onready var _whirlwind_button: Button = %WhirlwindButton
@onready var _arcane_bolt_button: Button = %ArcaneBoltButton
@onready var _execution_button: Button = %ExecutionButton
@onready var _skills_button: Button = %SkillsButton
@onready var _item_button: Button = %ItemButton
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _auto_button: Button = %AutoButton
@onready var _auto_stage_button: Button = %AutoStageButton
@onready var _speed_x1_button: Button = %SpeedX1Button
@onready var _speed_x2_button: Button = %SpeedX2Button
@onready var _speed_fastest_button: Button = %SpeedFastestButton
@onready var _inventory_button: Button = %InventoryButton
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
@onready var _shop_panel: SubHeroShopPanel = %SubHeroShopPanel
# Keep this reference as Control so a cold headless harness does not depend on
# the newly-added panel class being present in Godot's global class cache.
@onready var _assignment_panel: Control = %SubHeroAssignmentPanel

var _critical_time_remaining: float = 0.0
var _enemy_summary_signature: String = ""

const ENEMY_SUMMARY_CARD_COLOR := Color("151321")
const ENEMY_SUMMARY_CARD_BORDER := Color("49384a")
const ENEMY_SUMMARY_TITLE_COLOR := Color("d9b565")
const ENEMY_SUMMARY_TEXT_COLOR := Color("d8cfdf")
const ENEMY_SUMMARY_MUTED_COLOR := Color("9d93ae")


func _ready() -> void:
	_attack_button.pressed.connect(func() -> void: attack_requested.emit())
	_whirlwind_button.pressed.connect(func() -> void: skill_requested.emit(SkillCatalog.WHIRLWIND))
	_arcane_bolt_button.pressed.connect(func() -> void: skill_requested.emit(SkillCatalog.ARCANE_BOLT))
	_execution_button.pressed.connect(func() -> void: skill_requested.emit(SkillCatalog.EXECUTION_STRIKE))
	_skills_button.pressed.connect(_on_skills_button_pressed)
	_item_button.pressed.connect(func() -> void: item_requested.emit())
	_end_turn_button.pressed.connect(func() -> void: end_turn_requested.emit())
	_auto_button.pressed.connect(func() -> void: auto_toggle_requested.emit())
	_auto_stage_button.pressed.connect(func() -> void: auto_stage_toggle_requested.emit())
	_speed_x1_button.pressed.connect(func() -> void: game_speed_requested.emit(0))
	_speed_x2_button.pressed.connect(func() -> void: game_speed_requested.emit(1))
	_speed_fastest_button.pressed.connect(func() -> void: game_speed_requested.emit(2))
	_inventory_button.pressed.connect(_on_inventory_button_pressed)
	_shop_button.pressed.connect(_on_shop_button_pressed)
	_bestiary_button.pressed.connect(_on_bestiary_button_pressed)
	_dev_button.pressed.connect(_on_dev_button_pressed)
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


func _on_inventory_button_pressed() -> void:
	_inventory_panel.toggle_inventory()


func _on_shop_button_pressed() -> void:
	_shop_panel.toggle_panel()


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
	_inventory_panel.visible or _bestiary_panel.visible or _development_panel.visible
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

	_stage_label.text = "STAGE %02d" % stage_state.stage_number
	_turn_label.text = _get_turn_label()
	_turn_label.modulate = _get_turn_color()
	_encounter_label.text = _get_encounter_text(stage_state)
	_update_enemy_summary()
	_event_label.text = str(get_parent().get("_last_move_text"))
	var inventory: EquipmentInventory = _player.get_inventory() if _player.has_method("get_inventory") else null
	if inventory != null:
		_inventory_button.text = "INVENTORY %d" % inventory.get_item_count()
	_skills_button.text = "SKILLS %d" % _player.get_skill_points()

	var player_stats: PlayerStats = _player.get("player_stats") as PlayerStats
	var player_progression: PlayerProgression = _player.get("player_progression") as PlayerProgression
	if player_progression != null:
		_gold_label.text = "GOLD %s" % _format_number(player_progression.gold)
	if player_stats != null:
		_player_hp_bar.max_value = maxi(player_stats.max_hp, 1)
		_player_hp_bar.value = clampi(player_stats.current_hp, 0, maxi(player_stats.max_hp, 1))
		_player_hp_value.text = "%d / %d" % [player_stats.current_hp, player_stats.max_hp]
		var cell: Vector2i = _player.get("grid_position")
		var movement_remaining: int = int(_player.get("movement_points_remaining"))
		_combat_info_label.text = "MP %d / %d   •   CELL %d, %d" % [movement_remaining, player_stats.movement_points, cell.x + 1, cell.y + 1]

	var target: Node = _get_target()
	_update_target(target)
	_update_buttons(player_stats)


func _update_enemy_summary() -> void:
	var grouped_enemies: Dictionary = {}
	var spawned_enemies: Array[EnemyController] = _stage_manager.get_spawned_enemies() if _stage_manager.has_method("get_spawned_enemies") else []
	for enemy in spawned_enemies:
		if enemy == null or not is_instance_valid(enemy) or enemy.is_defeated():
			continue
		var enemy_stats: EnemyStats = enemy.enemy_stats
		if enemy_stats == null:
			continue
		var enemy_name: String = enemy.get_display_name()
		var summary_key: String = _get_enemy_summary_key(enemy, enemy_stats, enemy_name)
		if not grouped_enemies.has(summary_key):
			grouped_enemies[summary_key] = {
				"enemy_name": enemy_name,
				"enemy_level": enemy.enemy_level,
				"max_hp": enemy_stats.max_hp,
				"attack": enemy_stats.attack,
				"defense": enemy_stats.defense,
				"movement_points": enemy_stats.movement_points,
				"attack_range": enemy_stats.attack_range,
				"count": 0,
			}
		grouped_enemies[summary_key]["count"] += 1

	var summary_parts: Array[String] = []
	for summary_key: String in grouped_enemies.keys():
		summary_parts.append("%s:%d" % [summary_key, int(grouped_enemies[summary_key]["count"])])
	summary_parts.sort()
	var summary_signature: String = "|".join(summary_parts) if not summary_parts.is_empty() else "NONE"
	if summary_signature == _enemy_summary_signature:
		return
	_enemy_summary_signature = summary_signature
	for child in _enemy_summary_row.get_children():
		child.free()

	if grouped_enemies.is_empty():
		var empty_label := Label.new()
		empty_label.text = "FIELD MONSTERS  •  NONE"
		empty_label.add_theme_color_override("font_color", ENEMY_SUMMARY_MUTED_COLOR)
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_enemy_summary_row.add_child(empty_label)
		return

	for summary: Dictionary in grouped_enemies.values():
		_enemy_summary_row.add_child(_create_enemy_summary_card(summary))


func _get_enemy_summary_key(enemy: EnemyController, enemy_stats: EnemyStats, enemy_name: String) -> String:
	var enemy_type: int = enemy.enemy_definition.enemy_type if enemy.enemy_definition != null else EnemyType.NORMAL
	return "%s|%d|%d|%d|%d|%d|%d|%d" % [
		enemy_name,
		enemy.enemy_level,
		enemy_type,
		enemy_stats.max_hp,
		enemy_stats.attack,
		enemy_stats.defense,
		enemy_stats.movement_points,
		enemy_stats.attack_range,
	]


func _create_enemy_summary_card(summary: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 64.0)
	card.add_theme_stylebox_override("panel", _make_enemy_summary_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 5)
	card.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	margin.add_child(content)

	var name_label := Label.new()
	name_label.text = "%s  LV.%d  ×%d" % [str(summary["enemy_name"]).to_upper(), int(summary["enemy_level"]), int(summary["count"])]
	name_label.add_theme_color_override("font_color", ENEMY_SUMMARY_TITLE_COLOR)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(name_label)

	var primary_stats_label := Label.new()
	primary_stats_label.text = "HP %d  ATK %d  DEF %d" % [int(summary["max_hp"]), int(summary["attack"]), int(summary["defense"])]
	primary_stats_label.add_theme_color_override("font_color", ENEMY_SUMMARY_TEXT_COLOR)
	primary_stats_label.add_theme_font_size_override("font_size", 9)
	primary_stats_label.clip_text = true
	content.add_child(primary_stats_label)

	var secondary_stats_label := Label.new()
	secondary_stats_label.text = "MOV %d  RNG %d" % [int(summary["movement_points"]), int(summary["attack_range"])]
	secondary_stats_label.add_theme_color_override("font_color", ENEMY_SUMMARY_MUTED_COLOR)
	secondary_stats_label.add_theme_font_size_override("font_size", 9)
	content.add_child(secondary_stats_label)
	return card


func _make_enemy_summary_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ENEMY_SUMMARY_CARD_COLOR
	style.border_color = ENEMY_SUMMARY_CARD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func _get_target() -> Node:
	if _player.has_method("get_target"):
		var target: Node = _player.call("get_target") as Node
		if target != null and is_instance_valid(target) and not bool(target.get("_is_defeated")):
			return target
	return null


func _update_target(target: Node) -> void:
	if target == null:
		_target_label.text = "TARGET  //  NONE"
		_target_hp_bar.value = 0
		_target_hp_value.text = "--"
		return
	var enemy_stats: EnemyStats = target.get("enemy_stats") as EnemyStats
	var enemy_name: String = str(target.call("get_display_name")) if target.has_method("get_display_name") else "ENEMY"
	var enemy_level: int = int(target.get("enemy_level"))
	_target_label.text = "TARGET  //  %s  LV.%d" % [enemy_name.to_upper(), enemy_level]
	if enemy_stats == null:
		return
	_target_hp_bar.max_value = maxi(enemy_stats.max_hp, 1)
	_target_hp_bar.value = clampi(enemy_stats.current_hp, 0, maxi(enemy_stats.max_hp, 1))
	_target_hp_value.text = "%d / %d" % [enemy_stats.current_hp, enemy_stats.max_hp]


func _update_buttons(player_stats: PlayerStats) -> void:
	var player_turn: bool = _turn_manager.get_phase() == TurnState.PLAYER_TURN
	var input_enabled: bool = bool(_player.get("is_selected")) and bool(_player.call("is_input_enabled"))
	var can_attack: bool = player_turn and input_enabled and _get_target() != null
	_attack_button.disabled = not can_attack
	var can_use_skill: bool = player_turn and input_enabled
	_whirlwind_button.disabled = not can_use_skill or not _can_use_skill(SkillCatalog.WHIRLWIND)
	_arcane_bolt_button.disabled = not can_use_skill or not _can_use_skill(SkillCatalog.ARCANE_BOLT)
	_execution_button.disabled = not can_use_skill or not _can_use_skill(SkillCatalog.EXECUTION_STRIKE)
	var potion_count: int = _player.get_healing_item_count() if _player.has_method("get_healing_item_count") else 0
	_item_button.text = "POTION %d" % potion_count
	var can_use_item: bool = player_turn and input_enabled and potion_count > 0
	if player_stats != null:
		can_use_item = can_use_item and player_stats.current_hp < player_stats.max_hp
	_item_button.disabled = not can_use_item

	var phase: int = _turn_manager.get_phase()
	if phase == TurnState.VICTORY:
		_end_turn_button.text = "NEXT STAGE"
		_end_turn_button.disabled = false
	elif phase == TurnState.DEFEAT:
		_end_turn_button.text = "DEFEATED"
		_end_turn_button.disabled = true
	else:
		_end_turn_button.text = "END TURN"
		_end_turn_button.disabled = not player_turn
	_auto_button.disabled = phase == TurnState.DEFEAT
	_auto_stage_button.disabled = phase == TurnState.DEFEAT
	# Victory is a brief status effect, not a modal result screen. Keep the
	# compact banner mouse-transparent so it never covers combat controls.
	_state_banner.visible = phase == TurnState.VICTORY or phase == TurnState.DEFEAT
	_state_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_label.text = "VICTORY" if phase == TurnState.VICTORY else "DEFEAT"
	_state_label.modulate = Color("89c797") if phase == TurnState.VICTORY else Color("d46a78")
	if player_stats == null:
		_attack_button.disabled = true
		_whirlwind_button.disabled = true
		_arcane_bolt_button.disabled = true
		_execution_button.disabled = true
		_item_button.disabled = true


func _can_use_skill(skill_id: StringName) -> bool:
	var combat_scene: Node = get_parent()
	return combat_scene.has_method("can_use_skill") and bool(combat_scene.call("can_use_skill", skill_id))


func set_auto_mode(enabled: bool) -> void:
	if _auto_button == null:
		return
	_auto_button.text = "AUTO: ON" if enabled else "AUTO: OFF"
	_auto_button.icon = AUTO_ON_ICON if enabled else AUTO_OFF_ICON
	_auto_button.modulate = Color("89c797") if enabled else Color("f0e7d2")


func set_auto_stage_mode(enabled: bool) -> void:
	if _auto_stage_button == null:
		return
	_auto_stage_button.text = "AUTO STAGE: ON" if enabled else "AUTO STAGE: OFF"
	_auto_stage_button.icon = AUTO_ON_ICON if enabled else AUTO_OFF_ICON
	_auto_stage_button.modulate = Color("89c797") if enabled else Color("f0e7d2")


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


func _get_turn_label() -> String:
	match _turn_manager.get_phase():
		TurnState.PLAYER_TURN:
			return "YOUR TURN"
		TurnState.ENEMY_TURN:
			return "ENEMY TURN"
		TurnState.VICTORY:
			return "VICTORY"
		TurnState.DEFEAT:
			return "DEFEAT"
		_:
			return "-"


func _get_turn_color() -> Color:
	match _turn_manager.get_phase():
		TurnState.PLAYER_TURN:
			return Color("d9b565")
		TurnState.ENEMY_TURN:
			return Color("d46a78")
		TurnState.VICTORY:
			return Color("89c797")
		TurnState.DEFEAT:
			return Color("d46a78")
		_:
			return Color("b9afc6")


func _format_number(value: int) -> String:
	var text_value: String = str(maxi(value, 0))
	var formatted: String = ""
	while text_value.length() > 3:
		formatted = "," + text_value.substr(text_value.length() - 3, 3) + formatted
		text_value = text_value.substr(0, text_value.length() - 3)
	return text_value + formatted
