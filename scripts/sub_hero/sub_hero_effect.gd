class_name SubHeroEffect
extends Resource

## Extension point for Sub Hero utility effects.
##
## The initial data set uses basic damage only. Concrete effects can override
## these hooks later without making SubHeroData or the combat manager own
## effect-specific state.
@export var effect_id: StringName = &""
@export var display_name: String = ""


func on_attack_resolved(
	_attacker: Resource,
	_target: Node,
	_damage: int,
	_context: Dictionary
) -> void:
	return
