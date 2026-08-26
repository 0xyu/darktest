class_name EveryThirdAttackEffect
extends EquipmentEffect


func _init() -> void:
	effect_id = &"every_3rd_attack"
	display_name = "Every 3rd attack deals +100% damage"


func get_damage_multiplier(_attacker: Node, _target: Node, attack_context: Dictionary) -> float:
	return 2.0 if int(attack_context.get("attack_number", 0)) % 3 == 0 else 1.0
