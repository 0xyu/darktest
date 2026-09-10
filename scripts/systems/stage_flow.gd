class_name StageFlow
extends RefCounted

## Owns the authored-stage FLOW POLICY for the running scene: which area / stage
## the player is on, what completing a stage means, what the authored path
## offers next, which stages the linear gate lets the player enter, and where a
## town visit returns to.
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
## Rules that live here (and nowhere else)
## ---------------------------------------
##   * entry bookkeeping: entering an authored stage records the current area /
##     stage and, for a visit-type stage (TOWN), records the clear itself,
##     because entering a town IS completing that stage in this build
##   * battle completion: clearing battle stage N completes the authored stage N
##     of the area the player is currently on, and reports what is next
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
## has no "return to map after clearing" rule.
##
## Static data is never written
## ---------------------------
## StageDatabase / StageData are read-only here; only PlayerProgress is mutated.

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


## Area the player is currently on, or &"" when no authored stage has been
## entered yet (the endless boot loop never enters one).
func get_current_area_id() -> StringName:
	return _progress.current_area_id if _progress != null else &""


## Requests entry to an authored stage. Returns true when the stage is authored
## and its gameplay has been requested through gameplay_requested. Returns false
## for unknown / un-authored / out-of-range stages — the caller shows the reason.
func request_enter(area_id: StringName, stage_number: int, from_map: bool = false) -> bool:
	if _router == null or _progress == null:
		return false
	var route: Dictionary = _router.route(area_id, stage_number)
	if not bool(route.get("ok", false)):
		return false
	var destination: int = int(route.get("destination", StageRouterScript.Destination.NONE))
	var enriched: Dictionary = route.duplicate()
	enriched["from_map"] = from_map
	_apply_entry(enriched, destination)
	return true


## Reason an entry was rejected, for the host's status line.
func get_entry_failure_reason(area_id: StringName, stage_number: int) -> String:
	if _router == null:
		return "Cannot enter that stage."
	var route: Dictionary = _router.route(area_id, stage_number)
	return str(route.get("reason", "Cannot enter that stage."))


## True when the linear progression lets the player enter this stage. Kept here
## so the world map's lock gate and the flow share one rule; the rule itself
## belongs to PlayerProgress.
func is_stage_unlocked(area_id: StringName, stage_number: int) -> bool:
	if _progress == null:
		return false
	return _progress.is_stage_unlocked(area_id, stage_number)


## Records the clear of battle stage `cleared_stage_number` against the authored
## area the player is currently on and returns the authored "what's next" text.
##
## Returns "" when this clear is not part of an authored path — either no
## authored stage has been entered (the endless boot loop, which must never
## write progress) or the current area does not author that stage number (the
## player ground past the authored path).
##
## Deliberately independent of AUTO / FARMING: the result is identical either way.
func on_battle_cleared(cleared_stage_number: int) -> String:
	if _progress == null:
		return ""
	var area_id: StringName = _progress.current_area_id
	if area_id.is_empty():
		return ""
	var stage := StageDatabaseScript.lookup(area_id, cleared_stage_number)
	if stage == null:
		return ""
	_progress.complete_stage(area_id, cleared_stage_number)
	return next_stage_text(area_id, cleared_stage_number)


## Authored "what's next" after `stage_number` clears: either the next authored
## stage — its type read through the router from StageDatabase, never a hard-coded
## number — or the area-complete summary when it was the final stage.
func next_stage_text(area_id: StringName, stage_number: int) -> String:
	if _router == null:
		return ""
	var next_route: Dictionary = _router.route(area_id, stage_number + 1)
	if bool(next_route.get("ok", false)):
		var next_stage: int = int(next_route.get("stage_number", 0))
		var next_type: int = int(next_route.get("stage_type", StageTypeScript.COMBAT))
		return "STAGE %02d (%s) UNLOCKED" % [
			next_stage,
			StageTypeScript.get_display_name(next_type).to_upper(),
		]
	var database := StageDatabaseScript.load_area(area_id)
	var total: int = int(database.stage_count) if database != null else stage_number
	return "AREA %s COMPLETE (%d/%d)" % [String(area_id).to_upper(), total, total]


## Decision for a town close: true when the town currently open was entered from
## the world map, so the host returns to the refreshed map instead of restoring
## the combat view. Consumes the flag — either way the visit is over.
func on_town_closed() -> bool:
	var return_to_map := _town_open_from_map
	_town_open_from_map = false
	return return_to_map


## Entry bookkeeping for one resolved route: records the current position and, for
## a visit-type stage, the clear itself (entering the town IS completing it in
## this build, so the linear chain can move past it).
func _apply_entry(route: Dictionary, destination: int) -> void:
	var area_id: StringName = StringName(route.get("area_id", &""))
	var stage_number: int = int(route.get("stage_number", 0))
	var from_map: bool = bool(route.get("from_map", false))
	_progress.current_area_id = area_id
	_progress.current_stage_number = stage_number
	_town_open_from_map = destination == StageRouterScript.Destination.TOWN and from_map
	if destination == StageRouterScript.Destination.TOWN:
		_progress.complete_stage(area_id, stage_number)
		route["visit_completed"] = true
		route["next_text"] = next_stage_text(area_id, stage_number)
	gameplay_requested.emit(route)
