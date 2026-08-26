class_name MobileCombatHUD
extends CanvasLayer

## Portrait-first HUD for the existing combat scene.
## The HUD only forwards input to the existing player and turn systems.
signal move_requested(direction: Vector2i)
signal attack_requested
signal item_requested
signal end_turn_requested
signal auto_toggle_requested

@onready var _stage_manager: Node = get_parent().get_node_or_null("StageManager")
@onready var _turn_manager: Node = get_parent().get_node_or_null("TurnManager")
@onready var _player: Node = get_parent().get_node_or_null("Player")

@onready var _stage_label: Label = %StageLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _encounter_label: Label = %EncounterLabel
@onready var _player_hp_bar: ProgressBar = %PlayerHPBar
@onready var _player_hp_value: Label = %PlayerHPValue
@onready var _target_label: Label = %TargetLabel
@onready var _target_hp_bar: ProgressBar = %TargetHPBar
@onready var _target_hp_value: Label = %TargetHPValue
@onready var _combat_info_label: Label = %CombatInfoLabel
@onready var _event_label: Label = %EventLabel
@onready var _attack_button: Button = %AttackButton
@onready var _item_button: Button = %ItemButton
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _auto_button: Button = %AutoButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _critical_label: Label = %CriticalLabel
@onready var _state_banner: PanelContainer = %StateBanner
@onready var _state_label: Label = %StateLabel
@onready var _inventory_panel: EquipmentInventoryPanel = %InventoryPanel
@onready var _move_buttons: Array[Button] = [%MoveUpButton, %MoveLeftButton, %MoveDownButton, %MoveRightButton]

var _critical_time_remaining: float = 0.0


func _ready() -> void:
	_move_buttons[0].pressed.connect(_on_move_up_pressed)
	_move_buttons[1].pressed.connect(_on_move_left_pressed)
	_move_buttons[2].pressed.connect(_on_move_down_pressed)
	_move_buttons[3].pressed.connect(_on_move_right_pressed)
	_attack_button.pressed.connect(func() -> void: attack_requested.emit())
	_item_button.pressed.connect(func() -> void: item_requested.emit())
	_end_turn_button.pressed.connect(func() -> void: end_turn_requested.emit())
	_auto_button.pressed.connect(func() -> void: auto_toggle_requested.emit())
	_inventory_button.pressed.connect(_on_inventory_button_pressed)
	_inventory_panel.set_player(_player)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
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
	_event_label.text = str(get_parent().get("_last_move_text"))
	var inventory: EquipmentInventory = _player.get_inventory() if _player.has_method("get_inventory") else null
	if inventory != null:
		_inventory_button.text = "INVENTORY %d" % inventory.get_item_count()

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
	var movement_remaining: int = int(_player.get("movement_points_remaining"))
	var can_move: bool = player_turn and input_enabled and movement_remaining > 0
	for button in _move_buttons:
		button.disabled = not can_move
	var can_attack: bool = player_turn and input_enabled and _get_target() != null
	_attack_button.disabled = not can_attack
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
	_state_banner.visible = phase == TurnState.VICTORY or phase == TurnState.DEFEAT
	_state_label.text = "VICTORY" if phase == TurnState.VICTORY else "DEFEAT"
	_state_label.modulate = Color("89c797") if phase == TurnState.VICTORY else Color("d46a78")
	if player_stats == null:
		_attack_button.disabled = true
		_item_button.disabled = true


func set_auto_mode(enabled: bool) -> void:
	if _auto_button == null:
		return
	_auto_button.text = "AUTO: ON" if enabled else "AUTO: OFF"
	_auto_button.modulate = Color("89c797") if enabled else Color("f0e7d2")


func present_loot(items: Array[EquipmentInstance], new_best_items: Array[EquipmentInstance] = [], source_name: String = "") -> void:
	var loot_presentation: LootPresentation = %LootPresentation
	loot_presentation.present_loot(items, new_best_items, source_name)


func show_critical_indicator(damage: int) -> void:
	_critical_label.text = "CRITICAL HIT  •  %d" % damage
	_critical_label.visible = true
	_critical_label.modulate = Color("f2c15e")
	_critical_time_remaining = 0.8


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
