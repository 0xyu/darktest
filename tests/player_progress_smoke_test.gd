extends SceneTree

## Phase 3 smoke test: PlayerProgress (map / stage player progress).
## Run headless: godot --headless --path . -s res://tests/player_progress_smoke_test.gd
##
## Phase 7.6 (Global Stage Range model): a stage number is GLOBAL and the current
## area is DERIVED from the position, so this object holds three fields with
## three different meanings and one writer each:
##   current_stage_number   where the player is now (can move backwards)
##   highest_stage_reached  the monotonic unlock ceiling
##   completed_stages       which stages are explicitly DONE (canonical ids)
## Verifies progress stays fully separated from static data and that no second
## stored position exists.

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
	_test_current_stage_is_derived()
	_test_cross_range_unlock_chain()
	_test_reach_keeps_the_chain_alive_past_the_authored_path()
	_test_no_stored_current_area()
	_test_unknown_area_never_unlocks()

	if _failures.is_empty():
		print("PlayerProgress smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_fresh_progress_has_first_stage_only() -> void:
	var progress := PlayerProgressScript.new()
	_expect(progress.is_stage_unlocked(1), "fresh progress: stage 1 should be unlocked")
	_expect(not progress.is_stage_unlocked(2), "fresh progress: stage 2 should be locked (stage 1 not completed)")
	_expect(not progress.is_stage_completed(1), "fresh progress: stage 1 should not be completed")
	_expect(not progress.is_stage_unlocked(0), "stage number 0 should never unlock")
	_expect(not progress.is_stage_unlocked(11), "fresh progress: stage 11 should stay locked (stage 10 not completed)")


func _test_completion_and_unlock_chain() -> void:
	var progress := PlayerProgressScript.new()
	for number in range(1, 6):
		_expect(progress.complete_stage(number), "stage %d should complete" % number)
	_expect(progress.is_stage_completed(5), "stage 5 should be completed after complete_stage")
	_expect(progress.is_stage_unlocked(6), "stage 6 should unlock once stage 5 is completed")
	_expect(not progress.is_stage_unlocked(10), "stage 10 should stay locked until stage 9 is completed")

	# Unlock reads the previous stage on the one global chain, then keeps chaining.
	var stepped := PlayerProgressScript.new()
	stepped.complete_stage(1)
	_expect(stepped.is_stage_unlocked(2), "completing stage 1 should unlock stage 2")
	_expect(not stepped.is_stage_unlocked(3), "stage 3 should still be locked before stage 2 is completed")
	# Completing 6 unlocks exactly 7 (its predecessor); it must NOT leap to 8.
	_expect(stepped.complete_stage(6), "stage 6 should complete even when 2-5 are skipped")
	_expect(stepped.is_stage_unlocked(7), "completing stage 6 unlocks its immediate successor, stage 7")
	_expect(not stepped.is_stage_unlocked(8), "completing stage 6 alone must not unlock stage 8 (needs 7 first)")


func _test_complete_stage_rejects_unknown_stages() -> void:
	var progress := PlayerProgressScript.new()
	_expect(not progress.complete_stage(0), "complete_stage should reject stage number 0")
	# Forest authors 1-10, so 11 is covered by no area at all: nothing can be
	# recorded for it, which is exactly what lets the endless tail past the last
	# authored area stay un-authored.
	_expect(not progress.complete_stage(11), "complete_stage should reject stage 11 (no area covers it)")
	_expect(not progress.complete_stage(-3), "complete_stage should reject a negative stage number")
	_expect(not progress.is_stage_completed(11), "rejected out-of-range completions must not be reported as completed")
	_expect(progress.get("completed_stages").is_empty(), "rejected completions must not record anything")


func _test_keys_are_canonical_id_strings() -> void:
	var progress := PlayerProgressScript.new()
	progress.complete_stage(6)
	var completed: Dictionary = progress.get("completed_stages")
	_expect(completed.has("forest_006"), "stage 6 should be keyed by its canonical id 'forest_006'")
	_expect(completed.size() == 1, "one completion should record exactly one entry")
	for key in completed:
		_expect(key is String, "completed_stages keys must be Strings, not Resources")


func _test_boss_boundary() -> void:
	# Forest 10 is the BOSS stage; the last stage completes and opens the next
	# GLOBAL stage number, which the next area (or the endless tail) takes over.
	var progress := PlayerProgressScript.new()
	for number in range(1, 11):
		_expect(progress.complete_stage(number), "stage %d (through boss) should complete" % number)
	_expect(progress.is_stage_completed(10), "boss stage 10 should be completed")
	_expect(progress.is_stage_unlocked(11), "clearing stage 10 opens stage 11 (one global chain, across areas)")
	_expect(not progress.is_stage_completed(11), "stage 11 completes nothing: no area authors it")
	_expect(progress.get("completed_stages").size() == 10, "clearing Forest should record exactly 10 canonical ids")


func _test_current_stage_is_derived() -> void:
	var progress := PlayerProgressScript.new()
	var initial: Dictionary = progress.get_current_stage()
	_expect(initial.get("stage_number") == 1, "fresh progress current stage number defaults to 1")
	_expect(String(initial.get("area_id", "")) == "forest", "stage 1 is inside Forest, so the area is derived as forest")
	_expect(String(initial.get("area_name", "")) == "Forest", "the derived area carries its authored display name")

	progress.current_stage_number = 6
	var current: Dictionary = progress.get_current_stage()
	_expect(current.get("stage_number") == 6, "get_current_stage should report the set stage number")
	_expect(String(current.get("area_id", "")) == "forest", "stage 6 still derives the forest area")
	_expect(String(progress.get_current_area_id()) == "forest", "get_current_area_id derives the area from the position")

	# Past the last authored area the derivation is simply empty: a legal state,
	# not an error, and the position itself keeps advancing.
	progress.current_stage_number = 57
	var past_end: Dictionary = progress.get_current_stage()
	_expect(String(progress.get_current_area_id()) == "", "stage 57 is past every authored area, so the area is empty")
	_expect(String(past_end.get("area_id", "")) == "", "get_current_stage reports the same derived (empty) area")
	_expect(past_end.get("stage_number") == 57, "the position is still reported past the authored path")


func _test_cross_range_unlock_chain() -> void:
	# The unlock chain is global: it does not restart or stop at an area boundary.
	var progress := PlayerProgressScript.new()
	progress.mark_reached(10)
	_expect(progress.is_stage_unlocked(10), "an area's last stage is unlocked once the player reached it")
	progress.complete_stage(10)
	_expect(progress.is_stage_unlocked(11), "clearing stage 10 unlocks stage 11 across the area boundary")
	_expect(not progress.is_stage_unlocked(12), "clearing 10 alone must not unlock 12")


func _test_reach_keeps_the_chain_alive_past_the_authored_path() -> void:
	# Past the last authored area nothing can be recorded as completed, so the
	# monotonic reach is the ONLY thing that keeps the gate open. Without it the
	# progression would deadlock at the end of the authored content.
	var progress := PlayerProgressScript.new()
	progress.mark_reached(57)
	_expect(progress.is_stage_unlocked(57), "a reached stage beyond every authored area stays unlocked")
	_expect(progress.is_stage_unlocked(20), "everything the player already passed through stays unlocked")
	_expect(not progress.is_stage_unlocked(58), "the stage just past the reached position stays locked")
	_expect(progress.get("completed_stages").is_empty(), "reaching writes no completions")
	_expect(int(progress.get("highest_stage_reached")) == 57, "the reach ceiling is recorded")

	# A defeat moves the position back but must NOT lower the ceiling.
	progress.current_stage_number = 56
	progress.mark_reached(56)
	_expect(int(progress.get("highest_stage_reached")) == 57, "mark_reached is monotonic: a rollback keeps the ceiling")


func _test_no_stored_current_area() -> void:
	# Guard against the regression this model removed: a second, STORED copy of
	# the position (which used to drift away from the battle's stage number).
	var progress := PlayerProgressScript.new()
	var properties: Array = []
	for property in progress.get_property_list():
		properties.append(String(property.get("name", "")))
	_expect(not properties.has("current_area_id"), "PlayerProgress must not store a current_area_id (it is derived)")
	_expect(properties.has("current_stage_number"), "PlayerProgress stores exactly one position")
	_expect(properties.has("highest_stage_reached"), "PlayerProgress stores the monotonic unlock ceiling")


func _test_unknown_area_never_unlocks() -> void:
	# StageDatabase is the source of truth for which numbers any area authors:
	# a number no area covers has no stage and can never be completed.
	var progress := PlayerProgressScript.new()
	_expect(StageDatabaseScript.lookup(1) != null, "stage 1 is authored by Forest")
	_expect(not progress.is_stage_completed(1), "an authored but unplayed stage is not completed")
	_expect(not progress.complete_stage(999), "complete_stage should reject a stage number no area covers")
	_expect(not progress.is_stage_completed(999), "a number no area covers is never completed")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
