## Headless UI Development Harness entry point.
##
## Runs every suite under res://tools/ui_harness/suites/ in a bare SceneTree —
## no game launch, no MCP, no screenshots. See docs/ui-harness.md.
##
## Usage:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <project> \
##       --script res://tools/ui_harness/ui_harness_runner.gd \
##       [++ --suite <name>] [--quiet] [--list]
##
##   --suite <name>  run one suite only (name = suite file name without .gd)
##   --quiet         print only SKIP / FAIL lines plus the one-line summary
##   --list          print the available suite names and exit
##
## Exit code: 0 = all suites green, 1 = any failure or unloadable suite.
extends SceneTree

const SUITES_DIR := "res://tools/ui_harness/suites"
const BASE_SUITE_SCRIPT := preload("res://tools/ui_harness/ui_harness_suite.gd")

var _all_results: Array[Dictionary] = []
var _load_failures: int = 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	var args := OS.get_cmdline_user_args()
	var filter := _parse_filter(args)
	var quiet := args.has("--quiet")
	root.size = Vector2i(720, 1280)
	if args.has("--list"):
		for path in _discover_suites():
			print(path.get_file().trim_suffix(".gd"))
		quit(0)
		return
	for path in _discover_suites():
		var suite = _instantiate(path)
		if suite == null:
			_load_failures += 1
			continue
		if not filter.is_empty() and suite.suite_name() != filter:
			continue
		suite.set_tree(self)
		var result: Dictionary = await suite.run_all()
		_all_results.append(result)
		_print_suite(result, quiet)
	var summary := _aggregate(_all_results)
	_print_summary(summary)
	quit(0 if summary.failed == 0 and _load_failures == 0 else 1)


func _discover_suites() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(SUITES_DIR)
	if dir == null:
		push_error("ui_harness: cannot open %s" % SUITES_DIR)
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".gd"):
			paths.append(SUITES_DIR.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


## Instantiate a suite only if its script chain extends the base suite.
## Verified by walking get_base_script() so there is no dependency on the
## global script class cache (a cold headless run has not rebuilt it).
func _instantiate(path: String) -> Object:
	var script := load(path) as Script
	if script == null:
		push_error("ui_harness: cannot load script %s" % path)
		return null
	var probe: Script = script
	while probe != null:
		if probe == BASE_SUITE_SCRIPT:
			return script.new()
		probe = probe.get_base_script()
	push_error("ui_harness: %s does not extend ui_harness_suite.gd" % path)
	return null


func _parse_filter(args: PackedStringArray) -> String:
	for i in range(args.size()):
		if args[i] == "--suite" and i + 1 < args.size():
			return args[i + 1]
	return ""


func _print_suite(result: Dictionary, quiet: bool = false) -> void:
	if not quiet:
		print("[ui_harness] suite %s" % result.suite)
	var prefix := ("%s :: " % result.suite) if quiet else ""
	for test in result.tests:
		if test.skipped:
			print("  [SKIP] %s%s (%s)" % [prefix, test.test, test.skip_reason])
		elif test.passed:
			if not quiet:
				print("  [PASS] %s (%d assertions)" % [test.test, test.assertions])
		else:
			print("  [FAIL] %s%s" % [prefix, test.test])
			for failure in test.failures:
				print("      - %s" % failure)


func _aggregate(results: Array[Dictionary]) -> Dictionary:
	var passed := 0
	var failed := 0
	var skipped := 0
	var failures: Array[Dictionary] = []
	for result in results:
		passed += result.passed
		failed += result.failed
		skipped += result.skipped
		failures.append_array(result.failures)
	return {
		"passed": passed,
		"failed": failed,
		"skipped": skipped,
		"total": passed + failed + skipped,
		"failures": failures,
	}


func _print_summary(summary: Dictionary) -> void:
	print("[ui_harness] %d tests, %d passed, %d failed, %d skipped" % [
		summary.total, summary.passed, summary.failed, summary.skipped,
	])
	for failure in summary.failures:
		push_error("[ui_harness] %s :: %s" % [failure.test, "; ".join(failure.failures)])
