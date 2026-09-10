class_name StageFlow
extends RefCounted

## Owns the authored-stage FLOW POLICY for the running scene: which stage the
## player is on, what completing a stage means, what the authored path offers
## next, which stages the linear gate lets the player enter, and where a town
## visit returns to.
##
## Why this class exists
## --------------------
## Phase 7 implemented that policy as private methods of the combat scene
## (grid_combat), which made the scene host and the flow rules the same object:
## completion recording, unlock text, return routing and the entry session all
## lived next to battle hosting. StageFlow is that policy extracted, so the
## combat scene goes back to being only a HOST — it starts battles, switches
## views, forwards engine / HUD signals — and owns no flow rules. The rules are
## also testable without mounting the combat scene and driving a real battle.
##
## One global stage counter, one writer (Phase 7.6)
## ------------------------------------------------
## Stage numbers are global and an area is a RANGE on that counter, so the flow
## passes stage numbers around and DERIVES the area through
## StageDatabase.database_for_stage / area_for_stage. Nothing here stores an area
## of its own.
##
## The position has exactly ONE writer: on_stage_started(). Every path that moves
## the battle to a different stage — boot, a world-map / DEV entry, an advance
## (AUTO and manual share the single advance seam), a defeat fallback and a
## FARMING re-spawn — reaches StageManager.initialize_stage(), which emits
## stage_started, which the host forwards here. A visit-type stage starts no
## battle, so the flow calls the same writer from its own entry bookkeeping. That
## is why the map's HERE marker, the stage bar and PlayerProgress can no longer
## disagree about which stage the player is on.
##
## Rules that live here (and nowhere else)
## ---------------------------------------
##   * position bookkeeping: the stage a battle (or visit) started on becomes the
##     current stage number, and raises the monotonic highest-stage-reached
##   * battle completion: clearing a stage covered by an authored area records
##     that stage under its canonical id and reports what is next; a clear past
##     the last authored area records nothing (there is nothing authored to
##     record) while the position still advances
##   * next-stage text: read from StageDatabase through the router, never from a
##     hard-coded stage number or type table
##   * the linear unlock gate handed to the world map
##   * where a town close goes (back to the map it was opened from, or back to
##     the combat view)
##
## Automation never changes a RESULT
## ---------------------------------
## Whether AUTO or FARMING is on, clearing an authored battle records the SAME
## completion and reports the SAME authored "what's next". AUTO and FARMING are
## not consulted here at all: automation decides only WHEN the battle advances
## (see grid_combat's single advance seam), and FARMING decides that the battle
## stays on the same stage. Neither is a flow rule.
##
## Advancing is ALWAYS "the battle moves to stage N+1"
## -----------------------------------------------
## The game is primarily endless: a stage that is not authored behaves as a
## plain endless stage, and a cleared stage continues to the next battle. The
## world map is a status view / shortcut that can be opened at any time, not a
## hub the player is forced back to after every clear. That is why this class
## has no "return to map after clearing" rule — and why an area boundary is not a
## wall: clearing 10 simply advances to 11, which the next area covers.
##
## Static data is never written
## ---------------------------
## StageDatabase / StageData are read-only here; only PlayerProgress is mutated.
##
## Persisting is announced, not performed (Phase 8)
## ------------------------------------------------
## This class does not know a save exists. It announces every real change of the
## player's progress through progress_changed, and the save subscribes, so the
## autosave triggers and the single position writer can never disagree about what
## changed.

const StageRouterScript := preload("res://scripts/systems/stage_router.gd")
const StageDatabaseScript := preload("res://scripts/data/stage_database.gd")
const StageTypeScript := preload("res://scripts/data/stage_type.gd")
const PlayerProgressScript := preload("res://scripts/progress/player_progress.gd")

## Raised when an authored stage entry has been resolved and the host should open
## the matching gameplay. `route` is the StageRouter route dictionary, enriched
## with the flow fields the host needs:
##   from_map  — the entry was clicked on the world map
##   next_text — authored "what's next", already resolved for a completed visit
##   visit_completed — a visit-type stage was recorded as cleared on entry
signal gameplay_requested(route: Dictionary)

