class_name CriticalHealingEffect
extends EquipmentEffect


func _init() -> void:
	effect_id = &"critical_healing"
	display_name = "Critical attacks restore 5% HP"


func on_attack_resolved(attacker: Node, _target: Node, result: DamageResult, _attack_context: Dictionary) -> void:
	if not result.is_critical or result.is_miss:
		return
	if attacker == null or not attacker.has_method("heal_from_equipment_effect"):
		return
	attacker.heal_from_equipment_effect(0.05, effect_id, display_name)
