class_name CombatActions
extends VBoxContainer

## Player combat-action cluster: the skill buttons, attack / potion / end-turn
## row, and the auto toggles.
##
## The combat HUD owns world access (player, turn manager, targets). It feeds
## button state through the set_* methods on every refresh, and presses are
## re-emitted as *_requested signals that the HUD forwards to the combat scene.

signal attack_requested
signal skill_requested(skill_id: StringName)
signal item_requested
signal end_turn_requested
signal next_stage_requested
signal auto_toggle_requested
signal farming_toggle_requested

const AUTO_OFF_ICON: Texture2D = preload("res://assets/ui/hud/2_options_off.png")
const AUTO_ON_ICON: Texture2D = preload("res://assets/ui/hud/2_options_on.png")

const END_TURN_TEXT := "END TURN"
const DEFEATED_TEXT := "DEFEATED"
const ENABLED_COLOR := Color(0.941, 0.906, 0.824, 1.0)
const ACTIVE_COLOR := Color(0.537, 0.78, 0.592, 1.0)

@onready var _attack_button: Button = %AttackButton
@onready var _whirlwind_button: Button = %WhirlwindButton
@onready var _arcane_bolt_button: Button = %ArcaneBoltButton
@onready var _execution_button: Button = %ExecutionButton
@onready var _item_button: Button = %ItemButton
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _next_stage_button: Button = %NextStageButton
@onready var _auto_button: Button = %AutoButton
@onready var _farming_button: Button = %FarmingButton

var _skill_buttons: Dictionary = {}


func _ready() -> void:
	_skill_buttons[SkillCatalog.WHIRLWIND] = _whirlwind_button
	_skill_buttons[SkillCatalog.ARCANE_BOLT] = _arcane_bolt_button
	_skill_buttons[SkillCatalog.EXECUTION_STRIKE] = _execution_button

	_attack_button.pressed.connect(func() -> void: attack_requested.emit())
	_whirlwind_button.pressed.connect(func() -> void: skill_requested.emit(SkillCatalog.WHIRLWIND))
	_arcane_bolt_button.pressed.connect(func() -> void: skill_requested.emit(SkillCatalog.ARCANE_BOLT))
	_execution_button.pressed.connect(func() -> void: skill_requested.emit(SkillCatalog.EXECUTION_STRIKE))
	_item_button.pressed.connect(func() -> void: item_requested.emit())
	_end_turn_button.pressed.connect(func() -> void: end_turn_requested.emit())
	_next_stage_button.pressed.connect(func() -> void: next_stage_requested.emit())
	_auto_button.pressed.connect(func() -> void: auto_toggle_requested.emit())
	_farming_button.pressed.connect(func() -> void: farming_toggle_requested.emit())


func set_attack_usable(usable: bool) -> void:
	if _attack_button != null:
		_attack_button.disabled = not usable


func set_skill_usable(skill_id: StringName, usable: bool) -> void:
	var button: Button = _skill_buttons.get(skill_id) as Button
	if button != null:
		button.disabled = not usable


func set_item_button(potion_count: int, usable: bool) -> void:
	if _item_button == null:
		return
	_item_button.text = "POTION %d" % potion_count
	_item_button.disabled = not usable


func set_end_turn_state(phase: int, player_turn: bool) -> void:
	if _end_turn_button == null:
		return
	if phase == TurnState.VICTORY:
		# The dedicated NEXT STAGE button handles stage progression; END TURN
		# no longer relabels or advances in victory.
		_end_turn_button.text = END_TURN_TEXT
		_end_turn_button.disabled = true
	elif phase == TurnState.DEFEAT:
		_end_turn_button.text = DEFEATED_TEXT
		_end_turn_button.disabled = true
	else:
		_end_turn_button.text = END_TURN_TEXT
		_end_turn_button.disabled = not player_turn


## Victory-only NEXT STAGE control. Only revealed during VICTORY, and only
## enabled once the caller confirms the player stands on the stage exit cell.
func set_next_stage_state(phase: int, enabled: bool) -> void:
	if _next_stage_button == null:
		return
	_next_stage_button.visible = phase == TurnState.VICTORY
	_next_stage_button.disabled = not enabled


func set_auto_controls(phase: int) -> void:
	if _auto_button == null or _farming_button == null:
		return
	var defeated: bool = phase == TurnState.DEFEAT
	_auto_button.disabled = defeated
	_farming_button.disabled = defeated


func set_auto_mode(enabled: bool) -> void:
	if _auto_button == null:
		return
	_auto_button.text = "AUTO: ON" if enabled else "AUTO: OFF"
	_auto_button.icon = AUTO_ON_ICON if enabled else AUTO_OFF_ICON
	_auto_button.modulate = ACTIVE_COLOR if enabled else ENABLED_COLOR


func set_farming_mode(enabled: bool) -> void:
	if _farming_button == null:
		return
	_farming_button.text = "FARMING: ON" if enabled else "FARMING: OFF"
	_farming_button.icon = AUTO_ON_ICON if enabled else AUTO_OFF_ICON
	_farming_button.modulate = ACTIVE_COLOR if enabled else ENABLED_COLOR


## Disables every action that depends on a valid player-stat snapshot.
func disable_player_actions() -> void:
	if _attack_button != null:
		_attack_button.disabled = true
	for button: Button in _skill_buttons.values():
		if button != null:
			button.disabled = true
	if _item_button != null:
		_item_button.disabled = true
