class_name LootSystem
extends Node

## Converts enemy defeats into equipment-drop events without owning an inventory.
signal loot_dropped(enemy: Node, loot: Array[EquipmentInstance])

@export var random_seed: int = 0

var _loot_generator: LootGenerator
var _combat_system: CombatSystem
var _stage_manager: StageManager
## Which guaranteed drops this save has already granted. The same store the save
## persists, so a stage's fixed reward is one-per-save rather than one-per-kill.
var _content_state: AuthoredContentState
## The hero, read only for the equipment slots that are still EMPTY (§8 M5 slot coverage).
var _player: PlayerController


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


## Wires the hero whose EMPTY equipment slots a drop should cover (§8 M5 "保底掉落的槽位覆盖").
## Optional: without a player a drop rolls its slot at random, which is the pre-R3 behaviour.
func attach_player(player: PlayerController) -> void:
	_player = player


## The equipment slots the hero has nothing equipped in. Empty when no player is attached.
func get_empty_equipment_slots() -> Array[int]:
	var slots: Array[int] = []
	if _player == null or not is_instance_valid(_player):
		return slots
	var inventory: EquipmentInventory = _player.get_inventory()
	if inventory == null:
		return slots
	for slot in range(EquipmentSlot.WEAPON, EquipmentSlot.AMULET + 1):
		if inventory.get_equipped_item(slot) == null:
			slots.append(slot)
	return slots


## Wires the one-shot store the guaranteed-drop rule records into. Optional: with no
## store the fixed drops still happen, they just cannot be recorded as granted.
func attach_content_state(content_state: AuthoredContentState) -> void:
	_content_state = content_state


func get_loot_generator() -> LootGenerator:
	if _loot_generator == null:
		_loot_generator = LootGenerator.new(random_seed)
	return _loot_generator


func generate_loot_for_enemy(enemy: EnemyController, stage_number: int = 1) -> Array[EquipmentInstance]:
	# §8 M5: while the hero still has empty equipment slots, a drop covers one of them instead of
	# rolling a random slot — without it the seven slots are only covered by luck (a coupon
	# collector needs ~30 drops, and the first nine stages offer ~18 kills).
	var loot: Array[EquipmentInstance] = get_loot_generator().generate_loot(
		enemy, stage_number, get_empty_equipment_slots()
	)
	# The stage's authored fixed drops ride on top of the rolled loot, and only off
	# the boss: the stage grants them, the boss is what has to fall for them.
	if _is_boss(enemy):
		_append_stage_guarantees(loot)
	return loot


## Appends every entry of `guaranteed` that `stage_key` has not granted yet, and
## records each grant. Split out from the defeat path so the rule can be exercised
## without an enemy node.
func grant_guaranteed_drops(
	loot: Array[EquipmentInstance],
	guaranteed: Array[EquipmentDefinition],
	stage_key: String
) -> void:
	for definition in guaranteed:
		if definition == null:
			continue
		if _content_state != null and _content_state.is_consumed(stage_key, definition.definition_id):
			continue
		loot.append(EquipmentInstance.create_from_definition(definition))
		if _content_state != null:
			_content_state.consume(stage_key, definition.definition_id)


## Appends the live stage's authored fixed drops. The one-shot key is scoped to the
## DEFINITION's own stage number, so the stage that authors a reward is the stage
## that pays it — not whichever number a caller happened to pass in.
func _append_stage_guarantees(loot: Array[EquipmentInstance]) -> void:
	var definition: StageDefinition = null
	if _stage_manager != null:
		definition = _stage_manager.current_definition
	if definition == null or definition.guaranteed_loot.is_empty():
		return
	grant_guaranteed_drops(loot, definition.guaranteed_loot, _stage_key_for(definition.stage_number))


func _is_boss(enemy: EnemyController) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var enemy_data: EnemyData = enemy.enemy_data
	return enemy_data != null and EnemyType.is_boss(enemy_data.enemy_type)


## The canonical stage id a one-shot key is scoped to, e.g. "forest_010". A stage
## past every authored area has no StageData, so its global number names it instead.
func _stage_key_for(stage_number: int) -> String:
	var safe_number: int = maxi(stage_number, 1)
	var stage = StageDatabase.lookup(safe_number)
	if stage == null or String(stage.id).is_empty():
		return "stage_%d" % safe_number
	return String(stage.id)


func _on_actor_died(actor: Node) -> void:
	if not actor is EnemyController:
		return
	var stage_number: int = 1
	if _stage_manager != null and _stage_manager.stage_state != null:
		stage_number = _stage_manager.stage_state.stage_number
	var loot: Array[EquipmentInstance] = generate_loot_for_enemy(actor as EnemyController, stage_number)
	if not loot.is_empty():
		loot_dropped.emit(actor, loot)
