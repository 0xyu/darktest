class_name EquipmentEffect
extends Resource

const EveryThirdAttackEffectResource = preload("res://scripts/items/effects/every_third_attack_effect.gd")
const CriticalHealingEffectResource = preload("res://scripts/items/effects/critical_healing_effect.gd")
const MovementAttackEffectResource = preload("res://scripts/items/effects/movement_attack_effect.gd")
const BackAttackEffectResource = preload("res://scripts/items/effects/back_attack_effect.gd")
const PoisonedTargetEffectResource = preload("res://scripts/items/effects/poisoned_target_effect.gd")

## Base contract for build-defining equipment behavior.
@export var effect_id: StringName = &""
@export var display_name: String = "Equipment Effect"


func get_damage_multiplier(_attacker: Node, _target: Node, _attack_context: Dictionary) -> float:
	return 1.0


func on_attack_resolved(
	_attacker: Node,
	_target: Node,
	_result: DamageResult,
	_attack_context: Dictionary
) -> void:
	return


static func create_for_id(requested_effect_id: StringName) -> EquipmentEffect:
	match requested_effect_id:
		&"every_3rd_attack", &"third_attack":
			return EveryThirdAttackEffectResource.new()
		&"critical_healing", &"critical_heals":
			return CriticalHealingEffectResource.new()
		&"movement_attack", &"moving_attack":
			return MovementAttackEffectResource.new()
		&"back_attack", &"attack_from_behind":
			return BackAttackEffectResource.new()
		&"poisoned_target", &"poisoned_enemy":
			return PoisonedTargetEffectResource.new()
		_:
			return null
