## Frame-driven headless UI test base class for the UI Development Harness.
##
## Runs inside a bare `--headless --script` SceneTree (NOT the game, NOT MCP,
## NOT screenshots). Subclasses extend this file by path because a brand-new
## `class_name` is invisible to a cold headless run until the editor rescans
## the global script class cache:
##     extends "res://tools/ui_harness/ui_harness_suite.gd"
##
## Each `test_*` method is a coroutine driven by `run_all()`: the runner
## (`ui_harness_runner.gd`) awaits it, which pumps `process_frame` so deferred
## refreshes, layout, and `_process()` all behave like the real game.
extends RefCounted

var _tree: SceneTree
var _created: Array[Node] = []
var _failures: Array[String] = []
var _assertion_count: int = 0
var _skipped: bool = false
var _skip_reason: String = ""


func suite_name() -> String:
	return get_script().resource_path.get_file().trim_suffix(".gd")


func set_tree(tree: SceneTree) -> void:
	_tree = tree


# ---------------------------------------------------------------------------
# Lifecycle hooks (override in subclass)
# ---------------------------------------------------------------------------

func suite_setup() -> void:
	pass


func setup() -> void:
	pass


func teardown() -> void:
	pass


func suite_teardown() -> void:
	pass


# ---------------------------------------------------------------------------
# Driver (called by ui_harness_runner)
# ---------------------------------------------------------------------------

## Runs every `test_*` method and returns a per-suite summary Dictionary:
## { suite, tests: [{test, passed, skipped, skip_reason, failures, assertions}],
##   passed, failed, skipped, total, failures }
func run_all() -> Dictionary:
	var tests: Array[Dictionary] = []
	suite_setup()
	for method_name in _test_methods():
		_failures.clear()
		_assertion_count = 0
		_skipped = false
		_skip_reason = ""
		setup()
		# KEY: awaiting the test method pumps process_frame, so deferred
		# refreshes / layout / _process actually run (McpTestRunner's sync path
		# never does this, which is why UI suites cannot use it).
		await call(method_name)
		teardown()
		var passed: bool = _skipped or (_failures.is_empty() and _assertion_count > 0)
		var entry := {
			"test": method_name,
			"passed": passed,
			"skipped": _skipped,
			"skip_reason": _skip_reason,
			"failures": _failures.duplicate(),
			"assertions": _assertion_count,
		}
		if not _skipped and _assertion_count == 0:
			entry.passed = false
			entry.failures = ["test completed with 0 assertions"]
		tests.append(entry)
		_free_created()
	suite_teardown()
	return _summarize(tests)


# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

func expect(condition: bool, message: String = "") -> void:
	_assertion_count += 1
	if not condition:
		_failures.append(message if message != "" else "expect failed")


func expect_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	_assertion_count += 1
	if actual != expected:
		_failures.append(message if message != "" else "expected %s, got %s" % [str(expected), str(actual)])


func expect_ne(actual: Variant, not_expected: Variant, message: String = "") -> void:
	_assertion_count += 1
	if actual == not_expected:
		_failures.append(message if message != "" else "expected value != %s" % str(not_expected))


func expect_contains(haystack: Variant, needle: Variant, message: String = "") -> void:
	_assertion_count += 1
	if haystack is String:
		if haystack.find(str(needle)) == -1:
			_failures.append(message if message != "" else "'%s' not found in '%s'" % [str(needle), haystack])
	elif haystack is Array:
		if not haystack.has(needle):
			_failures.append(message if message != "" else "%s not found in array" % str(needle))
	else:
		_failures.append(message if message != "" else "expect_contains requires String or Array")


func skip(reason: String = "") -> void:
	_skipped = true
	_skip_reason = reason


# ---------------------------------------------------------------------------
# Tree / input helpers
# ---------------------------------------------------------------------------

## Register a node to be freed at the end of the current test.
func track_node(node: Node) -> void:
	if node != null:
		_created.append(node)


## Advance the SceneTree so deferred calls, layout, and _process() settle.
func flush_frames(count: int = 2) -> void:
	for _i in count:
		await _tree.process_frame


## Load + instantiate a scene and add it to the tree (root by default).
## Tracks the instance so it is freed after the test.
func mount_scene(path: String, parent: Node = null) -> Node:
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("ui_harness: cannot load %s" % path)
		return null
	var instance: Node = packed.instantiate()
	if parent == null:
		parent = _tree.root
	parent.add_child(instance)
	_created.append(instance)
	await flush_frames(2)
	return instance


## Panels rebuild their cells on every refresh — ALWAYS re-query per use.
func find_cell(grid: Node, index: int) -> Node:
	if grid == null:
		return null
	return grid.get_child(index)


func count_cells(grid: Node) -> int:
	return grid.get_child_count() if grid != null else 0


## Unit-style click: fire the cell's own `cell_pressed` signal, exactly as
## InventoryCell._gui_input does on a left click. Robust headless; primary path.
func click_cell(cell: Node) -> void:
	if cell != null and cell.has_signal("cell_pressed"):
		cell.emit_signal("cell_pressed", cell)


## Integration-style click: route a synthetic InputEventMouseButton through the
## root viewport's GUI pipeline (pure scene-tree math, headless-safe). Use when
## the test needs to prove input actually reaches a control's _gui_input.
func push_click(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var center: Vector2 = control.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	press.global_position = center
	_tree.root.push_input(press, false)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _test_methods() -> Array[String]:
	var names: Array[String] = []
	for method in get_method_list():
		var name: String = method.get("name", "")
		if name.begins_with("test_"):
			names.append(name)
	names.sort()
	return names


func _free_created() -> void:
	for node in _created:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_created.clear()


func _summarize(tests: Array[Dictionary]) -> Dictionary:
	var passed := 0
	var failed := 0
	var skipped := 0
	var failures: Array[Dictionary] = []
	for test in tests:
		if test.skipped:
			skipped += 1
		elif test.passed:
			passed += 1
		else:
			failed += 1
			failures.append({"test": test.test, "failures": test.failures})
	return {
		"suite": suite_name(),
		"tests": tests,
		"passed": passed,
		"failed": failed,
		"skipped": skipped,
		"total": tests.size(),
		"failures": failures,
	}
