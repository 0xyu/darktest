extends SceneTree

## Phase 4 smoke test: StageRouter (stage entry dispatcher).
## Run headless: godot --headless --path . -s res://tests/stage_router_smoke_test.gd
##
## Verifies the router turns (area_id, stage_number) into the right gameplay
## destination by reading StageData.stage_type — never by hard-coding stage
## numbers — and walks the authored Forest path: 01 -> Combat / 06 -> Combat /
## 08 -> Town / 10 -> Boss (Boss routes into Combat; its authored type stays
## BOSS). Unknown / un-authored stages resolve to clean failed routes.

const StageRouterScript = preload("res://scripts/systems/stage_router.gd")
const StageDatabaseScript = preload("res://scripts/data/stage_database.gd")
const StageTypeScript = preload("res://scripts/data/stage_type.gd")
const StageDataScript = preload("res://scripts/data/stage_data.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_forest_walkthrough()
	_test_boss_routes_into_combat_but_keeps_type()
	_test_destination_names()
	_test_destination_for_stage()
	_test_unknown_requests_fail_cleanly()
	_test_request_enter_emits_only_for_routable_stages()
	_test_unroutable_stage_type_is_none()

	if _failures.is_empty():
		print("StageRouter smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_forest_walkthrough() -> void:
	var router := StageRouterScript.new()
	# Forest authored layout (StageDatabase): COMBAT everywhere except 08 TOWN /
	# 10 BOSS. Routing is driven by stage_type, not by number. Stage 06 is an
	# authored override that keeps the default COMBAT gameplay and carries
	# content instead, so it routes exactly like its neighbours.
	var expected_destination := {
		1: StageRouterScript.Destination.COMBAT,
		2: StageRouterScript.Destination.COMBAT,
		3: StageRouterScript.Destination.COMBAT,
		4: StageRouterScript.Destination.COMBAT,
		5: StageRouterScript.Destination.COMBAT,
		6: StageRouterScript.Destination.COMBAT,
		7: StageRouterScript.Destination.COMBAT,
		8: StageRouterScript.Destination.TOWN,
		9: StageRouterScript.Destination.COMBAT,
		10: StageRouterScript.Destination.COMBAT,  # BOSS reuses the combat route
	}
	for number in range(1, 11):
		var route_result: Dictionary = router.route(&"forest", number)
		_expect(bool(route_result.get("ok", false)), "forest stage %d should route (ok)" % number)
		if not bool(route_result.get("ok", false)):
			continue
		_expect(
			route_result.get("destination") == expected_destination[number],
			"forest stage %d should route to %s" % [number, StageRouterScript.get_destination_name(expected_destination[number])]
		)
		_expect(
			route_result.get("stage_id") == "forest_%03d" % number,
			"forest stage %d route should carry its canonical id (got %s)" % [number, route_result.get("stage_id")]
		)
		_expect(route_result.get("stage") != null, "forest stage %d route should carry the StageData" % number)


func _test_boss_routes_into_combat_but_keeps_type() -> void:
	var router := StageRouterScript.new()
	var route_result: Dictionary = router.route(&"forest", 10)
	_expect(bool(route_result.get("ok", false)), "forest boss stage 10 should route (ok)")
	# The authored type must stay BOSS on the record even though the route kind is
	# Combat — Phase 5 consults stage_type to load boss-specific combat data.
	_expect(route_result.get("stage_type") == StageTypeScript.BOSS, "forest 10 stage_type should remain BOSS")
	_expect(route_result.get("destination") == StageRouterScript.Destination.COMBAT, "forest boss stage 10 should route into Combat")


func _test_destination_names() -> void:
	_expect(StageRouterScript.get_destination_name(StageRouterScript.Destination.COMBAT) == "Combat", "COMBAT destination name")
	_expect(StageRouterScript.get_destination_name(StageRouterScript.Destination.TOWN) == "Town", "TOWN destination name")
	_expect(StageRouterScript.get_destination_name(StageRouterScript.Destination.NONE) == "Unknown", "NONE destination name is Unknown")
	_expect(StageRouterScript.is_valid_destination(StageRouterScript.Destination.TOWN), "TOWN is a valid destination")
	_expect(not StageRouterScript.is_valid_destination(999), "999 is not a valid destination")


func _test_destination_for_stage() -> void:
	var router := StageRouterScript.new()
	var authored_combat_stage := StageDatabaseScript.lookup(&"forest", 6)
	_expect(authored_combat_stage != null, "forest stage 6 should be authored")
	if authored_combat_stage != null:
		_expect(router.destination_for_stage(authored_combat_stage) == StageRouterScript.Destination.COMBAT, "destination_for_stage(forest 6) should be COMBAT")
	var boss_stage := StageDatabaseScript.lookup(&"forest", 10)
	_expect(boss_stage != null, "forest stage 10 should be authored")
	if boss_stage != null:
		_expect(router.destination_for_stage(boss_stage) == StageRouterScript.Destination.COMBAT, "destination_for_stage(forest 10) should be COMBAT")
	_expect(router.destination_for_stage(null) == StageRouterScript.Destination.NONE, "destination_for_stage(null) should be NONE")


func _test_unknown_requests_fail_cleanly() -> void:
	var router := StageRouterScript.new()
	_expect(not bool(router.route(&"forest", 0).get("ok", false)), "forest stage 0 should fail to route")
	_expect(not bool(router.route(&"forest", 11).get("ok", false)), "forest stage 11 (past stage_count) should fail to route")
	_expect(not bool(router.route(&"swamp", 1).get("ok", false)), "un-authored area swamp should fail to route")
	for number in [0, 11, -3]:
		var route_result: Dictionary = router.route(&"forest", number)
		_expect(route_result.get("destination") == StageRouterScript.Destination.NONE, "failed route for forest %d should carry NONE" % number)
		_expect(not String(route_result.get("reason", "")).is_empty(), "failed route for forest %d should explain its reason" % number)


func _test_request_enter_emits_only_for_routable_stages() -> void:
	var router := StageRouterScript.new()
	var received: Array[Dictionary] = []
	router.enter_requested.connect(func(route_result: Dictionary) -> void: received.append(route_result))

	_expect(router.request_enter(&"forest", 6), "request_enter(forest 6) should succeed")
	_expect(router.request_enter(&"forest", 8), "request_enter(forest 8) should succeed")
	_expect(not router.request_enter(&"forest", 0), "request_enter(forest 0) should be rejected")
	_expect(not router.request_enter(&"swamp", 1), "request_enter(swamp 1) should be rejected")

	_expect(received.size() == 2, "request_enter should emit exactly for the two routable stages")
	if received.size() >= 1:
		_expect(received[0].get("stage_id") == "forest_006", "first emitted route should be forest_006")
		var destination: int = received[0].get("destination", StageRouterScript.Destination.NONE)
		_expect(destination == StageRouterScript.Destination.COMBAT, "first emitted route should target COMBAT")
	if received.size() >= 2:
		_expect(received[1].get("stage_id") == "forest_008", "second emitted route should be forest_008")
		_expect(received[1].get("destination") == StageRouterScript.Destination.TOWN, "second emitted route should target TOWN")


func _test_unroutable_stage_type_is_none() -> void:
	var router := StageRouterScript.new()
	var invalid_stage := StageDataScript.new()
	invalid_stage.stage_type = 999  # not an authored StageType -> must not route
	_expect(router.destination_for_stage(invalid_stage) == StageRouterScript.Destination.NONE, "unknown stage_type should resolve to NONE, not a guessed route")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
