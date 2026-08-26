class_name EquipmentComparison
extends RefCounted

## Readable comparison data for a candidate item and its slot's current item.
## The comparison keeps raw values and presentation-ready rows together so UI
## layers do not need to reimplement equipment math.
var candidate_item: EquipmentInstance
var current_item: EquipmentInstance
var slot: int = -1
var candidate_stats: Dictionary = {}
var current_stats: Dictionary = {}
var stat_deltas: Dictionary = {}
var score_delta: float = 0.0


func _init(
	candidate: EquipmentInstance = null,
	current: EquipmentInstance = null,
	equipment_slot: int = -1
) -> void:
	candidate_item = candidate
	current_item = current
	slot = equipment_slot
	for stat_id in EquipmentAffix.get_stat_ids():
		candidate_stats[stat_id] = _get_stat_value(candidate_item, stat_id)
		current_stats[stat_id] = _get_stat_value(current_item, stat_id)
		stat_deltas[stat_id] = float(candidate_stats[stat_id]) - float(current_stats[stat_id])
	if candidate_item != null:
		score_delta = candidate_item.get_equipment_score()
	if current_item != null and current_item != candidate_item:
		score_delta -= current_item.get_equipment_score()


func get_stat_delta(stat_id: StringName) -> float:
	return float(stat_deltas.get(stat_id, 0.0))


func has_stat_change(stat_id: StringName) -> bool:
	return not is_zero_approx(get_stat_delta(stat_id))


func get_changed_stat_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for stat_id in EquipmentAffix.get_stat_ids():
		if has_stat_change(stat_id):
			result.append(stat_id)
	return result


func get_stat_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for stat_id in get_changed_stat_ids():
		var delta: float = get_stat_delta(stat_id)
		var is_percentage: bool = EquipmentAffix.is_percentage_stat(stat_id)
		result.append({
			"stat_id": stat_id,
			"display_name": EquipmentAffix.get_display_name_for_stat(stat_id),
			"current_value": current_stats.get(stat_id, 0.0),
			"candidate_value": candidate_stats.get(stat_id, 0.0),
			"delta": delta,
			"is_percentage": is_percentage,
			"is_positive": delta > 0.0,
			"formatted_delta": _format_delta(delta, is_percentage),
		})
	return result


func get_formatted_lines() -> Array[String]:
	var result: Array[String] = []
	for row in get_stat_rows():
		result.append("%s %s" % [row["display_name"], row["formatted_delta"]])
	return result


func is_upgrade() -> bool:
	return score_delta > 0.0


func to_dictionary() -> Dictionary:
	return {
		"item": candidate_item,
		"current_item": current_item,
		"slot": slot,
		"candidate_stats": candidate_stats.duplicate(),
		"current_stats": current_stats.duplicate(),
		"stat_deltas": stat_deltas.duplicate(),
		"stat_rows": get_stat_rows(),
		"formatted_lines": get_formatted_lines(),
		"score_delta": score_delta,
		"is_upgrade": is_upgrade(),
	}


func _get_stat_value(item: EquipmentInstance, stat_id: StringName) -> float:
	if item == null:
		return 0.0
	return item.get_affix_value(stat_id)


func _format_delta(delta: float, is_percentage: bool) -> String:
	if is_percentage:
		return "%+.0f%%" % (delta * 100.0)
	return "%+d" % roundi(delta)
