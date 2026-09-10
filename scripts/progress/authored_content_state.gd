class_name AuthoredContentState
extends Resource

## Which one-shot authored stage content has already been consumed.
##
## Deliberately SEPARATE from PlayerProgress
## ----------------------------------------
## PlayerProgress answers "which stages has the player cleared" and is the linear
## unlock chain. This class answers a different question — "which stage content
## has been used up" — and the two must not be conflated: clearing a stage does
## not consume its chest, and a consumed chest does not mean the stage is
## unresolved. Keeping them apart also means the map progress model needs no
## change when new content kinds are authored.
##
## Storage format
## --------------
## Keys are plain identifiers, exactly like PlayerProgress.completed_stages, so
## the whole object serializes without referencing any Resource:
##   "<stage_id>:<content_id>"   e.g. "forest_006:cache"
##
## Only one-shot content is recorded here. Repeatable content (one_shot == false,
## e.g. a boss enemy that keeps returning) is never consumed and never appears in
## this set.

## Raised after a piece of one-shot content is recorded as consumed, so a save can
## persist the change (Phase 8) without every caller having to remember to save.
signal content_consumed(key: String)

## Consumed content keys -> true.
@export var consumed: Dictionary = {}


## Canonical key for one piece of stage content. Stage ids come from
## StageDatabase (e.g. "forest_006"), content ids from StageContent.id.
static func make_key(stage_id: String, content_id: StringName) -> String:
	return "%s:%s" % [stage_id, String(content_id)]


## True when this content has already been consumed.
func is_consumed(stage_id: String, content_id: StringName) -> bool:
	if String(stage_id).is_empty() or String(content_id).is_empty():
		return false
	return consumed.has(make_key(stage_id, content_id))


## Records this content as consumed and returns true. Idempotent: consuming the
## same entry twice reports true without adding a second key.
func consume(stage_id: String, content_id: StringName) -> bool:
	var key := make_key(stage_id, content_id)
	if String(stage_id).is_empty() or String(content_id).is_empty():
		return false
	if consumed.has(key):
		return true
	consumed[key] = true
	content_consumed.emit(key)
	return true


func get_consumed_count() -> int:
	return consumed.size()


## Number of consumed entries belonging to `stage_id`, e.g. 1 after the forest_006
## chest was opened.
func get_consumed_count_for_stage(stage_id: String) -> int:
	var count: int = 0
	var prefix: String = "%s:" % stage_id
	for key in consumed:
		if String(key).begins_with(prefix):
			count += 1
	return count


func forget_all() -> void:
	consumed.clear()
