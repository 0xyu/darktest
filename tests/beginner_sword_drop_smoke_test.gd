extends SceneTree

## Beginner Sword smoke test: the fixed item, its Stage 10 authoring, and the
## once-per-save grant rule.
## Run headless: godot --headless --path . -s res://tests/beginner_sword_drop_smoke_test.gd
##
## Verifies:
##   * the sword is FIXED data — authored affix, no rolled values, one identity
##   * Stage 10 ("forest_010") authors it as its boss's guaranteed drop
##   * that boss is a Mini Boss, which is the enemy the guarantee keys on
##   * the grant is one per SAVE: a replay grants nothing, a later save grants again

const AuthoredContentStateScript = preload("res://scripts/progress/authored_content_state.gd")
const LootSystemScript = preload("res://scripts/systems/loot_system.gd")

const SWORD_PATH := "res://resources/items/beginner_sword.tres"
const LEVEL_010_PATH := "res://resources/levels/level_010.tres"
const STAGE_10_KEY := "forest_010"
const SWORD_ID := &"beginner_sword"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_sword_is_fixed_data()
	_test_stage_10_authors_the_sword()
	_test_grant_is_once_per_save()
	_test_boss_kill_path()

	if _failures.is_empty():
		print("Beginner Sword smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_sword_is_fixed_data() -> void:
	var definition: EquipmentDefinition = load(SWORD_PATH)
	_expect(definition != null, "the Beginner Sword resource loads")
	if definition == null:
		return

	_expect(String(definition.definition_id) == String(SWORD_ID), "its id is beginner_sword")
	_expect(definition.display_name == "Beginner Sword", "its name is 'Beginner Sword'")
	_expect(definition.slot == EquipmentSlot.WEAPON, "it is a weapon")
	_expect(not definition.is_consumable, "it is not a consumable")
	_expect(definition.unique_effect_id == &"", "it carries no unique effect")
	_expect(definition.base_affixes.size() == 1, "it authors exactly one affix")
	if definition.base_affixes.size() != 1:
		return
	var affix: EquipmentAffix = definition.base_affixes[0]
	_expect(affix.stat_id == &"attack", "its affix is attack")
	_expect(is_equal_approx(affix.value, 10.0), "its attack value is the authored 10")
	_expect(not affix.is_percentage, "its attack value is flat, not a percentage")

	# Fixed means fixed: two instances of the definition are identical, because
	# nothing is rolled when the instance is built.
	var first: EquipmentInstance = EquipmentInstance.create_from_definition(definition)
	var second: EquipmentInstance = EquipmentInstance.create_from_definition(definition)
	_expect(first != null, "a fixed instance can be created from the definition")
	_expect(not first.affixes.is_empty(), "the fixed instance carries the authored affix")
	_expect(is_equal_approx(first.get_affix_value(&"attack"), 10.0), "the instance rolls no attack value")
	_expect(first.affixes.size() == second.affixes.size(), "two fixed instances roll the same affix count")
	_expect(
		is_equal_approx(first.get_affix_value(&"attack"), second.get_affix_value(&"attack")),
		"two fixed instances have identical attack"
	)
	_expect(first.instance_id == SWORD_ID, "a fixed instance is identified by its definition id")
	_expect(first.get_slot() == EquipmentSlot.WEAPON, "the instance reports the weapon slot")


func _test_stage_10_authors_the_sword() -> void:
	var config: LevelConfig = load(LEVEL_010_PATH)
	_expect(config != null, "level_010.tres loads as a LevelConfig")
	if config == null:
		return
	_expect(config.boss != null, "stage 10 authors a boss")
	_expect(
		config.boss != null and EnemyType.is_boss(config.boss.enemy_type),
		"the stage 10 boss is a Mini Boss, which is what the guarantee keys on"
	)

	var definition: StageDefinition = config.to_stage_definition()
	_expect(definition.guaranteed_loot.size() == 1, "stage 10 guarantees exactly one fixed drop")
	if definition.guaranteed_loot.size() != 1:
		return
	var guaranteed: EquipmentDefinition = definition.guaranteed_loot[0]
	_expect(guaranteed != null, "the guaranteed drop resolves")
	_expect(
		guaranteed != null and guaranteed.definition_id == SWORD_ID,
		"the guaranteed drop is the Beginner Sword"
	)


func _test_grant_is_once_per_save() -> void:
	var config: LevelConfig = load(LEVEL_010_PATH)
	if config == null:
		return
	var guaranteed: Array[EquipmentDefinition] = config.to_stage_definition().guaranteed_loot
	var loot_system = LootSystemScript.new()
	var state: AuthoredContentState = AuthoredContentStateScript.new()
	loot_system.attach_content_state(state)

	var first_loot: Array[EquipmentInstance] = []
	loot_system.grant_guaranteed_drops(first_loot, guaranteed, STAGE_10_KEY)
	_expect(first_loot.size() == 1, "the first Stage 10 kill grants the sword")
	_expect(
		state.is_consumed(STAGE_10_KEY, SWORD_ID),
		"the grant is recorded under the canonical stage id forest_010"
	)
	if first_loot.size() == 1:
		_expect(
			first_loot[0].get_display_name() == "Beginner Sword",
			"the granted item is the Beginner Sword"
		)

	var replay_loot: Array[EquipmentInstance] = []
	loot_system.grant_guaranteed_drops(replay_loot, guaranteed, STAGE_10_KEY)
	_expect(replay_loot.is_empty(), "replaying Stage 10 in the same save grants nothing")

	# "Once per SAVE", not once ever: a different save has its own record.
	var fresh_state: AuthoredContentState = AuthoredContentStateScript.new()
	loot_system.attach_content_state(fresh_state)
	var new_save_loot: Array[EquipmentInstance] = []
	loot_system.grant_guaranteed_drops(new_save_loot, guaranteed, STAGE_10_KEY)
	_expect(new_save_loot.size() == 1, "a fresh save grants the sword again")

	# A stage with no authored guarantee pays out nothing extra.
	var empty_loot: Array[EquipmentInstance] = []
	var no_guarantee: Array[EquipmentDefinition] = []
	loot_system.grant_guaranteed_drops(empty_loot, no_guarantee, "forest_009")
	_expect(empty_loot.is_empty(), "a stage without guaranteed loot grants nothing")

	loot_system.free()


## The real defeat path: a boss kill on Stage 10 pays the sword out of the LIVE
## stage definition, and the same stage does not pay it twice.
func _test_boss_kill_path() -> void:
	var config: LevelConfig = load(LEVEL_010_PATH)
	_expect(config != null, "level_010.tres loads for the defeat-path test")
	if config == null:
		return

	var stage_manager := StageManager.new()
	stage_manager.current_definition = config.to_stage_definition()
	var boss := EnemyController.new()
	boss.enemy_data = config.boss

	var loot_system = LootSystemScript.new()
	loot_system.attach_stage_manager(stage_manager)
	loot_system.attach_content_state(AuthoredContentStateScript.new())

	var first_loot: Array[EquipmentInstance] = loot_system.generate_loot_for_enemy(boss, 10)
	_expect(_contains_sword(first_loot), "killing the Stage 10 boss drops the Beginner Sword")
	_expect(first_loot.size() >= 1, "the boss still rolls its own loot table")

	var replay_loot: Array[EquipmentInstance] = loot_system.generate_loot_for_enemy(boss, 10)
	_expect(not _contains_sword(replay_loot), "a second Stage 10 boss kill drops no sword")

	# Only the BOSS pays the stage guarantee: a normal enemy on stage 10 does not.
	var minion := EnemyController.new()
	minion.enemy_data = EnemyData.new()
	minion.enemy_data.enemy_type = EnemyType.NORMAL
	var minion_loot: Array[EquipmentInstance] = loot_system.generate_loot_for_enemy(minion, 10)
	_expect(not _contains_sword(minion_loot), "only the boss pays out the guaranteed drop")

	# A stage that authors no guarantee never pays one, boss or not.
	var plain_definition := StageDefinition.new()
	plain_definition.stage_number = 9
	stage_manager.current_definition = plain_definition
	var plain_loot: Array[EquipmentInstance] = loot_system.generate_loot_for_enemy(boss, 9)
	_expect(not _contains_sword(plain_loot), "a stage authoring no guarantee grants no sword")

	loot_system.free()
	stage_manager.free()
	boss.free()
	minion.free()


func _contains_sword(loot: Array[EquipmentInstance]) -> bool:
	for item in loot:
		if item != null and item.definition != null and item.definition.definition_id == SWORD_ID:
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)