@tool
extends SceneTree

## One-off generator: indexes the hand-authored item definitions under
## res://resources/items into a YARD Registry at
## res://resources/items/item_registry.tres.
##
## Unlike tools/generate_enemy_registry.gd this script does not generate any
## resource: it only builds the index. The single thing it writes back to an
## existing file is a `uid://` in the .tres header, assigned to any definition
## that lacks one — YARD keys its entries by UID and most hand-authored .tres
## files predate UID serialization. (ResourceSaver.set_uid() is not used: it
## crashes on Godot 4.7.2 for a resource that has no uid yet.) Run with:
## godot --headless --path . --script tools/generate_item_registry.gd

const SCAN_DIR := "res://resources/items"
const REGISTRY_PATH := "res://resources/items/item_registry.tres"
const DEFINITION_CLASS := &"EquipmentDefinition"
## Properties YARD pre-resolves so Registry.filter()/filter_by_value() work on
## them without loading each entry.
const INDEXED_PROPERTIES: Array[StringName] = [
	&"slot",
	&"rarity",
	&"item_level",
	&"is_consumable",
]

const RegistryIOLoader := preload("res://addons/yard/editor_only/registry_io.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var definition_paths := _collect_definition_paths()
	if definition_paths.is_empty():
		push_error("No %s resources found under %s; nothing to index." % [DEFINITION_CLASS, SCAN_DIR])
		return 1

	var uid_to_id: Dictionary[StringName, StringName] = {}
	var id_to_uid: Dictionary[StringName, StringName] = {}
	var used_ids := {}
	var indexed := 0
	var invalid := 0
	for path in definition_paths:
		var definition := ResourceLoader.load(path) as EquipmentDefinition
		if definition == null:
			push_warning("Skipping %s: not an %s." % [path, DEFINITION_CLASS])
			continue
		if not _validate_definition_affixes(path, definition):
			invalid += 1
			continue
		var uid := _ensure_uid(path)
		if uid.is_empty():
			push_warning("Skipping %s: could not resolve or assign a uid." % path)
			continue
		var string_id := _unique_string_id(path, used_ids)
		if StringName(path.get_file().get_basename()) != definition.definition_id:
			print("Note: %s is registered as '%s' (definition_id=%s)." % [
				path, string_id, definition.definition_id,
			])
		uid_to_id[StringName(uid)] = string_id
		id_to_uid[string_id] = StringName(uid)
		indexed += 1
		print("Indexed item: %s (%s, slot=%s)" % [
			definition.display_name, string_id, definition.get_slot_name(),
		])

	if indexed == 0:
		push_error("No %s resource could be indexed." % DEFINITION_CLASS)
		return 1
	if invalid > 0:
		push_error("%d definition(s) configure affixes the game cannot apply; registry not written." % invalid)
		return 1

	_save_registry(uid_to_id, id_to_uid)
	return 0 if _verify_registry(id_to_uid.keys()) else 1


## Rejects a definition whose configured affixes could never reach combat (§12:
## "affixes that only display are a defect"). An unknown `stat_id` is rolled,
## displayed and score-counted exactly like a real one, so the only place it can be
## caught is at authoring time — here.
func _validate_definition_affixes(path: String, definition: EquipmentDefinition) -> bool:
	var is_valid := true
	for affix in definition.base_affixes:
		if affix == null:
			continue
		if not EquipmentAffix.is_known_stat(affix.stat_id):
			push_error("%s: affix stat_id '%s' is not in the affix catalogue, so it can never affect combat." % [
				path, affix.stat_id,
			])
			is_valid = false
	if not definition.unique_effect_id.is_empty() \
			and EquipmentEffect.create_for_id(definition.unique_effect_id) == null:
		push_error("%s: unique_effect_id '%s' has no implementation." % [
			path, definition.unique_effect_id,
		])
		is_valid = false
	return is_valid


func _collect_definition_paths() -> Array[String]:
	var found: Array[String] = []
	_walk_dir(SCAN_DIR, found)
	found.sort()
	return found


func _walk_dir(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Cannot open scan directory: %s" % dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full_path := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_walk_dir(full_path, out)
		elif entry.ends_with(".tres") and full_path != REGISTRY_PATH:
			out.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


## Returns the resource's `uid://` text, assigning one when the file has none.
## The header is authoritative so that re-running this script keeps every uid
## stable; the uid cache is only consulted for files that have no header uid
## yet. (On Godot 4.7.2 ResourceUID.path_to_uid() returns the path itself when
## the resource is unknown.)
func _ensure_uid(path: String) -> String:
	var uid_text := _header_uid(path)
	if not uid_text.begins_with("uid://"):
		var cached := String(ResourceUID.path_to_uid(path))
		if cached.begins_with("uid://"):
			uid_text = cached
			if not _write_uid_to_header(path, uid_text):
				return ""
			print("Recorded uid %s in %s" % [uid_text, path])
		else:
			uid_text = ResourceUID.id_to_text(ResourceUID.create_id())
			if not _write_uid_to_header(path, uid_text):
				return ""
			print("Assigned uid %s to %s" % [uid_text, path])
	_register_uid(uid_text, path)
	return uid_text


## Registers a uid in the session's uid cache. Never steals a uid that already
## belongs to another resource.
func _register_uid(uid_text: String, path: String) -> void:
	var uid_int := ResourceUID.text_to_id(uid_text)
	if uid_int == ResourceUID.INVALID_ID or ResourceUID.has_id(uid_int):
		return
	ResourceUID.add_id(uid_int, path)


func _header_uid(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var header := file.get_line()
	file.close()
	var marker := header.find("uid=\"")
	if marker < 0:
		return ""
	var end := header.find("\"", marker + 5)
	if end < 0:
		return ""
	return header.substr(marker + 5, end - marker - 5)


## Writes the uid into the resource file's `[gd_resource ...]` header, which is
## where Godot serializes it, so the assignment survives version control and a
## rebuilt uid cache.
func _write_uid_to_header(path: String, uid_text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	var lines := file.get_as_text().split("\n")
	file.close()
	if lines.is_empty() or not lines[0].begins_with("[gd_resource"):
		push_error("%s does not start with a [gd_resource ...] header." % path)
		return false
	if lines[0].contains("uid=\""):
		return true

	var header := lines[0]
	var close_index := header.rfind("]")
	if close_index < 0:
		push_error("Malformed resource header in %s: %s" % [path, header])
		return false
	lines[0] = "%s uid=\"%s\"%s" % [
		header.substr(0, close_index), uid_text, header.substr(close_index),
	]

	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("Cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	out.store_string("\n".join(lines))
	out.close()
	return true


## File basename, forced unique: two definitions may legitimately share a
## definition_id, but a registry entry name must be unique.
func _unique_string_id(path: String, used_ids: Dictionary) -> StringName:
	var base_id := path.get_file().get_basename()
	var string_id := StringName(base_id)
	var suffix := 2
	while used_ids.has(string_id):
		string_id = StringName("%s_%d" % [base_id, suffix])
		suffix += 1
	used_ids[string_id] = true
	return string_id


func _save_registry(
	uid_to_id: Dictionary[StringName, StringName],
	id_to_uid: Dictionary[StringName, StringName],
) -> void:
	var registry := Registry.new()

	# Fill entries directly: Registry marks its maps read-only at runtime,
	# so RegistryIO.add_entry() cannot mutate them outside the editor.
	registry._version = Registry._REGISTRY_FORMAT_VERSION
	registry._scan_auto = true
	registry._scan_remove = true
	# Values must be typed arrays so YARD's editor loader can assign them
	# back to the typed RegistryScanRuleset fields without errors.
	var class_restrictions: Array[StringName] = [DEFINITION_CLASS]
	var scan_directories: Array[String] = [SCAN_DIR]
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
		&"slot": {},
		&"rarity": {},
		&"item_level": {},
		&"is_consumable": {},
	}
	registry.resource_path = REGISTRY_PATH
	# Also saves the registry once the index has been filled in.
	RegistryIOLoader.rebuild_property_index(registry)

	# Saving may drop or replace the header uid, which would break every
	# reference to the registry, so the previous identity is restored.
	var previous_uid := _header_uid(REGISTRY_PATH)
	var save_err := ResourceSaver.save(registry, REGISTRY_PATH, ResourceSaver.FLAG_CHANGE_PATH)
	if save_err != OK:
		push_error("Failed to save registry to %s (error %d)" % [REGISTRY_PATH, save_err])
		return
	# The registry file itself needs a uid:// so YARD's editor can resolve it.
	var registry_uid := _ensure_uid(REGISTRY_PATH)
	if previous_uid.begins_with("uid://") and registry_uid != previous_uid:
		_write_uid_to_header(REGISTRY_PATH, previous_uid)
		_register_uid(previous_uid, REGISTRY_PATH)
		registry_uid = previous_uid
	print("Registry saved: %s with %d entries (uid %s)." % [
		REGISTRY_PATH, registry.size(), registry_uid,
	])


## Reads the registry back from disk and checks that it is usable: every entry
## loads as an EquipmentDefinition and every indexed property resolved for
## every entry (a misspelled property name would silently index nothing).
func _verify_registry(expected_ids: Array) -> bool:
	var reloaded := ResourceLoader.load(
		REGISTRY_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	) as Registry
	if reloaded == null:
		push_error("Verification failed: %s could not be reloaded." % REGISTRY_PATH)
		return false

	var ok := true
	if reloaded.size() != expected_ids.size():
		push_error("Verification failed: expected %d entries, found %d." % [
			expected_ids.size(), reloaded.size(),
		])
		ok = false

	for string_id in expected_ids:
		var entry_id := StringName(string_id)
		if not reloaded.has_string_id(entry_id):
			push_error("Verification failed: missing entry '%s'." % string_id)
			ok = false
			continue
		var entry := reloaded.load_entry(entry_id)
		if not (entry is EquipmentDefinition):
			push_error("Verification failed: entry '%s' did not load as %s." % [
				string_id, DEFINITION_CLASS,
			])
			ok = false

	for property in INDEXED_PROPERTIES:
		if not reloaded.is_property_indexed(property):
			push_error("Verification failed: property '%s' is not indexed." % property)
			ok = false
			continue
		var covered := {}
		for value in reloaded._property_index[property]:
			for indexed_id in reloaded._property_index[property][value]:
				covered[indexed_id] = true
		if covered.size() != expected_ids.size():
			push_error("Verification failed: property '%s' indexed %d of %d entries." % [
				property, covered.size(), expected_ids.size(),
			])
			ok = false

	print("Verification %s: %d entries, indexed properties %s." % [
		"passed" if ok else "FAILED", reloaded.size(), str(INDEXED_PROPERTIES),
	])
	return ok
