class_name MiniBossDefinition
extends EnemyData

## Behaviour configuration for a guaranteed Mini Boss encounter.
enum BossBehavior {
	AOE,
	SUMMONER,
	ENRAGER,
}

@export_enum("AOE", "Summoner", "Enrager") var boss_behavior: int = BossBehavior.AOE
@export_range(1, 8, 1) var ability_range: int = 2
@export_range(0.1, 3.0, 0.05) var ability_damage_multiplier: float = 0.75
@export_range(1, 3, 1) var summon_count: int = 1
@export_range(0.05, 0.95, 0.05) var enrage_health_threshold: float = 0.5
@export_range(1.05, 4.0, 0.05) var enrage_attack_multiplier: float = 1.5
