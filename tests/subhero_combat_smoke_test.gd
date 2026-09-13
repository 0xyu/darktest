extends SceneTree

const ManagerScript = preload("res://scripts/sub_hero/sub_hero_combat_manager.gd")
const InstanceScript = preload("res://scripts/sub_hero/sub_hero_instance.gd")
const SkeletonDataPath := "res://resources/sub_heroes/common/SkeletonArcher.tres"
const ServantDataPath := "res://resources/sub_heroes/common/DarkServant.tres"


class MockEnemy:
	extends Node

	signal defeated
	var enemy_id: StringName
	var current_hp: int
	var is_mini_boss: bool = false
	var grid_position: Vector2i
	var defeated_flag: bool = false

	func _init(source_id: StringName, source_hp: int, source_position: Vector2i) -> void:
		enemy_id = source_id
		current_hp = source_hp
		grid_position = source_position

	func get_current_hp() -> int:
		return current_hp

	func set_current_hp(value: int) -> void:
		current_hp = maxi(value, 0)

	func handle_defeat() -> void:
		if defeated_flag:
			return
		defeated_flag = true
		defeated.emit(self)

	func is_defeated() -> bool:
		return defeated_flag


## A target that exposes real `EnemyStats`, so the armor entry has a defense to read.
class MockArmoredEnemy:
	extends Node

	var enemy_stats: EnemyStats

	func _init(source_hp: int, source_defense: int) -> void:
		enemy_stats = EnemyStats.new()
		enemy_stats.max_hp = maxi(source_hp, 1)
		enemy_stats.current_hp = enemy_stats.max_hp
		enemy_stats.attack = 1
		enemy_stats.defense = maxi(source_defense, 0)


var _failures: Array[String] = []
var _attack_results: Array[Resource] = []
var _deaths: Array[Node] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var skeleton_data = load(SkeletonDataPath)
	var servant_data = load(ServantDataPath)
	var skeleton = InstanceScript.new(&"skeleton_archer", 1)
	var servant = InstanceScript.new(&"dark_servant", 2)
	var manager = ManagerScript.new()
	root.add_child(manager)
	# A Sub Hero kill must travel the same kill path as a player kill, which is
	# CombatSystem.resolve_defeat() -> actor_died (EXP, gold and loot listeners).
	var combat_system := CombatSystem.new()
	root.add_child(combat_system)
	combat_system.actor_died.connect(_on_actor_died)
	manager.attach_combat_system(combat_system)
	manager.attack_resolved.connect(_on_attack_resolved)
	_expect(manager.register_active_sub_hero(skeleton, skeleton_data), "skeleton should register")
	_expect(manager.register_active_sub_hero(servant, servant_data), "servant should register")

	var high_hp_enemy := MockEnemy.new(&"far_enemy", 80, Vector2i(100, 100))
	var lowest_hp_enemy := MockEnemy.new(&"low_enemy", 20, Vector2i(0, 0))
	root.add_child(high_hp_enemy)
	root.add_child(lowest_hp_enemy)
	manager.start_combat([high_hp_enemy, lowest_hp_enemy])
	manager._process(1.8)
	_expect(_attack_results.size() == 1, "only the faster Sub Hero should attack at 1.8 seconds")
	_expect(_attack_results[0].target_id == &"low_enemy", "targeting should choose lowest HP regardless of distance")
	_expect(lowest_hp_enemy.current_hp == 12, "Skeleton Archer should apply configured damage")
	_expect(manager.get_current_target(&"skeleton_archer") == lowest_hp_enemy, "current target should be exposed")

	manager._process(1.2)
	_expect(_attack_results.size() == 2, "Dark Servant should attack on its independent 3 second timer")
	_expect(lowest_hp_enemy.current_hp == 0, "level two Dark Servant should defeat the low HP enemy")
	_expect(lowest_hp_enemy.defeated_flag, "lethal Sub Hero damage should call enemy defeat")
	_expect(_deaths.size() == 1 and _deaths[0] == lowest_hp_enemy, "lethal Sub Hero damage should announce the death on CombatSystem.actor_died")
	_expect(manager.get_current_target(&"skeleton_archer") == null, "dead target should be cleared")

	manager._process(1.8)
	_expect(high_hp_enemy.current_hp == 72, "Sub Hero should retarget a living enemy after death")
	manager.stop_combat()
	manager._process(10.0)
	_expect(high_hp_enemy.current_hp == 72, "stopped combat should not leak attacks")

	var scaled_damage: int = manager.calculate_subhero_damage(skeleton_data, InstanceScript.new(&"skeleton_archer", 3), null)
	_expect(scaled_damage == 8, "an unarmored target takes the Sub Hero's attack power unchanged (got %d)" % scaled_damage)

	# §4.1/§6.2: a Sub Hero resolves through the SAME armor entry as every other damage source, so an
	# armored target takes less while a weak attacker still chips instead of hitting a wall.
	var armored := MockArmoredEnemy.new(1000, 8)
	root.add_child(armored)
	var armored_damage: int = manager.calculate_subhero_damage(skeleton_data, InstanceScript.new(&"skeleton_archer", 3), armored)
	_expect(
		armored_damage < scaled_damage and armored_damage >= 1,
		"armor reduces Sub Hero damage but never below 1 (got %d vs %d)" % [armored_damage, scaled_damage]
	)
	var expected_armored: int = maxi(
		roundi(BalanceFormulas.armor_damage(BalanceProfile.get_default(), float(scaled_damage), 8.0)),
		1
	)
	_expect(
		armored_damage == expected_armored,
		"the armored hit IS the shared armor formula (%d vs %d)" % [armored_damage, expected_armored]
	)
	armored.free()

	manager.free()
	combat_system.free()
	if _failures.is_empty():
		print("Sub Hero combat smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _on_attack_resolved(result: Resource) -> void:
	_attack_results.append(result)


func _on_actor_died(actor: Node) -> void:
	_deaths.append(actor)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
