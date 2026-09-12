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
## §16 Magic Tome: a spell press. It is its own signal (not a `skill_requested`) so
## the host can grant it a completely different contract: no action, no turn, and
## legal in any phase.
signal magic_requested(skill_id: StringName)

const AUTO_OFF_ICON: Texture2D = preload("res://assets/ui/hud/2_options_off.png")
const AUTO_ON_ICON: Texture2D = preload("res://assets/ui/hud/2_options_on.png")

const END_TURN_TEXT := "END TURN"
const DEFEATED_TEXT := "DEFEATED"
const ENABLED_COLOR := Color(0.941, 0.906, 0.824, 1.0)
const DISABLED_COLOR := Color(0.459, 0.435, 0.514, 1.0)
const ACTIVE_COLOR := Color(0.537, 0.78, 0.592, 1.0)
const MAGIC_READY_TEXT := "READY"
const MAGIC_COOLDOWN_TEXT := "CD"

@onready var _attack_button: Button = %AttackButton
@onready var _whirlwind_button: Button = %WhirlwindButton
@onready var _arcane_bolt_button: Button = %ArcaneBoltButton
@onready var _execution_button: Button = %ExecutionButton
@onready var _item_button: Button = %ItemButton
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _next_stage_button: Button = %NextStageButton
@onready var _auto_button: Button = %AutoButton
@onready var _farming_button: Button = %FarmingButton
@onready var _magic_row: HBoxContainer = %MagicRow

var _skill_buttons: Dictionary = {}
## §16: the tome's buttons are BUILT from the state the host reports, so a new spell
## needs no scene edit and the row can never disagree with the catalog.
var _magic_buttons: Dictionary = {}


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


## §16 Magic row. Each entry is one tome spell as the host reports it:
## {skill_id, display_name, tooltip, cooldown (Player Turns), usable}. A button is
## created the first time a spell is reported, then only its label and availability
## are refreshed — the cooldown is shown in Player Turns, which is what it is.
func set_magic_states(states: Array[Dictionary]) -> void:
	for state in states:
		var skill_id: StringName = state.get("skill_id", &"")
		if skill_id.is_empty():
			continue
		var button: Button = _magic_buttons.get(skill_id) as Button
		if button == null:
			button = _create_magic_button(state)
		var cooldown: int = int(state.get("cooldown", 0))
		var status: String = MAGIC_READY_TEXT if cooldown <= 0 else "%s %d" % [MAGIC_COOLDOWN_TEXT, cooldown]
		var label: String = "%s\n%s" % [str(state.get("display_name", "")), status]
		if button.text != label:
			button.text = label
		button.tooltip_text = str(state.get("tooltip", ""))
		button.disabled = not bool(state.get("usable", false))


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


## NEXT STAGE control. It is revealed after a clear (VICTORY) and, while it is not
## usable, disabled. A stage the player walked back into may leave an enabled
## control mid-fight, so `enabled` alone can reveal it too.
func set_next_stage_state(phase: int, enabled: bool) -> void:
	if _next_stage_button == null:
		return
	_next_stage_button.visible = enabled or phase == TurnState.VICTORY
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
	for button: Button in _magic_buttons.values():
		if button != null:
			button.disabled = true


## Builds one Magic row button. Styling is copied from the ATTACK button so the row
## stays visually part of the action cluster without duplicating the style boxes.
func _create_magic_button(state: Dictionary) -> Button:
	var skill_id: StringName = state.get("skill_id", &"")
	var button := Button.new()
	button.name = "Magic%sButton" % String(skill_id).to_pascal_case()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", ENABLED_COLOR)
	button.add_theme_color_override("font_disabled_color", DISABLED_COLOR)
	if _attack_button != null:
		for style_name in ["normal", "pressed", "hover"]:
			var style: StyleBox = _attack_button.get_theme_stylebox(style_name)
			if style != null:
				button.add_theme_stylebox_override(style_name, style)
	button.pressed.connect(func() -> void: magic_requested.emit(skill_id))
	if _magic_row != null:
		_magic_row.add_child(button)
	_magic_buttons[skill_id] = button
	return button
