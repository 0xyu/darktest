class_name SkillDefinition
extends Resource

## Describes one player skill without coupling its data to the HUD.
enum TargetMode {
	SINGLE_TARGET,
	ADJACENT_AREA,
}

const MAX_LEVEL: int = 5

@export var skill_id: StringName = &""
@export var display_name: String = "Skill"
@export_multiline var description: String = ""
@export_range(0, 99, 1) var range_cells: int = 1
@export_range(0.1, 10.0, 0.05) var damage_multiplier: float = 1.0
@export_range(0.0, 10.0, 0.05) var damage_multiplier_per_level: float = 0.1
@export var target_mode: TargetMode = TargetMode.SINGLE_TARGET


func is_area_skill() -> bool:
	return target_mode == TargetMode.ADJACENT_AREA


func get_damage_multiplier(skill_level: int) -> float:
	var safe_level: int = clampi(skill_level, 1, MAX_LEVEL)
	return damage_multiplier + damage_multiplier_per_level * float(safe_level - 1)
