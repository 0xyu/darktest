extends SceneTree

## A Sub Hero killing blow must travel exactly the same kill path as the player's
## own blow: CombatSystem.resolve_defeat() -> actor_died -> the EXP, gold and loot
## listeners. This test drives that path deterministically on the real game scene
## (no wall-clock waits), so a regression back to a private defeat call shows up
## here as missing rewards.

const GameScene = preload("res://scenes/world/grid_combat.tscn")
const InstanceScript = preload("res://scripts/sub_hero/sub_hero_instance.gd")

var _failures: Array[String] = []
## Rewards attributed to the Sub Hero's kill, matched by the reward source name so
## a stage-clear reward cannot be mistaken for the kill.
var _kill_source: String = ""
var _kill_experience: int = 0
var _kill_gold: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame

	var player: PlayerController = game.get_node("Player")
	var manager: SubHeroCombatManager = game.get_node("SubHeroCombatManager")
	var stage_manager: StageManager = game.get_node("StageManager")
	var experience_system: ExperienceSystem = game.get_node("ExperienceSystem")
	var gold_system: GoldSystem = game.get_node("GoldSystem")

	player.add_sub_hero(InstanceScript.new(&"skeleton_archer", 1))
	_expect(player.assign_sub_hero_slot(0, &"skeleton_archer"), "Sub Hero should assign to the active combat slot")
	await process_frame
	_expect(manager.is_combat_running(), "Sub Hero combat should be running after stage start")

	var enemies: Array[EnemyController] = stage_manager.get_spawned_enemies()
	_expect(not enemies.is_empty(), "stage should have a live enemy")
	if not enemies.is_empty():
		var enemy: EnemyController = enemies[0]
		_kill_source = enemy.get_display_name()
		experience_system.experience_awarded.connect(_on_experience_awarded)
		gold_system.gold_awarded.connect(_on_gold_awarded)
		# The Sub Hero's own timer is driven directly: the outcome does not depend on
		# wall-clock timing. The damaged enemy is the lowest-HP one, so it is picked.
		enemy.set_current_hp(1)
		manager._process(5.0)
		_expect(enemy.is_defeated(), "a lethal Sub Hero blow defeats the enemy")
		_expect(_kill_experience > 0, "a Sub Hero kill awards EXP like a player kill")
		_expect(_kill_gold > 0, "a Sub Hero kill awards gold like a player kill")

	game.queue_free()
	if _failures.is_empty():
		print("Sub Hero kill reward smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _on_experience_awarded(amount: int, _current: int, _required: int, source_name: String) -> void:
	if not _kill_source.is_empty() and source_name == _kill_source:
		_kill_experience += amount


func _on_gold_awarded(amount: int, _current: int, source_name: String) -> void:
	if not _kill_source.is_empty() and source_name == _kill_source:
		_kill_gold += amount


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
