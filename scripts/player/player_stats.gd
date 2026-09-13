class_name PlayerStats
extends Resource

## Runtime and derived combat values for the player.
@export var max_hp: int = 100
@export var current_hp: int = 100
@export var attack: int = 10
@export var defense: int = 5
@export_range(0.0, 1.0, 0.01) var critical_chance: float = 0.05
@export_range(1.0, 10.0, 0.05) var critical_damage: float = 1.5
@export var movement_points: int = 3
@export var attack_range: int = 1
@export_range(0.0, 1.0, 0.01) var dodge: float = 0.0
@export_range(0.0, 1.0, 0.01) var life_steal: float = 0.0
## §12 tier affixes: an additive damage bonus against the matching enemy tier
## (§8 elite spawns, mini bosses). Read by CombatSystem for every attack the owner
## makes; 0.0 means no bonus.
@export var damage_vs_elite: float = 0.0
@export var damage_vs_boss: float = 0.0
## §12 Stun affix: chance per landed hit (0..1) to apply `StatusEffectComponent.STUN`
## to the target. The stun itself lives on the target, not here.
@export_range(0.0, 1.0, 0.01) var stun_chance: float = 0.0

## What ONE level adds to the three core numbers. They live beside the values they
## grow, because the hero rebuilds its derived stats from the level every time
## (PlayerController.recompute_stats_from_level_and_equipment): a level-up applies
## exactly these numbers and a load reconstructs exactly these numbers, so a restored
## level cannot be worth less than a played-up one.
@export_range(0, 999999, 1) var max_hp_per_level: int = 20
@export_range(0, 999999, 1) var attack_per_level: int = 2
@export_range(0, 999999, 1) var defense_per_level: int = 1


func reset_current_hp() -> void:
	current_hp = max_hp


func clamp_current_hp() -> void:
	current_hp = clampi(current_hp, 0, maxi(max_hp, 0))
