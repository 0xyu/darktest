class_name MovementAttackEffect
extends EquipmentEffect


func _init() -> void:
	effect_id = &"movement_attack"
	display_name = "Moving 2 cells before attacking deals +75% damage"


func get_damage_multiplier(_attacker: Node, _target: Node, attack_context: Dictionary) -> float:
	return 1.75 if int(attack_context.get("cells_moved", 0)) >= 2 else 1.0
