class_name DamageResult
extends Resource

## Data produced by a damage calculation; it performs no calculation itself.
@export var attacker_id: StringName = &""
@export var target_id: StringName = &""
@export var skill_id: StringName = &""
@export var raw_damage: int = 0
@export var final_damage: int = 0
## §4.1: the HP the target ACTUALLY lost, which is `final_damage` capped by the HP it had.
## Overkill is not part of it, so life steal can never pay for damage that never landed.
@export var hp_lost: int = 0
@export var is_critical: bool = false
## The strike dealt no damage: either it was refused or the target dodged it.
@export var is_miss: bool = false
## §4: the attack never happened at all — no target in range, an invalid target, or
## no action left. A refused attack must not spend the action and must not be
## presented as a strike; the input surface reports the reason as text instead.
@export var is_refused: bool = false
## §12 Dodge affix: the attack happened but the target evaded it.
@export var is_dodge: bool = false
## §12 Life Steal affix: HP actually restored to the attacker by this hit.
@export var lifesteal_heal: int = 0
## §12 Stun affix: the status this hit applied to the target, if any.
@export var applied_status_id: StringName = &""
@export var applied_status_turns: int = 0
@export var target_defeated: bool = false

## Live node references for the presentation layer only (animation targets).
## Gameplay logic keeps using the *_id fields. Not exported so they are never
## serialized into saved resources.
var attacker: Node = null
var target: Node = null
