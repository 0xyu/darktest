class_name MagicTome
extends Node

## The player's Magic Tome companion (docs/game-design.md §16).
##
## Design contract, in three lines:
##   * Its spells are GLOBALLY available — any living enemy can be struck from any
##     cell, so casting is never a positioning puzzle.
##   * A cast is FREE — it never consumes the player's action and never advances the
##     turn, so the tome can be used during the enemy phase and during AUTO mode.
##     This is what gives the player something to do while automation fights.
##   * The only cost is a cooldown measured in PLAYER TURNS, never in real time: a
##     cast arms its cooldown, and every new Player Turn ticks every armed cooldown
##     down by one.
##
## The tome owns no combat rules. Strikes are resolved by CombatSystem (the ONE
## damage / defeat / reward path) and the player-turn clock comes from TurnManager,
## so a tome kill grants exactly what a weapon kill grants.

signal skill_cast(skill_id: StringName, hit_count: int, total_damage: int)
signal skill_refused(skill_id: StringName, reason: String)
signal cooldowns_changed(cooldowns: Dictionary)

var _combat_system: CombatSystem
var _turn_manager: TurnManager
var _caster: Node
## skill_id -> Player Turns remaining. An absent entry means "ready to cast".
var _cooldowns: Dictionary = {}


## Binds the tome to the systems it reads. Connected once: the cooldown clock is the
## turn manager's `player_turn_started`, which fires for the player's own turn and
## for an AUTO-driven one alike.
func attach(combat_system: CombatSystem, turn_manager: TurnManager, caster: Node) -> void:
	_combat_system = combat_system
	_turn_manager = turn_manager
	_caster = caster
	if _turn_manager == null:
		return
	var turn_signal: Signal = _turn_manager.player_turn_started
	if not turn_signal.is_connected(_on_player_turn_started):
		turn_signal.connect(_on_player_turn_started)


func get_skills() -> Array[MagicSkillDefinition]:
	return MagicTomeCatalog.get_all()


func get_cooldown(skill_id: StringName) -> int:
	return maxi(int(_cooldowns.get(skill_id, 0)), 0)


func get_cooldowns() -> Dictionary:
	return _cooldowns.duplicate()


func is_ready(skill_id: StringName) -> bool:
	return get_cooldown(skill_id) <= 0


## Whether a cast would do something right now: a known spell, off cooldown, with at
## least one living enemy to strike. The turn phase is deliberately NOT consulted.
func can_cast(skill_id: StringName) -> bool:
	var skill := MagicTomeCatalog.get_skill(skill_id)
	if skill.skill_id.is_empty() or not is_ready(skill_id):
		return false
	# A caster with no combat stats (for example before the player is initialised)
	# cannot land a strike, so the row must not offer one.
	if _combat_system == null or not _combat_system.is_living_target(_caster):
		return false
	return not _collect_targets(skill, null).is_empty()


## Casts a spell. `preferred_target` is the enemy the player has selected; when it is
## missing or dead a single-target spell falls back to the nearest living enemy.
## Returns false (and emits `skill_refused`) when nothing was struck.
func cast(skill_id: StringName, preferred_target: Node = null) -> bool:
	var skill := MagicTomeCatalog.get_skill(skill_id)
	if skill.skill_id.is_empty():
		skill_refused.emit(skill_id, "Unknown spell")
		return false
	if not is_ready(skill_id):
		skill_refused.emit(skill_id, "Still recharging")
		return false
	if _combat_system == null or _caster == null or not is_instance_valid(_caster):
		skill_refused.emit(skill_id, "The tome is dormant")
		return false

	var targets: Array[Node] = _collect_targets(skill, preferred_target)
	if targets.is_empty():
		skill_refused.emit(skill_id, "No enemy to strike")
		return false

	var hit_count: int = 0
	var total_damage: int = 0
	for target in targets:
		# A lethal hit on the last enemy can clear the stage mid-loop, so the host
		# list is re-checked per target instead of trusted for the whole cast.
		if not is_instance_valid(target):
			continue
		var result: DamageResult = _combat_system.resolve_magic_strike(
			_caster, target, skill.damage_multiplier, skill.skill_id
		)
		if result == null or result.is_refused:
			continue
		# A dodged spell still counts as cast (it arms the cooldown) but deals nothing.
		hit_count += 1
		total_damage += result.final_damage

	if hit_count == 0:
		skill_refused.emit(skill_id, "No enemy to strike")
		return false

	_start_cooldown(skill)
	cooldowns_changed.emit(get_cooldowns())
	skill_cast.emit(skill.skill_id, hit_count, total_damage)
	return true


func _start_cooldown(skill: MagicSkillDefinition) -> void:
	if skill.cooldown_turns <= 0:
		return
	_cooldowns[skill.skill_id] = skill.cooldown_turns


## §16: one tick per new Player Turn — the only thing that ever lowers a cooldown.
## Reaching zero removes the entry, which is what makes the spell READY again.
func _on_player_turn_started() -> void:
	if _cooldowns.is_empty():
		return
	for key in _cooldowns.keys():
		var remaining: int = int(_cooldowns[key]) - 1
		if remaining <= 0:
			_cooldowns.erase(key)
		else:
			_cooldowns[key] = remaining
	cooldowns_changed.emit(get_cooldowns())


## The enemies a cast would hit: every living enemy for an area spell, otherwise the
## selected target or — with nothing selected — the nearest living enemy.
func _collect_targets(skill: MagicSkillDefinition, preferred_target: Node) -> Array[Node]:
	var living: Array[Node] = _living_enemies()
	var targets: Array[Node] = []
	if living.is_empty():
		return targets
	if skill.hits_every_enemy():
		return living
	var chosen: Node = preferred_target if _is_living_enemy(preferred_target) else _nearest_enemy(living)
	if chosen != null:
		targets.append(chosen)
	return targets


func _living_enemies() -> Array[Node]:
	var living: Array[Node] = []
	if _combat_system == null:
		return living
	for candidate in _combat_system.get_combat_targets():
		if _combat_system.is_living_target(candidate):
			living.append(candidate)
	return living


func _is_living_enemy(candidate: Node) -> bool:
	return _combat_system != null and _combat_system.is_living_target(candidate)


func _nearest_enemy(candidates: Array[Node]) -> Node:
	var caster_cell: Vector2i = _grid_cell(_caster)
	var best: Node = null
	var best_distance: int = 0
	for candidate in candidates:
		var distance: int = _cell_distance(caster_cell, _grid_cell(candidate))
		if best == null or distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _grid_cell(actor: Node) -> Vector2i:
	if actor != null and is_instance_valid(actor):
		var value: Variant = actor.get("grid_position")
		if value is Vector2i:
			return value
	return Vector2i.ZERO


func _cell_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
