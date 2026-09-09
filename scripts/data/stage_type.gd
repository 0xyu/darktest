class_name StageType
extends RefCounted

## Gameplay type of a stage node on an area path.
##
## Phase 1 of the Area / Stage / StageType system. Only the type catalogue lives
## here; the set can grow (ELITE / TREASURE / SHRINE / SECRET ...) by appending
## enum values in this single file without touching AreaData, StageData, or
## PlayerProgress. Routing and validation read `is_valid()` / the enum value.

enum {
	COMBAT = 0,
	EVENT,
	TOWN,
	BOSS,
}

const DISPLAY_NAMES := {
	COMBAT: "Combat",
	EVENT: "Event",
	TOWN: "Town",
	BOSS: "Boss",
}


## True when `stage_type` is one of the currently defined gameplay types.
static func is_valid(stage_type: int) -> bool:
	return DISPLAY_NAMES.has(stage_type)


static func get_display_name(stage_type: int) -> String:
	return DISPLAY_NAMES.get(stage_type, "Unknown")
