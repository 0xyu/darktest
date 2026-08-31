class_name PlayerProgression
extends Resource

## Persistent progression values independent from the player's derived stats.
signal experience_changed(current_experience: int, required_experience: int)
signal level_up(new_level: int)
signal gold_changed(current_gold: int, amount: int)
signal skill_points_changed(current_skill_points: int)
signal skill_level_changed(skill_id: StringName, new_level: int)

const BASE_EXPERIENCE_TO_NEXT_LEVEL: int = 100
const EXPERIENCE_GROWTH_RATE: float = 1.15

@export_range(1, 999999, 1) var level: int = 1
@export var experience: int = 0
@export var gold: int = 0
@export_range(1, 999999, 1) var current_stage: int = 1
@export_range(0, 999999, 1) var skill_points: int = 0
@export var skill_levels: Dictionary = {}


func experience_to_next_level() -> int:
	var safe_level: int = maxi(level, 1)
	return maxi(1, roundi(float(BASE_EXPERIENCE_TO_NEXT_LEVEL) * pow(EXPERIENCE_GROWTH_RATE, float(safe_level - 1))))


func add_experience(amount: int) -> int:
	var safe_amount: int = maxi(amount, 0)
	if safe_amount == 0:
		experience_changed.emit(experience, experience_to_next_level())
		return 0

	experience += safe_amount
	var levels_gained: int = 0
	while experience >= experience_to_next_level():
		experience -= experience_to_next_level()
		level += 1
		levels_gained += 1
		skill_points += 1
		skill_points_changed.emit(skill_points)
		level_up.emit(level)

	experience_changed.emit(experience, experience_to_next_level())
	return levels_gained


func get_experience_ratio() -> float:
	var required_experience: int = experience_to_next_level()
	if required_experience <= 0:
		return 0.0
	return clampf(float(experience) / float(required_experience), 0.0, 1.0)


func add_gold(amount: int) -> int:
	var safe_amount: int = maxi(amount, 0)
	if safe_amount == 0:
		return 0
	gold += safe_amount
	gold_changed.emit(gold, safe_amount)
	return safe_amount


func spend_gold(amount: int) -> bool:
	var safe_amount: int = maxi(amount, 0)
	if gold < safe_amount:
		return false
	if safe_amount == 0:
		return true
	gold -= safe_amount
	gold_changed.emit(gold, -safe_amount)
	return true


func get_skill_points() -> int:
	return maxi(skill_points, 0)


func get_skill_level(skill_id: StringName) -> int:
	return clampi(int(skill_levels.get(skill_id, 0)), 0, SkillDefinition.MAX_LEVEL)


## Learns or upgrades a skill by one level. Level 0 is unlearned and every
## upgrade costs exactly one skill point.
func upgrade_skill(skill_id: StringName) -> bool:
	var skill := SkillCatalog.get_skill(skill_id)
	if skill.skill_id.is_empty() or get_skill_points() <= 0:
		return false
	var current_level: int = get_skill_level(skill_id)
	if current_level >= SkillDefinition.MAX_LEVEL:
		return false
	skill_levels[skill_id] = current_level + 1
	skill_points -= 1
	skill_level_changed.emit(skill_id, current_level + 1)
	skill_points_changed.emit(skill_points)
	return true
