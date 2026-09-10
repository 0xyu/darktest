class_name StageContent
extends Resource

## ONE authored content entry layered on top of a stage's normal gameplay.
##
## The authored-stage model
## -----------------------
## A stage is a normal stage first. Only stages the designer explicitly authors
## differ at all, and even then the gameplay is unchanged: the stage still runs
## its battle, and the content below is added on top of it. This is why content is
## NOT a StageType — a new piece of content never changes which gameplay a stage
## opens (see stage_type.gd for that decision).
##
## Lifecycle
## ---------
## `one_shot` separates the two lifecycles the design calls for:
##   * one_shot == true  — consumed once and gone for good (a chest that has been
##     opened, a pool that has been drained). The stage then behaves as a plain
##     normal stage. Consumption is recorded in AuthoredContentState, which is
##     independent of map progress.
##   * one_shot == false — the content is (re)created every time the stage starts,
##     so it keeps appearing (a boss enemy the player can fight again).
##
## Automation never affects content
## -------------------------------
## Content resolves the same way whether AUTO / FARMING is on or off: the player
## (or the auto walker) stepping onto the content's cell is the only trigger.
##
## "A specific boss enemy" is NOT a kind here
## -----------------------------------------
## The battle pipeline already expresses an authored enemy for a stage: an
## authored LevelConfig at resources/levels/level_<n>.tres whose `boss` field is
## set, picked up by LevelProvider for battle level n. Because an authored stage
## number maps 1:1 onto its battle level (Forest 06 <-> battle level 6), that
## existing mechanism IS the "force this boss on this stage" feature — see
## level_010.tres for the shipped example. Re-adding it here would duplicate a
## working system.

enum Kind {
	CHEST,
	HEALING_POOL,
}

const KIND_DISPLAY_NAMES := {
	Kind.CHEST: "Chest",
	Kind.HEALING_POOL: "Healing Pool",
}

## Stable id within its stage, e.g. &"cache" for forest_006. Combined with the
## stage id it forms the consumption key "<stage_id>:<content_id>".
@export var id: StringName = &""
@export var kind: int = Kind.CHEST
@export var display_name: String = ""
## Consumed once and never created again. See the class docs for the two
## lifecycles.
@export var one_shot: bool = true

# --- Kind.CHEST ---
## Gold granted when opened (0 grants none). Paid through GoldSystem so chest gold
## obeys the same HUD / logging path as every other gold award.
@export_range(0, 99999999, 1) var gold: int = 0
## Optional loot table rolled through LootGenerator; null rolls no item.
@export var loot_table: Resource
## Item level for the rolled loot. 0 means "use the stage number".
@export_range(0, 999999, 1) var item_level: int = 0

# --- Kind.HEALING_POOL ---
## Flat HP restored (0 restores none).
@export_range(0, 99999999, 1) var heal_amount: int = 0
## Additional HP restored as a ratio of max HP, e.g. 0.25 for a quarter.
@export_range(0.0, 1.0, 0.01) var heal_max_hp_ratio: float = 0.0


static func get_kind_display_name(kind: int) -> String:
	return KIND_DISPLAY_NAMES.get(kind, "Unknown")


static func is_valid_kind(kind: int) -> bool:
	return KIND_DISPLAY_NAMES.has(kind)


## Human-readable validation messages; empty means this entry is valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("StageContent id must not be empty.")
	if not is_valid_kind(kind):
		errors.append("StageContent '%s' has invalid kind %d." % [id, kind])
	if kind == Kind.HEALING_POOL and heal_amount <= 0 and heal_max_hp_ratio <= 0.0:
		errors.append("StageContent '%s' healing pool restores nothing (set heal_amount or heal_max_hp_ratio)." % id)
	return errors


func is_valid() -> bool:
	return get_validation_errors().is_empty()


## HP a healing pool should restore for a hero with `max_hp`, combining the flat
## and max-HP-ratio parts.
func get_heal_amount(max_hp: int) -> int:
	var flat: int = maxi(heal_amount, 0)
	var scaled: int = maxi(roundi(float(maxi(max_hp, 0)) * clampf(heal_max_hp_ratio, 0.0, 1.0)), 0)
	return flat + scaled
