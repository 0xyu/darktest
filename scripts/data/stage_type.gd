class_name StageType
extends RefCounted

## Gameplay type of a stage node on an area path.
##
## Phase 1 of the Area / Stage / StageType system. Only the type catalogue lives
## here; the set can grow by appending enum values in this single file without
## touching AreaData, StageData, or PlayerProgress. Routing and validation read
## `is_valid()` / the enum value.
##
## This enum answers ONE question only: which gameplay view does the stage open
## (COMBAT and BOSS both open the battle; TOWN opens the town view). Anything a
## stage adds ON TOP of its gameplay — an authored boss enemy, a chest, a
## healing pool, a story beat — is authored content, NOT a stage type, and lives
## in the stage's content layer (see StageContent). Authored content is
## therefore never a new enum value here.
##
## The former EVENT type was retired for exactly that reason: it described
## "this stage is not really a battle", which the content layer now expresses
## without splitting the gameplay vocabulary.

enum {
	COMBAT = 0,
	TOWN,
	BOSS,
}

const DISPLAY_NAMES := {
	COMBAT: "Combat",
	TOWN: "Town",
	BOSS: "Boss",
}


## True when `stage_type` is one of the currently defined gameplay types.
static func is_valid(stage_type: int) -> bool:
	return DISPLAY_NAMES.has(stage_type)


static func get_display_name(stage_type: int) -> String:
	return DISPLAY_NAMES.get(stage_type, "Unknown")
