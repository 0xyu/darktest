class_name PoisonedTargetEffect
extends EquipmentEffect


func _init() -> void:
	effect_id = &"poisoned_target"
	display_name = "Attacking a poisoned enemy deals +50% damage"


func get_damage_multiplier(_attacker: Node, _target: Node, attack_context: Dictionary) -> float:
	return 1.5 if bool(attack_context.get("target_poisoned", false)) else 1.0
