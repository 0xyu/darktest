class_name BackAttackEffect
extends EquipmentEffect


func _init() -> void:
	effect_id = &"back_attack"
	display_name = "Attacking from behind deals +100% damage"


func get_damage_multiplier(_attacker: Node, _target: Node, attack_context: Dictionary) -> float:
	return 2.0 if bool(attack_context.get("attacking_from_behind", false)) else 1.0
