class_name StageRouter
extends RefCounted

## Phase 4 dispatcher of the Area / Stage / StageType system (Coding Plan Rev 2).
##
## StageRouter is the single seam that turns an "enter this stage" request —
## (area_id, stage_number) — into the gameplay the player should reach. It looks
## the stage up through StageDatabase and dispatches from the authored
## StageData.stage_type, NEVER from hard-coded stage numbers (no `if stage == 6`).
##
## Phase 4 scope is a routing shell only:
##   * route() / destination_for_stage() answer "where does this stage take the
##     player" for every authored stage, lazily via StageDatabase.lookup.
##   * request_enter() is the entry-point request a host connects to (Phase 5
##     wiring, or the future map/completion flow) to actually start that gameplay.
##   * This file does NOT start combat or show TownView —
##     that content wiring is Phase 5. It does NOT read or write PlayerProgress —
##     unlock gating belongs to the flow caller (Phase 7).
##
## Static data only: no completed / unlocked / current state is stored here.
## Distinguish from the battle-side StageManager (scripts/systems/stage_manager.gd,
## the wave / spawn engine of ONE fight). StageRouter never spawns enemies or
## manages a fight; the two share no state and are intentionally unrelated.

const StageDatabaseScript := preload("res://scripts/data/stage_database.gd")
const StageTypeScript := preload("res://scripts/data/stage_type.gd")

## Destination kinds a routed stage can send the player into.
##
## The vocabulary is deliberately smaller than StageType: BOSS is an authored
## *type* whose *gameplay* reuses the combat route in the current build (there is
## no separate boss scene; mini-boss / boss is a battle-layer feature), so a BOSS
## stage routes to Destination.COMBAT while its record still reports
## stage_type == BOSS. If a future phase adds a dedicated boss or shrine scene,
## the new destination is added HERE only — data classes stay untouched.
enum Destination {
	COMBAT,
	TOWN,
	NONE = -1,
}

const DESTINATION_NAMES := {
	Destination.COMBAT: "Combat",
	Destination.TOWN: "Town",
}

## Emitted when an authored, routable stage is requested for entry. A host
## (Phase 5 wiring / future flow) connects here to start the actual gameplay.
## `route` is the same dictionary route() returns.
signal enter_requested(route: Dictionary)


## True when `destination` is one of the current route kinds.
static func is_valid_destination(destination: int) -> bool:
	return DESTINATION_NAMES.has(destination)


static func get_destination_name(destination: int) -> String:
	return DESTINATION_NAMES.get(destination, "Unknown")


## Central stage_type -> route table. Today only BOSS diverges from its authored
## type (it routes into Combat). Future authored types or future route kinds are
## decided here and nowhere else.
##
## Note that authored *content* (a forced boss enemy, a chest, a healing pool)
## does NOT appear here: content is layered on top of the gameplay this table
## picks, so adding content never changes a route.
func _destination_for_stage_type(stage_type: int) -> int:
	match stage_type:
		StageTypeScript.COMBAT, StageTypeScript.BOSS:
			return Destination.COMBAT
		StageTypeScript.TOWN:
			return Destination.TOWN
		_:
			return Destination.NONE


## Resolves the gameplay destination for an already-materialized stage. Returns
## Destination.NONE for a null / not-yet-authored-valid stage.
func destination_for_stage(stage: StageData) -> int:
	if stage == null:
		return Destination.NONE
	return _destination_for_stage_type(stage.stage_type)


## Full route record for one stage request. Looks the stage up through
## StageDatabase.lookup; unknown / un-authored / out-of-range requests resolve to
## a clean failed route (ok == false, reason set) — mirroring the "unknown query
## returns null" style of Phase 2.
func route(area_id: StringName, stage_number: int) -> Dictionary:
	var stage := StageDatabaseScript.lookup(area_id, stage_number)
	if stage == null:
		return {
			"ok": false,
			"area_id": area_id,
			"stage_number": stage_number,
			"stage": null,
			"stage_id": "",
			"stage_type": StageTypeScript.COMBAT,
			"destination": Destination.NONE,
			"destination_name": "",
			"display_name": "",
			"reason": "No authored stage %s/%d (unknown area or out of range)." % [area_id, stage_number],
		}
	var destination := _destination_for_stage_type(stage.stage_type)
	return {
		"ok": true,
		"area_id": area_id,
		"stage_number": stage_number,
		"stage": stage,
		"stage_id": String(stage.id),
		"stage_type": stage.stage_type,
		"destination": destination,
		"destination_name": get_destination_name(destination),
		"display_name": stage.display_name,
		"reason": "",
	}


## Entry-point request for a host: resolves the route and, when the stage is
## authored and routable, emits enter_requested(route) and returns true. Returns
## false (emitting nothing) for unknown / un-authored stages — the caller decides
## what to show on a failed entry, since lock gating is a Phase 7 flow concern.
func request_enter(area_id: StringName, stage_number: int) -> bool:
	var route_result := route(area_id, stage_number)
	if not bool(route_result.get("ok", false)):
		return false
	enter_requested.emit(route_result)
	return true
