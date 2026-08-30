@tool
extends SceneTree

## One-off generator: builds randomized EnemyData resources from the Oryx
## creature atlas and a YARD Registry that indexes them. Run with:
## godot --headless --path . --script tools/generate_enemy_registry.gd

const OUTPUT_DIR := "res://resources/enemies/generated"
const REGISTRY_PATH := "res://resources/enemies/enemy_registry.tres"
const GENERATED_ENEMY_COUNT := 24
const MIN_LEVEL := 1
const MAX_LEVEL := 12
const MIN_HP := 35
const MAX_HP := 160
const MIN_ATTACK := 6
const MAX_ATTACK := 26
const MIN_DEFENSE := 1
const MAX_DEFENSE := 8
const MIN_GOLD := 6
const MAX_GOLD := 40
const GENERATOR_SEED := 20260830

const NAME_PREFIXES: Array[String] = [
	"Foul", "Rotting", "Ashen", "Cursed", "Withered", "Grim",
	"Hollow", "Blighted", "Dread", "Pale",
]
const NAME_CORES: Array[String] = [
	"Thrall", "Stalker", "Hound", "Revenant", "Fiend", "Ghoul",
	"Crawler", "Wretch", "Shade", "Brute",
]
const DESCRIPTIONS: Array[String] = [
	"A wretched creature drawn to the player by the scent of blood.",
	"It stalks the dark corridors, hungry and patient.",
	"Twisted by the curse, it knows only hunger and hate.",
	"Something once mortal, now hollowed out by the dark.",
	"It crawls from the rift, clawing at the living.",
	"A minor horror of the deeper stages.",
]

