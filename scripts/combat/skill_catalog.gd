class_name SkillCatalog
extends RefCounted

## The first three player skills. Balance values live here so combat code and
## UI do not each maintain their own copy.
const WHIRLWIND: StringName = &"whirlwind"
const ARCANE_BOLT: StringName = &"arcane_bolt"
const EXECUTION_STRIKE: StringName = &"execution_strike"


static func get_all() -> Array[SkillDefinition]:
	return [
		get_skill(WHIRLWIND),
		get_skill(ARCANE_BOLT),
		get_skill(EXECUTION_STRIKE),
	]


static func get_skill(skill_id: StringName) -> SkillDefinition:
	var skill := SkillDefinition.new()
	skill.skill_id = skill_id
	match skill_id:
		WHIRLWIND:
			skill.display_name = "WHIRLWIND"
			skill.description = "Hits enemies in the four adjacent cells."
			skill.range_cells = 1
			skill.damage_multiplier = 0.8
			skill.target_mode = SkillDefinition.TargetMode.ADJACENT_AREA
		ARCANE_BOLT:
			skill.display_name = "ARCANE BOLT"
			skill.description = "A ranged attack that reaches two cells."
			skill.range_cells = 2
			skill.damage_multiplier = 1.0
			skill.target_mode = SkillDefinition.TargetMode.SINGLE_TARGET
		EXECUTION_STRIKE:
			skill.display_name = "EXECUTION"
			skill.description = "A powerful single-target melee attack."
			skill.range_cells = 1
			skill.damage_multiplier = 1.5
			skill.target_mode = SkillDefinition.TargetMode.SINGLE_TARGET
		_:
			skill.skill_id = &""
	return skill
