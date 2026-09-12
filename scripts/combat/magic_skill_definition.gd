class_name MagicSkillDefinition
extends Resource

## One Magic Tome spell (docs/game-design.md §16).
##
## A tome spell is the opposite of a player skill: it needs no skill level, no grid
## range and no turn of its own. Its only cost is a cooldown counted in PLAYER TURNS,
## and its tuning lives here so the combat code, the HUD and the presentation layer
## never each keep their own copy.
enum TargetMode {
	SINGLE_TARGET,
	ALL_ENEMIES,
}

@export var skill_id: StringName = &""
@export var display_name: String = "Spell"
@export_multiline var description: String = ""
## Player Turns the spell stays unavailable after it is cast.
@export_range(0, 20, 1) var cooldown_turns: int = 4
@export_range(0.1, 10.0, 0.05) var damage_multiplier: float = 1.0
@export var target_mode: TargetMode = TargetMode.SINGLE_TARGET
## Combat VFX category drawn at the impact point (see combat_vfx.gd).
@export var vfx_id: StringName = &"arcane"


func hits_every_enemy() -> bool:
	return target_mode == TargetMode.ALL_ENEMIES
