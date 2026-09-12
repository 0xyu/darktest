extends SceneTree

## Smoke test for the item registry built by tools/generate_item_registry.gd.
## Run headless: godot --headless --path . -s res://tests/item_registry_smoke_test.gd

const ITEM_DIR := "res://resources/items"
const REGISTRY_PATH := "res://resources/items/item_registry.tres"
const INDEXED_PROPERTIES: Array[StringName] = [
	&"slot",
	&"rarity",
	&"item_level",
	&"is_consumable",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := ResourceLoader.load(REGISTRY_PATH) as Registry
	_expect(registry != null, "%s should load as a Registry" % REGISTRY_PATH)
	if registry == null:
		_finish()
		return

	var registry_uid := _header_uid(REGISTRY_PATH)
	_expect(registry_uid.begins_with("uid://"), "%s should declare its own uid" % REGISTRY_PATH)
	_expect(registry.is_property_indexed(&"slot"), "slot should be an indexed property")

	# The registry must stay in sync with the directory it indexes.
	var definition_paths := _collect_definition_paths()
	_expect(not definition_paths.is_empty(), "no EquipmentDefinition found under %s" % ITEM_DIR)
	_expect(
		registry.size() == definition_paths.size(),
		"registry should hold %d entries, holds %d (re-run tools/generate_item_registry.gd)" % [
			definition_paths.size(), registry.size(),
		],
	)

	var slot_counts := {}
	for path in definition_paths:
		var string_id := StringName(path.get_file().get_basename())
		_expect(registry.has_string_id(string_id), "'%s' should be registered" % string_id)

		# A definition without a uid in its header cannot be resolved by a
		# registry that stores uids, so this is the load-bearing check.
		var header_uid := _header_uid(path)
		_expect(not header_uid.is_empty(), "%s should declare a uid" % path)
		_expect(
			String(registry.get_uid(string_id)) == header_uid,
			"'%s' should be registered under its own uid, got '%s'" % [string_id, registry.get_uid(string_id)],
		)

		# Resolving a uid to a resource is what consumers actually do.
		var definition := registry.load_entry(string_id) as EquipmentDefinition
		_expect(definition != null, "'%s' should load through its uid" % string_id)
		if definition == null:
			continue
		_expect(definition.resource_path == path, "'%s' should resolve to %s" % [string_id, path])
		_expect(
			registry.get_string_id(registry.get_uid(string_id)) == string_id,
			"uid <-> string id mapping should round-trip for '%s'" % string_id,
		)
		# §12: an authored affix outside the catalogue would be rolled, displayed and
		# score-counted while never reaching combat — the defect this check exists to make
		# impossible in shipped content.
		for affix in definition.base_affixes:
			if affix == null:
				continue
			_expect(
				EquipmentAffix.is_known_stat(affix.stat_id),
				"%s configures affix '%s', which is not in the affix catalogue" % [path, affix.stat_id],
			)
			_expect(
				not affix.get_label().is_empty(),
				"%s configures affix '%s' with no display label" % [path, affix.stat_id],
			)
		if not definition.unique_effect_id.is_empty():
			_expect(
				EquipmentEffect.create_for_id(definition.unique_effect_id) != null,
				"%s configures unique_effect_id '%s', which has no implementation" % [
					path, definition.unique_effect_id,
				],
			)
		slot_counts[definition.slot] = int(slot_counts.get(definition.slot, 0)) + 1

	# Every indexed property must cover every entry, otherwise filter() silently
	# misses resources and a misspelled property name goes unnoticed.
	for property in INDEXED_PROPERTIES:
		_expect(registry.is_property_indexed(property), "property '%s' should be indexed" % property)
		_expect(
			_indexed_entry_count(registry, property) == registry.size(),
			"property '%s' should index every entry" % property,
		)

	# Queries consumers will use, cross-checked against the definitions on disk.
	for slot in slot_counts:
		var matches := registry.filter_by_value(&"slot", slot)
		_expect(
			matches.size() == int(slot_counts[slot]),
			"slot %d should match %d entries, matched %d" % [slot, slot_counts[slot], matches.size()],
		)
		for matched_id in matches:
			var matched := registry.load_entry(StringName(matched_id)) as EquipmentDefinition
			_expect(
				matched != null and matched.slot == slot,
				"slot %d filter returned a non-matching entry '%s'" % [slot, matched_id],
			)

	for consumable_id in registry.filter_by_value(&"is_consumable", true):
		var consumable := registry.load_entry(StringName(consumable_id)) as EquipmentDefinition
		_expect(
			consumable != null and consumable.is_consumable,
			"is_consumable filter returned a non-consumable '%s'" % consumable_id,
		)

	_finish()


func _collect_definition_paths() -> Array[String]:
	var found: Array[String] = []
	_walk_dir(ITEM_DIR, found)
	found.sort()
	return found


func _walk_dir(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full_path := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_walk_dir(full_path, out)
		elif entry.ends_with(".tres") and full_path != REGISTRY_PATH:
			if ResourceLoader.load(full_path) is EquipmentDefinition:
				out.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


## Reads the uid out of a `.tres` header. On Godot 4.7.2 ResourceUID.path_to_uid()
## only answers for resources already in the uid cache, so the header is read
## directly instead.
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


func _indexed_entry_count(registry: Registry, property: StringName) -> int:
	var covered := {}
	for value in registry._property_index[property]:
		for string_id in registry._property_index[property][value]:
			covered[string_id] = true
	return covered.size()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("item_registry_smoke_test: PASS")
	else:
		print("item_registry_smoke_test: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
	quit(0 if _failures.is_empty() else 1)
