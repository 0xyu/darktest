extends SceneTree

## Authored stage CONTENT smoke test: StageContent data + AuthoredContentState.
## Run headless: godot --headless --path . -s res://tests/stage_content_smoke_test.gd
##
## Verifies the authored-stage model this feature establishes:
##   * a stage's content is layered on top of its gameplay, so content never
##     changes the stage_type / route
##   * one_shot separates "consumed once, then a plain normal stage" from
##     "recreated on every stage start"
##   * consumed state is recorded by identifier in its OWN class, independent of
##     PlayerProgress

const StageContentScript = preload("res://scripts/data/stage_content.gd")
const AuthoredContentStateScript = preload("res://scripts/progress/authored_content_state.gd")
const StageDatabaseScript = preload("res://scripts/data/stage_database.gd")
const StageTypeScript = preload("res://scripts/data/stage_type.gd")
const FOREST_PATH := "res://resources/stage_databases/forest.tres"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_forest_authored_content()
	_test_content_does_not_change_the_route()
	_test_un_authored_stages_have_no_content()
	_test_content_validation()
	_test_consumed_state()
	_test_kind_helpers()

	if _failures.is_empty():
		print("StageContent / AuthoredContentState smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_forest_authored_content() -> void:
	var stage: Resource = StageDatabaseScript.lookup(6)
	_expect(stage != null, "forest 06 should be authored")
	if stage == null:
		return

	var entries: Array = stage.get("content")
	_expect(entries.size() == 2, "forest 06 should author 2 content entries (got %d)" % entries.size())

	var chest: Resource = _find_content(entries, &"cache")
	_expect(chest != null, "forest 06 should author a 'cache' chest")
	if chest != null:
		_expect(chest.get("kind") == StageContentScript.Kind.CHEST, "the cache should be a CHEST")
		_expect(bool(chest.get("one_shot")), "the cache should be one-shot (opened once, then gone)")
		_expect(int(chest.get("gold")) > 0, "the cache should grant gold")
		_expect(bool(chest.call("is_valid")), "the cache entry should be valid")

	var spring: Resource = _find_content(entries, &"spring")
	_expect(spring != null, "forest 06 should author a 'spring' healing pool")
	if spring != null:
		_expect(spring.get("kind") == StageContentScript.Kind.HEALING_POOL, "the spring should be a HEALING_POOL")
		_expect(not bool(spring.get("one_shot")), "the spring should be repeatable (it refills on later visits)")
		_expect(int(spring.call("get_heal_amount", 100)) > 0, "the spring should restore HP")
		_expect(bool(spring.call("is_valid")), "the spring entry should be valid")


func _test_content_does_not_change_the_route() -> void:
	# Content is layered on top of the gameplay: an authored stage with content
	# keeps the same stage_type, so adding content can never re-route a stage.
	var stage: Resource = StageDatabaseScript.lookup(6)
	_expect(stage != null, "forest 06 should be authored")
	if stage == null:
		return
	_expect(stage.get("stage_type") == StageTypeScript.COMBAT, "forest 06 should still be a COMBAT stage despite its content")
	_expect(not stage.get("content").is_empty(), "forest 06 should carry content (so this is not a vacuous check)")


func _test_un_authored_stages_have_no_content() -> void:
	# The endless default: a stage nobody authored carries no content at all, which
	# is exactly what makes it a plain normal stage.
	for number in [1, 2, 3, 5, 7, 9]:
		var stage: Resource = StageDatabaseScript.lookup(number)
		_expect(stage != null, "forest %d should exist" % number)
		if stage != null:
			_expect(stage.get("content").is_empty(), "un-authored forest %d should carry no content" % number)


func _test_content_validation() -> void:
	var empty_id: Resource = StageContentScript.new()
	empty_id.set("kind", StageContentScript.Kind.CHEST)
	_expect(not bool(empty_id.call("is_valid")), "content with an empty id should be invalid")

	var bad_kind: Resource = StageContentScript.new()
	bad_kind.set("id", &"broken")
	bad_kind.set("kind", 999)
	_expect(not bool(bad_kind.call("is_valid")), "content with an unknown kind should be invalid")

	var useless_pool: Resource = StageContentScript.new()
	useless_pool.set("id", &"dry")
	useless_pool.set("kind", StageContentScript.Kind.HEALING_POOL)
	_expect(not bool(useless_pool.call("is_valid")), "a healing pool that restores nothing should be invalid")

	# A stage with duplicate content ids must be rejected.
	var stage_script = load("res://scripts/data/stage_data.gd")
	var stage: Resource = stage_script.new()
	stage.set("id", &"forest_01")
	stage.set("stage_number", 1)
	var first: Resource = StageContentScript.new()
	first.set("id", &"dup")
	first.set("kind", StageContentScript.Kind.CHEST)
	var second: Resource = StageContentScript.new()
	second.set("id", &"dup")
	second.set("kind", StageContentScript.Kind.CHEST)
	stage.get("content").append(first)
	stage.get("content").append(second)
	_expect(not bool(stage.call("is_valid")), "a stage with duplicate content ids should be invalid")
	_expect(_contains(stage.call("get_validation_errors"), "duplicate content id"), "duplicate content ids should be reported")

	# A single valid entry keeps the stage valid.
	stage.get("content").clear()
	stage.get("content").append(first)
	_expect(bool(stage.call("is_valid")), "a stage with one valid content entry should be valid")


func _test_consumed_state() -> void:
	var state: Resource = AuthoredContentStateScript.new()
	_expect(state.call("get_consumed_count") == 0, "fresh content state should be empty")

	_expect(not bool(state.call("is_consumed", "forest_006", &"cache")), "content should start unconsumed")
	_expect(bool(state.call("consume", "forest_006", &"cache")), "consuming should succeed")
	_expect(bool(state.call("is_consumed", "forest_006", &"cache")), "consumed content should report consumed")
	_expect(state.call("get_consumed_count") == 1, "exactly one content key should be recorded")

	# Idempotent: consuming twice must not add a second key.
	state.call("consume", "forest_006", &"cache")
	_expect(state.call("get_consumed_count") == 1, "consuming twice should stay idempotent")

	# Keys are per (stage, content): the same content id on another stage is
	# independent, and the same stage's other content is independent.
	_expect(not bool(state.call("is_consumed", "forest_007", &"cache")), "the same content id on another stage stays unconsumed")
	_expect(not bool(state.call("is_consumed", "forest_006", &"spring")), "another content entry on the same stage stays unconsumed")

	state.call("consume", "forest_006", &"spring")
	_expect(state.call("get_consumed_count_for_stage", "forest_006") == 2, "both forest 06 entries should be counted for that stage")
	_expect(state.call("get_consumed_count_for_stage", "forest_007") == 0, "another stage should have no consumed entries")

	# Identifier-only storage, so it serializes without referencing Resources.
	var key: String = AuthoredContentStateScript.make_key("forest_006", &"cache")
	_expect(key == "forest_006:cache", "the consumption key should be identifier-only (got '%s')" % key)

	# Nonsense input must never record anything.
	state.call("consume", "", &"cache")
	state.call("consume", "forest_006", &"")
	_expect(state.call("get_consumed_count") == 2, "consuming with an empty stage or content id should record nothing")

	state.call("forget_all")
	_expect(state.call("get_consumed_count") == 0, "forget_all should clear the state")


func _test_kind_helpers() -> void:
	_expect(StageContentScript.is_valid_kind(StageContentScript.Kind.CHEST), "CHEST should be a valid kind")
	_expect(StageContentScript.is_valid_kind(StageContentScript.Kind.HEALING_POOL), "HEALING_POOL should be a valid kind")
	_expect(not StageContentScript.is_valid_kind(999), "unknown content kinds should be invalid")
	_expect(not StageContentScript.get_kind_display_name(StageContentScript.Kind.CHEST).is_empty(), "CHEST should have a display name")


func _find_content(entries: Array, content_id: StringName) -> Resource:
	for entry in entries:
		if entry != null and entry.get("id") == content_id:
			return entry
	return null


func _contains(messages: PackedStringArray, needle: String) -> bool:
	for message in messages:
		if String(message).find(needle) != -1:
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
