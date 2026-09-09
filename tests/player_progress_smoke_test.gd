extends SceneTree

## Phase 3 smoke test: PlayerProgress (map / stage player progress).
## Run headless: godot --headless --path . -s res://tests/player_progress_smoke_test.gd
##
## Verifies progress is fully separated from static data: completion / unlock /
## current position live only in PlayerProgress, keyed by canonical StageDatabase
## stage ids (forest_001 ...), bounded by each area's stage_count.

const PlayerProgressScript = preload("res://scripts/progress/player_progress.gd")
const StageDatabaseScript = preload("res://scripts/data/stage_database.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fresh_progress_has_first_stage_only()
	_test_completion_and_unlock_chain()
	_test_complete_stage_rejects_unknown_stages()
	_test_keys_are_canonical_id_strings()
	_test_boss_boundary()
	_test_current_stage()
	_test_unknown_area_never_unlocks()

	if _failures.is_empty():
		print("PlayerProgress smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_fresh_progress_has_first_stage_only() -> void:
	var progress := PlayerProgressScript.new()
	_expect(progress.is_stage_unlocked(&"forest", 1), "fresh progress: forest stage 1 should be unlocked")
	_expect(not progress.is_stage_unlocked(&"forest", 2), "fresh progress: forest stage 2 should be locked (01 not completed)")
	_expect(not progress.is_stage_completed(&"forest", 1), "fresh progress: forest stage 1 should not be completed")
	_expect(not progress.is_stage_unlocked(&"forest", 0), "stage number 0 should never unlock")
	_expect(not progress.is_stage_unlocked(&"forest", 11), "forest stage 11 should never unlock (past stage_count 10)")


func _test_completion_and_unlock_chain() -> void:
	var progress := PlayerProgressScript.new()
	for number in range(1, 6):
		_expect(progress.complete_stage(&"forest", number), "forest stage %d should complete" % number)
	_expect(progress.is_stage_completed(&"forest", 5), "forest stage 5 should be completed after complete_stage")
	_expect(progress.is_stage_unlocked(&"forest", 6), "forest stage 6 should unlock once stage 5 is completed")
	_expect(not progress.is_stage_unlocked(&"forest", 10), "forest stage 10 should stay locked until stage 9 is completed")

	# Unlock reads the previous stage on the SAME area path, then keeps chaining.
	var stepped := PlayerProgressScript.new()
	stepped.complete_stage(&"forest", 1)
	_expect(stepped.is_stage_unlocked(&"forest", 2), "completing stage 1 should unlock stage 2")
	_expect(not stepped.is_stage_unlocked(&"forest", 3), "stage 3 should still be locked before stage 2 is completed")
	# Completing 6 unlocks exactly 7 (its predecessor); it must NOT leap to 8.
	_expect(stepped.complete_stage(&"forest", 6), "forest stage 6 should complete even when 2-5 are skipped")
	_expect(stepped.is_stage_unlocked(&"forest", 7), "completing stage 6 unlocks its immediate successor, stage 7")
	_expect(not stepped.is_stage_unlocked(&"forest", 8), "completing stage 6 alone must not unlock stage 8 (needs 7 first)")


func _test_complete_stage_rejects_unknown_stages() -> void:
	var progress := PlayerProgressScript.new()
	_expect(not progress.complete_stage(&"forest", 0), "complete_stage should reject stage number 0")
	_expect(not progress.complete_stage(&"forest", 11), "complete_stage should reject forest stage 11 (out of range)")
	_expect(not progress.complete_stage(&"forest", -3), "complete_stage should reject a negative stage number")
	_expect(not progress.complete_stage(&"swamp", 1), "complete_stage should reject an un-authored area (swamp)")
	_expect(not progress.is_stage_completed(&"forest", 11), "rejected out-of-range completions must not be reported as completed")
	_expect(progress.get("completed_stages").is_empty(), "rejected completions must not record anything")


func _test_keys_are_canonical_id_strings() -> void:
	var progress := PlayerProgressScript.new()
	progress.complete_stage(&"forest", 6)
	var completed: Dictionary = progress.get("completed_stages")
	_expect(completed.has("forest_006"), "stage 6 should be keyed by its canonical id 'forest_006'")
	_expect(completed.size() == 1, "one completion should record exactly one entry")
	for key in completed:
		_expect(key is String, "completed_stages keys must be Strings, not Resources")


func _test_boss_boundary() -> void:
	# Forest 10 is the BOSS stage; the last stage completes but nothing beyond it.
	var progress := PlayerProgressScript.new()
	for number in range(1, 11):
		_expect(progress.complete_stage(&"forest", number), "forest stage %d (through boss) should complete" % number)
	_expect(progress.is_stage_completed(&"forest", 10), "forest boss stage 10 should be completed")
	_expect(not progress.is_stage_unlocked(&"forest", 11), "there is no stage 11, so nothing unlocks past the boss")
	_expect(progress.get("completed_stages").size() == 10, "clearing Forest should record exactly 10 canonical ids")


func _test_current_stage() -> void:
	var progress := PlayerProgressScript.new()
	var initial: Dictionary = progress.get_current_stage()
	_expect(String(initial.get("area_id", "")) == "", "fresh progress has no current area")
	_expect(initial.get("stage_number") == 1, "fresh progress current stage number defaults to 1")

	progress.current_area_id = &"forest"
	progress.current_stage_number = 6
	var current: Dictionary = progress.get_current_stage()
	_expect(String(current.get("area_id", "")) == "forest", "get_current_stage should report the set area")
	_expect(current.get("stage_number") == 6, "get_current_stage should report the set stage number")


func _test_unknown_area_never_unlocks() -> void:
	var progress := PlayerProgressScript.new()
	_expect(not progress.is_stage_unlocked(&"swamp", 1), "un-authored area stage 1 should not unlock")
	_expect(not progress.is_stage_completed(&"swamp", 1), "un-authored area stage 1 should not be completed")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
