extends SceneTree

var _failures: Array[String] = []
var _combat := CombatSystem.new()
var _unparented_nodes: Array[Node] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	root.add_child(_combat)
	await process_frame

	var third_attack_player := _make_player(&"every_3rd_attack")
	var enemy := _make_enemy()
	var first := _resolve(third_attack_player, enemy)
	var second := _resolve(third_attack_player, enemy)
	var third := _resolve(third_attack_player, enemy)
	_expect(first.final_damage == 10 and second.final_damage == 10, "every third attack leaves the first two attacks unchanged")
	_expect(third.final_damage == 20, "every third attack deals double damage")

	var critical_player := _make_player(&"critical_healing")
	critical_player.player_stats.current_hp = 50
	critical_player.player_stats.critical_chance = 1.0
	var critical_result := _resolve(critical_player, enemy)
	_expect(critical_result.is_critical, "critical healing effect can receive a critical result")
	_expect(critical_player.player_stats.current_hp == 55, "critical attack restores five percent of max HP")

	var movement_grid := GridMap2D.new()
	movement_grid.name = "MovementGrid"
	movement_grid.grid_size = Vector2i(6, 3)
	root.add_child(movement_grid)
	var movement_player := _make_player(&"movement_attack")
	movement_player.grid_path = NodePath("../MovementGrid")
	movement_player.grid_position = Vector2i(1, 1)
	root.add_child(movement_player)
	await process_frame
	_expect(movement_player.try_move(Vector2i.RIGHT), "movement effect test moves one cell")
	_expect(movement_player.try_move(Vector2i.RIGHT), "movement effect test moves two cells")
	enemy.grid_position = Vector2i(4, 1)
	var movement_result := _resolve(movement_player, enemy)
	_expect(movement_result.final_damage == 18, "moving two cells before attacking adds seventy-five percent damage")

	var back_player := _make_player(&"back_attack")
	back_player.grid_position = Vector2i(1, 1)
	enemy.grid_position = Vector2i(2, 1)
	enemy.facing_direction = Vector2i.RIGHT
	var back_result := _resolve(back_player, enemy)
	_expect(back_result.final_damage == 20, "attacking from behind deals double damage")

	var poison_player := _make_player(&"poisoned_target")
	enemy.set_poisoned(true)
	var poison_result := _resolve(poison_player, enemy)
	_expect(poison_result.final_damage == 15, "attacking a poisoned enemy adds fifty percent damage")
	enemy.set_poisoned(false)

	var effect_ids: Array[StringName] = [
		&"every_3rd_attack",
		&"critical_healing",
		&"movement_attack",
		&"back_attack",
		&"poisoned_target",
	]
	for effect_id in effect_ids:
		_expect(EquipmentEffect.create_for_id(effect_id) != null, "effect factory creates " + String(effect_id))
	var mythic := EquipmentGenerator.new(1901).generate_equipment(20, EquipmentSlot.AMULET, EquipmentRarity.MYTHIC)
	_expect(mythic.definition.unique_effect_id != &"", "Mythic equipment guarantees a unique effect")

	if _failures.is_empty():
		print("Phase 19 smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	for child in root.get_children():
		child.free()
	for node in _unparented_nodes:
		if is_instance_valid(node):
			node.free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _make_player(effect_id: StringName) -> PlayerController:
	var player := PlayerController.new()
	player.player_stats = PlayerStats.new()
	player.player_stats.attack = 10
	player.player_stats.defense = 0
	player.player_stats.current_hp = player.player_stats.max_hp
	player.set_equipment_inventory(EquipmentInventory.new())
	var definition := EquipmentDefinition.new()
	definition.display_name = String(effect_id)
	definition.slot = EquipmentSlot.RING
	definition.unique_effect_id = effect_id
	var item := EquipmentInstance.new()
	item.instance_id = StringName("item_" + String(effect_id))
	item.definition = definition
	player.add_equipment(item)
	player.equip_item(item)
	_unparented_nodes.append(player)
	return player


func _make_enemy() -> EnemyController:
	var enemy := EnemyController.new()
	enemy.grid_position = Vector2i(2, 1)
	enemy.enemy_stats = EnemyStats.new()
	enemy.enemy_stats.max_hp = 1000
	enemy.enemy_stats.current_hp = 1000
	enemy.enemy_stats.defense = 0
	_unparented_nodes.append(enemy)
	return enemy


func _resolve(player: PlayerController, enemy: EnemyController) -> DamageResult:
	enemy.enemy_stats.current_hp = enemy.enemy_stats.max_hp
	return _combat.resolve_attack(player, enemy)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)
