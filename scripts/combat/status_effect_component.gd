class_name StatusEffectComponent
extends RefCounted

## Timed combat statuses on one actor. A status is an id plus the number of that
## actor's own turns it still suppresses; re-applying refreshes the duration
## instead of stacking, so a status never outlives the turns it was paid for.
##
## `STUN` is the only status today — the §12 "Stun" affix. A stunned actor loses
## its whole turn and the turn it lost pays for one turn of the status.

## Emitted only for a NEW status; refreshing an active one stays silent so the
## presentation layer does not announce the same stun twice.
signal applied(status_id: StringName, turns: int)
signal expired(status_id: StringName)
signal changed()

const STUN: StringName = &"stun"
## Turns one stun application costs its target. Centralised so the affix, the
## enemy turn and the presentation layer can never disagree.
const STUN_TURNS: int = 1
## §3.2/§12: turns of immunity that follow a released stun. A stun that expired leaves the
## target unable to be stunned again until it has COMPLETED its next own turn, which is what
## stops a high stun chance from taking every turn away forever ("解除后的下一个自身回合完成前
## 不能再次被眩晕"). One turn is exactly that window.
const STUN_IMMUNITY_TURNS: int = 1

var _turns_remaining: Dictionary[StringName, int] = {}
## Own turns the actor must still complete before [constant STUN] may be applied again.
var _stun_immunity_turns: int = 0


## The number of that actor's own turns still suppressed by `status_id`.
func turns_remaining(status_id: StringName) -> int:
	return maxi(int(_turns_remaining.get(status_id, 0)), 0)


func has_status(status_id: StringName) -> bool:
	return turns_remaining(status_id) > 0


## Applies (or refreshes) a status. Returns true only when it was not already
## active, which is what callers use to decide whether to announce it.
##
## §3.2: a stun applied to a target that is still inside its post-release immunity window is
## REFUSED (false), so the affix cannot chain-lock the target turn after turn.
func apply_status(status_id: StringName, turns: int) -> bool:
	if status_id.is_empty() or turns <= 0:
		return false
	if status_id == STUN and _stun_immunity_turns > 0:
		return false
	var is_new: bool = not has_status(status_id)
	_turns_remaining[status_id] = maxi(turns_remaining(status_id), turns)
	if is_new:
		applied.emit(status_id, _turns_remaining[status_id])
	changed.emit()
	return is_new


func apply_stun(turns: int = STUN_TURNS) -> bool:
	return apply_status(STUN, turns)


func is_stunned() -> bool:
	return has_status(STUN)


func get_active_status_ids() -> Array[StringName]:
	var active: Array[StringName] = []
	for status_id in _turns_remaining:
		if _turns_remaining[status_id] > 0:
			active.append(status_id)
	return active


## Consumes one turn from every active status. The actor's own turn calls this, so
## a status that suppressed a turn is paid for by the turn it suppressed.
##
## §3.2: the turn that RELEASES a stun also opens the immunity window, which the actor then
## spends by completing its next own turn ([method complete_turn]).
func tick_turn() -> void:
	if _turns_remaining.is_empty():
		return
	for status_id in _turns_remaining.keys():
		_turns_remaining[status_id] = maxi(_turns_remaining[status_id] - 1, 0)
		if _turns_remaining[status_id] <= 0:
			_turns_remaining.erase(status_id)
			if status_id == STUN:
				_stun_immunity_turns = STUN_IMMUNITY_TURNS
			expired.emit(status_id)
	changed.emit()


## §3.2: one own turn finished without being stunned. That turn is what the post-release
## immunity window was waiting for, so it closes here.
func complete_turn() -> void:
	if _stun_immunity_turns <= 0:
		return
	_stun_immunity_turns -= 1
	changed.emit()


## Whether a stun would be refused right now (§3.2 immunity window).
func is_stun_immune() -> bool:
	return _stun_immunity_turns > 0


func clear_all() -> void:
	if _turns_remaining.is_empty() and _stun_immunity_turns == 0:
		return
	var cleared: Array[StringName] = _turns_remaining.keys()
	_turns_remaining.clear()
	_stun_immunity_turns = 0
	for status_id in cleared:
		expired.emit(status_id)
	changed.emit()