## Raised whenever this flow actually CHANGES the player's progress (the position,
## the unlock ceiling, or a recorded completion). It is the autosave trigger:
## the save (Phase 8) subscribes here, so every path that moves the player or
## records a clear persists without a save call in any of those paths.
##
## Real changes only: a re-clear of an already-recorded stage, or a FARMING
## re-spawn of the stage the player is already on, changes nothing and therefore
## announces nothing — a grinding session must not rewrite the save file every few
## seconds.
signal progress_changed()

## Player map / stage progression. Injected so a later save system can restore it
## instead of the flow building its own (Phase 8 decides the mount point).
var _progress: PlayerProgress
var _router: StageRouter
## True while the town view currently open was entered from the world map, so
## closing it returns to the refreshed map instead of the combat view.
var _town_open_from_map: bool = false


func _init(progress: PlayerProgress = null) -> void:
	_progress = progress if progress != null else PlayerProgressScript.new()
	_router = StageRouterScript.new()


func get_progress() -> PlayerProgress:
	return _progress


func get_router() -> StageRouter:
	return _router


## Area the player is currently on, DERIVED from the position. Empty only past
## the last authored area (the endless tail), which is a legal state.
func get_current_area_id() -> StringName:
	return _progress.get_current_area_id() if _progress != null else &""


## The stage number the player currently stands on.
func get_current_stage_number() -> int:
	return _progress.current_stage_number if _progress != null else 1


## THE single position writer. Called whenever the game moves onto a stage:
## every battle start (the host forwards StageManager.stage_started) and the
## entry bookkeeping of a visit-type stage, which starts no battle.
##
## Records the position and raises the monotonic highest-stage-reached. A defeat
## fallback therefore moves the position back while the unlock ceiling stays put.
##
## Announces progress_changed when either number actually moved, which is the
## autosave trigger for "the player is somewhere else now".
func on_stage_started(stage_number: int) -> void:
	if _progress == null:
		return
	var previous_position: int = _progress.current_stage_number
	var previous_ceiling: int = _progress.highest_stage_reached
	_progress.current_stage_number = maxi(stage_number, 1)
	_progress.mark_reached(stage_number)
	if _progress.current_stage_number != previous_position \
		or _progress.highest_stage_reached != previous_ceiling:
		progress_changed.emit()


## Requests entry to an authored stage by its GLOBAL stage number. Returns true
## when the stage is authored and its gameplay has been requested through
## gameplay_requested. Returns false for un-authored / out-of-range numbers — the
## caller shows the reason.
func request_enter(stage_number: int, from_map: bool = false) -> bool:
	if _router == null or _progress == null:
		return false
	var route: Dictionary = _router.route(stage_number)
	if not bool(route.get("ok", false)):
		return false
	var destination: int = int(route.get("destination", StageRouterScript.Destination.NONE))
	var enriched: Dictionary = route.duplicate()
	enriched["from_map"] = from_map
	_apply_entry(enriched, destination)
	return true


## Reason an entry was rejected, for the host's status line.
func get_entry_failure_reason(stage_number: int) -> String:
	if _router == null:
		return "Cannot enter that stage."
	var route: Dictionary = _router.route(stage_number)
	return str(route.get("reason", "Cannot enter that stage."))


## True when the linear progression lets the player enter this GLOBAL stage. Kept
## here so the world map's lock gate and the flow share one rule; the rule itself
## belongs to PlayerProgress.
func is_stage_unlocked(stage_number: int) -> bool:
	if _progress == null:
		return false
	return _progress.is_stage_unlocked(stage_number)


## True when the stage AFTER `stage_number` has already been cleared, so the
## player is free to come back through it at any time.
##
## This is one progress question and nothing more: it says "the stage the player
## stands on is a REPLAY of content that is already done". The battle host's
## advance gate is what turns it into "the Next Stage Point may be used with
## enemies still standing" (see grid_combat.can_leave_stage_uncleared), so no
## gate lives here.
##
## Stage numbers are one global counter, so this asks about `stage_number + 1`
## directly. A number no authored area covers (the endless tail) can never be
## completed, so the endless chain keeps the classic clear-first rule.
func is_next_stage_cleared(stage_number: int) -> bool:
	if _progress == null:
		return false
	return _progress.is_stage_completed(stage_number + 1)


