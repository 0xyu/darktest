class_name LootSystem
extends Node

## Converts enemy defeats into equipment-drop events without owning an inventory.
signal loot_dropped(enemy: Node, loot: Array[EquipmentInstance])

@export var random_seed: int = 0

var _loot_generator: LootGenerator
var _combat_system: CombatSystem
var _stage_manager: StageManager


func _ready() -> void:
	_loot_generator = LootGenerator.new(random_seed)


func attach_combat_system(combat_system: CombatSystem) -> void:
	if _combat_system != null and _combat_system.actor_died.is_connected(_on_actor_died):
		_combat_system.actor_died.disconnect(_on_actor_died)
	_combat_system = combat_system
	if _combat_system == null:
		return
	if not _combat_system.actor_died.is_connected(_on_actor_died):
		_combat_system.actor_died.connect(_on_actor_died)


func attach_stage_manager(stage_manager: StageManager) -> void:
	_stage_manager = stage_manager


func get_loot_generator() -> LootGenerator:
	if _loot_generator == null:
		_loot_generator = LootGenerator.new(random_seed)
	return _loot_generator


func generate_loot_for_enemy(enemy: EnemyController, stage_number: int = 1) -> Array[EquipmentInstance]:
	return get_loot_generator().generate_loot(enemy, stage_number)


func _on_actor_died(actor: Node) -> void:
	if not actor is EnemyController:
		return
	var stage_number: int = 1
	if _stage_manager != null and _stage_manager.stage_state != null:
		stage_number = _stage_manager.stage_state.stage_number
	var loot: Array[EquipmentInstance] = generate_loot_for_enemy(actor as EnemyController, stage_number)
	if not loot.is_empty():
		loot_dropped.emit(actor, loot)