const RegistryIOLoader := preload("res://addons/yard/editor_only/registry_io.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GENERATOR_SEED

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var catalog_ids := CharacterSpriteCatalog.get_discovered_ids()
	if catalog_ids.is_empty():
		push_error("No atlas sprites discovered; cannot generate enemies.")
		quit(1)
		return

	var existing_files := _collect_existing_generated_files()
	var unused_ids := _pick_unused_sprite_ids(catalog_ids, existing_files)

	var generated_paths: Array[String] = []
	for index in range(GENERATED_ENEMY_COUNT):
		var character_id: StringName = unused_ids[index % unused_ids.size()]
		var path := _generate_enemy_resource(index, character_id, rng)
		if not path.is_empty():
			generated_paths.append(path)
	_save_registry(generated_paths)
	quit(0)


func _collect_existing_generated_files() -> Dictionary:
	var found := {}
	var dir := DirAccess.open(OUTPUT_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var next := dir.get_next()
	while next != "":
		if not dir.current_is_dir() and next.ends_with(".tres"):
			found[next.get_basename()] = true
		next = dir.get_next()
	dir.list_dir_end()
	return found


func _pick_unused_sprite_ids(catalog_ids: Array[StringName], existing_files: Dictionary) -> Array[StringName]:
	var pool: Array[StringName] = []
	for character_id in catalog_ids:
		# Skip named heroes/bosses so random enemies never reuse their art.
		if CharacterSpriteCatalog.CHARACTER_CELLS.has(character_id):
			continue
		var cell := CharacterSpriteCatalog.get_cell(character_id)
		var inferred_name := "enemy_atlas_%02d_%02d" % [cell.x, cell.y]
		if not existing_files.has(inferred_name):
			pool.append(character_id)
	if pool.size() < GENERATED_ENEMY_COUNT:
		# Not enough unused cells left; reuse all discovered IDs.
		pool = catalog_ids.duplicate()
	# Deterministic shuffle.
	var rng := RandomNumberGenerator.new()
	rng.seed = GENERATOR_SEED
	for index in range(pool.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: StringName = pool[index]
		pool[index] = pool[swap_index]
		pool[swap_index] = tmp
	return pool


func _generate_enemy_resource(index: int, character_id: StringName, rng: RandomNumberGenerator) -> String:
	var cell := CharacterSpriteCatalog.get_cell(character_id)
	var base_name := "enemy_atlas_%02d_%02d" % [cell.x, cell.y]
	var display_name := "%s %s" % [
		NAME_PREFIXES[rng.randi_range(0, NAME_PREFIXES.size() - 1)],
		NAME_CORES[rng.randi_range(0, NAME_CORES.size() - 1)],
	]

	var stats := EnemyStats.new()
	stats.level = rng.randi_range(MIN_LEVEL, MAX_LEVEL)
	stats.max_hp = rng.randi_range(MIN_HP, MAX_HP) + stats.level * 8
	stats.attack = rng.randi_range(MIN_ATTACK, MAX_ATTACK) + stats.level
	stats.defense = rng.randi_range(MIN_DEFENSE, MAX_DEFENSE)
	stats.movement_points = 2 + (1 if rng.randf() < 0.3 else 0)
	stats.attack_range = 1
	stats.experience_reward = stats.level * 18 + rng.randi_range(5, 20)
	stats.gold_reward = rng.randi_range(MIN_GOLD, MAX_GOLD) + stats.level * 3

	var enemy := EnemyData.new()
	enemy.id = StringName(base_name)
	enemy.name = display_name
	enemy.enemy_type = EnemyType.NORMAL
	enemy.base_stats = stats
	enemy.character_sprite_id = character_id
	enemy.description = DESCRIPTIONS[rng.randi_range(0, DESCRIPTIONS.size() - 1)]

	var path := "%s/%s.tres" % [OUTPUT_DIR, base_name]
	var err := ResourceSaver.save(enemy, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		push_error("Failed to save enemy resource to %s (error %d)" % [path, err])
		return ""
	var uid_int := ResourceUID.create_id()
	ResourceSaver.set_uid(path, uid_int)
	ResourceUID.add_id(uid_int, path)
	print("Generated enemy: %s (id=%s, level=%d, sprite=%s)" % [display_name, base_name, stats.level, character_id])
	return path


func _save_registry(generated_paths: Array[String]) -> void:
	var registry := Registry.new()

	# Fill entries directly: Registry marks its maps read-only at runtime,
	# so RegistryIO.add_entry() cannot mutate them outside the editor.
	var uid_to_id: Dictionary[StringName, StringName] = {}
	var id_to_uid: Dictionary[StringName, StringName] = {}
	for path in generated_paths:
		var uid := ResourceUID.path_to_uid(path)
		var string_id := StringName(path.get_file().get_basename())
		uid_to_id[uid] = string_id
		id_to_uid[string_id] = uid

	registry._version = Registry._REGISTRY_FORMAT_VERSION
	registry._scan_auto = true
	registry._scan_remove = true
	# Values must be typed arrays so YARD's editor loader can assign them
	# back to the typed RegistryScanRuleset fields without errors.
	var class_restrictions: Array[StringName] = [&"EnemyData"]
	var scan_directories: Array[String] = [OUTPUT_DIR]
	var allowed_extensions: Array[String] = []
	registry._scan_rulesets = [
		{
			&"class_restrictions": class_restrictions,
			&"scan_directories": scan_directories,
			&"recursive_scan": true,
			&"allowed_file_extensions": allowed_extensions,
			&"scan_regex_include": "",
			&"scan_regex_exclude": "",
		},
	]
	registry._uids_to_string_ids = uid_to_id
	registry._string_ids_to_uids = id_to_uid
	registry._property_index = {
		&"enemy_type": {},
		&"base_stats.level": {},
	}
	registry.resource_path = REGISTRY_PATH
	RegistryIOLoader.rebuild_property_index(registry)
	# The registry file itself needs a uid:// so YARD's editor can resolve it.
	var save_err := ResourceSaver.save(registry, REGISTRY_PATH, ResourceSaver.FLAG_CHANGE_PATH)
	if save_err != OK:
		push_error("Failed to save registry to %s (error %d)" % [REGISTRY_PATH, save_err])
		return
	var registry_uid_int := ResourceUID.create_id()
	ResourceSaver.set_uid(REGISTRY_PATH, registry_uid_int)
	ResourceUID.add_id(registry_uid_int, REGISTRY_PATH)
	print("Registry saved: %s with %d entries." % [REGISTRY_PATH, registry.size()])