## Records the clear of stage `cleared_stage_number` and returns the authored
## "what's next" text.
##
## Returns "" when there is nothing authored to record — the stage number is past
## every authored area (the player ground past the end of the authored path).
## That is not a failure: the position already advanced through
## on_stage_started(), and the host falls back to the endless text.
##
## Deliberately independent of AUTO / FARMING: the result is identical either way.
func on_battle_cleared(cleared_stage_number: int) -> String:
	if _progress == null:
		return ""
	var already_recorded: bool = _progress.is_stage_completed(cleared_stage_number)
	if not _progress.complete_stage(cleared_stage_number):
		return ""
	if not already_recorded:
		# Only a NEW completion announces: repeating a clear of the same stage
		# (FARMING) records nothing new, so there is nothing to persist.
		progress_changed.emit()
	return next_stage_text(cleared_stage_number)


## Authored "what's next" after `stage_number` clears:
##   * the next stage is covered by an area  → "STAGE 12 (COMBAT) UNLOCKED",
##     its type read through the router from StageDatabase, never a hard-coded
##     number
##   * the area ends here and another area follows → "AREA FOREST COMPLETE
##     (10/10) — NEXT: FOREST 2"
##   * the area ends here and nothing follows → "AREA FOREST COMPLETE (10/10)"
##   * no area covered `stage_number` at all → "" (the host's endless text)
func next_stage_text(stage_number: int) -> String:
	if _router == null:
		return ""
	var next_route: Dictionary = _router.route(stage_number + 1)
	if bool(next_route.get("ok", false)):
		var next_stage: int = int(next_route.get("stage_number", 0))
		var next_type: int = int(next_route.get("stage_type", StageTypeScript.COMBAT))
		return "STAGE %02d (%s) UNLOCKED" % [
			next_stage,
			StageTypeScript.get_display_name(next_type).to_upper(),
		]
	var area_id: StringName = StageDatabaseScript.area_for_stage(stage_number)
	if area_id.is_empty():
		return ""
	var database := StageDatabaseScript.load_area(area_id)
	var total: int = int(database.stage_count) if database != null else 1
	var summary := "AREA %s COMPLETE (%d/%d)" % [String(area_id).to_upper(), total, total]
	var next_area_id: StringName = StageDatabaseScript.area_for_stage(stage_number + 1)
	if next_area_id.is_empty() or next_area_id == area_id:
		return summary
	return "%s — NEXT: %s" % [summary, _area_label(next_area_id)]


## Decision for a town close: true when the town currently open was entered from
## the world map, so the host returns to the refreshed map instead of restoring
## the combat view. Consumes the flag — either way the visit is over.
func on_town_closed() -> bool:
	var return_to_map := _town_open_from_map
	_town_open_from_map = false
	return return_to_map


## Entry bookkeeping for one resolved route: for a visit-type stage, records the
## position through the single position writer and the clear itself (entering the
## town IS completing it in this build, so the linear chain can move past it).
## A combat/boss stage starts a battle instead, and the host's stage_started
## forwarding moves the position — one writer either way.
func _apply_entry(route: Dictionary, destination: int) -> void:
	var stage_number: int = int(route.get("stage_number", 0))
	var from_map: bool = bool(route.get("from_map", false))
	_town_open_from_map = destination == StageRouterScript.Destination.TOWN and from_map
	if destination == StageRouterScript.Destination.TOWN:
		# The visit IS the clear, and the completion is recorded BEFORE the
		# position write so a single progress_changed notification covers both
		# (and therefore a single save).
		if _progress != null:
			_progress.complete_stage(stage_number)
		on_stage_started(stage_number)
		route["visit_completed"] = true
		route["next_text"] = next_stage_text(stage_number)
	gameplay_requested.emit(route)


## Upper-case display name of an area id, falling back to the id itself.
func _area_label(area_id: StringName) -> String:
	var database := StageDatabaseScript.load_area(area_id)
	if database != null and not database.display_name.is_empty():
		return database.display_name.to_upper()
	return String(area_id).to_upper()
