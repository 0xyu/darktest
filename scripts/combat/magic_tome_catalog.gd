class_name MagicTomeCatalog
extends RefCounted

## The Magic Tome's spell list (docs/game-design.md §16). Balance values live here —
## combat code, the HUD and the presentation layer only ever read this catalog, so a
## spell's cooldown or multiplier is authored in exactly one place.
const MAGIC_MISSILE: StringName = &"magic_missile"
const ARCANE_NOVA: StringName = &"arcane_nova"


static func get_all() -> Array[MagicSkillDefinition]:
	return [
		get_skill(MAGIC_MISSILE),
		get_skill(ARCANE_NOVA),
	]


static func get_skill(skill_id: StringName) -> MagicSkillDefinition:
	var skill := MagicSkillDefinition.new()
	skill.skill_id = skill_id
	match skill_id:
		MAGIC_MISSILE:
			skill.display_name = "MAGIC MISSILE"
			skill.description = "Strikes one enemy anywhere on the battlefield, for free. Cooldown: 4 Player Turns."
			skill.cooldown_turns = 4
			skill.damage_multiplier = 0.9
			skill.target_mode = MagicSkillDefinition.TargetMode.SINGLE_TARGET
			skill.vfx_id = &"arcane"
		ARCANE_NOVA:
			skill.display_name = "ARCANE NOVA"
			skill.description = "Strikes every enemy on the battlefield, for free. Cooldown: 6 Player Turns."
			skill.cooldown_turns = 6
			skill.damage_multiplier = 0.6
			skill.target_mode = MagicSkillDefinition.TargetMode.ALL_ENEMIES
			skill.vfx_id = &"lightning"
		_:
			skill.skill_id = &""
	return skill


## True for every id this catalog knows, so the presentation layer can tell a tome
## spell from a weapon strike or a player skill.
static func is_magic_skill(skill_id: StringName) -> bool:
	return not get_skill(skill_id).skill_id.is_empty()
