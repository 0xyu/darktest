class_name grid_combat
extends Node2D

const SpecialEncounterTypeResource = preload("res://scripts/systems/special_encounter_type.gd")
const SubHeroAttackEffectResource = preload("res://scripts/combat/sub_hero_attack_effect.gd")
const StageFlowScript = preload("res://scripts/systems/stage_flow.gd")
const StageDatabaseScript = preload("res://scripts/data/stage_database.gd")
const StageContentControllerScript = preload("res://scripts/world/stage_content_controller.gd")
const StageProgressSaveScript = preload("res://scripts/progress/stage_progress_save.gd")
## The battlefield spans the full screen width up to this cap (the base 720px
## design width), so it stays a sane size on very wide windows or devices.
const MAX_GRID_WIDTH: float = 720.0

@onready var grid: GridMap2D = $Grid
@onready var dungeon_background: Sprite2D = $DungeonBackground
@onready var player: PlayerController = $Player
@onready var turn_manager: TurnManager = $TurnManager
@onready var combat_system: CombatSystem = $CombatSystem
@onready var stage_manager: StageManager = $StageManager
@onready var experience_system: ExperienceSystem = $ExperienceSystem
@onready var hud: MobileCombatHUD = $MobileCombatHUD
@onready var gold_system = $GoldSystem
@onready var loot_system = $LootSystem
@onready var auto_combat: AutoCombatController = $AutoCombatController
@onready var sub_hero_combat_manager: SubHeroCombatManager = $SubHeroCombatManager
@onready var combat_presentation: CombatPresentationSystem = $CombatPresentation

var _last_move_text: String = "Awaiting input"
var _active_enemies: Array[Node] = []
var _grid_play_area: Rect2 = Rect2()
var _defeat_retry_scheduled: bool = false
## Authored-stage flow policy: entry bookkeeping, completion, the unlock gate and
## the town return decision. This scene is only its HOST — it starts battles,
## switches views and forwards engine / HUD signals — so no flow rule lives in
## this file. It is ALSO the single advance seam: AUTO and the manual NEXT STAGE
## button both end up in _advance_after_clear(), so automation can never change a
## stage's result. See stage_flow.gd.
var _flow: StageFlow
## Authored stage content layer (chests, healing pools, ...). Created in code, not
## in the scene, so a project with no authored content adds no scene nodes and no
## behaviour: for a stage whose authored content is empty this controller does
## nothing at all.
var _stage_content: StageContentController
## The player-side progress save (Phase 8): it owns the PlayerProgress and the
## AuthoredContentState the rest of the scene is built from, restores them on boot
## and persists them whenever the flow announces a real progress change. It is the
## ONE mount point — the flow and the content controller are injected from it, so
## neither can end up with its own private copy of the player's state.
var _stage_save: StageProgressSave


func _ready() -> void:
	grid.queue_redraw()
	player.reset_movement_points()
	player.moved.connect(_on_player_moved)
	combat_system.attach_turn_manager(turn_manager)
	combat_system.set_player_actor(player)
	combat_system.connect_actor(player)
	# Enemy turns wait for the hero's attack animation to finish so enemies
	# never move/attack in the same beat as the player's own swing.
	turn_manager.set_enemy_phase_waiter(combat_presentation)
	# The enemy turn ENDS as soon as the enemy's strike is resolved, so its attack
	# animation keeps playing into the hero's turn. Actions from the cell the hero
	# stands on stay available (by design), but stepping to another cell waits for
	# the swing to finish.
	combat_presentation.enemy_attack_presentation_changed.connect(_on_enemy_attack_presentation_changed)
	combat_system.attack_resolved.connect(_on_attack_resolved)
	combat_system.skill_resolved.connect(_on_skill_resolved)
	combat_system.skill_failed.connect(_on_skill_failed)
	combat_system.actor_died.connect(_on_actor_died)
	experience_system.attach_player(player)
	experience_system.attach_combat_system(combat_system)
	experience_system.experience_awarded.connect(_on_experience_awarded)
	experience_system.level_up.connect(_on_level_up)
	gold_system.attach_player(player)
	gold_system.attach_combat_system(combat_system)
	gold_system.attach_stage_manager(stage_manager)
	gold_system.gold_awarded.connect(_on_gold_awarded)
	loot_system.attach_combat_system(combat_system)
	loot_system.attach_stage_manager(stage_manager)
	loot_system.loot_dropped.connect(_on_loot_dropped)
	turn_manager.state_changed.connect(_on_turn_state_changed)
	stage_manager.stage_started.connect(_on_stage_started)
	stage_manager.enemy_spawned.connect(_on_enemy_spawned)
	stage_manager.stage_completed.connect(_on_stage_completed)
	stage_manager.stage_generation_failed.connect(_on_stage_generation_failed)
	player.selection_changed.connect(_on_selection_changed)
	player.equipment_effect_triggered.connect(_on_equipment_effect_triggered)
	player.sub_hero_slots_changed.connect(_on_sub_hero_slots_changed)
	# A Sub Hero kill takes the same path as the player's own kill, so it awards
	# the same EXP, gold and loot.
	sub_hero_combat_manager.attach_combat_system(combat_system)
	sub_hero_combat_manager.attack_resolved.connect(_on_sub_hero_attack_resolved)
	sub_hero_combat_manager.attack_feedback_requested.connect(_on_sub_hero_attack_feedback_requested)
	sub_hero_combat_manager.cooldown_started.connect(_on_sub_hero_cooldown_started)
	sub_hero_combat_manager.combat_cleared.connect(_on_sub_hero_combat_cleared)
	sub_hero_combat_manager.combat_state_changed.connect(_on_sub_hero_combat_state_changed)
	hud.move_requested.connect(_on_hud_move_requested)
	hud.attack_requested.connect(_on_hud_attack_requested)
	hud.skill_requested.connect(_on_hud_skill_requested)
	hud.item_requested.connect(_on_hud_item_requested)
	hud.end_turn_requested.connect(_on_hud_end_turn_requested)
	hud.next_stage_requested.connect(_on_hud_next_stage_requested)
	hud.auto_toggle_requested.connect(_on_hud_auto_toggle_requested)
	hud.farming_toggle_requested.connect(_on_hud_farming_toggle_requested)
	hud.game_speed_requested.connect(_on_hud_game_speed_requested)
	# Player-side progress save. Loading happens BEFORE the flow and the content
	# controller exist, so both are built from the restored state instead of having
	# to be repaired afterwards. The saved position is resumed at the end of _ready.
	_stage_save = StageProgressSaveScript.new()
	_stage_save.load()
	# A stage's guaranteed boss drop is one-shot content, so it is recorded in the
	# save's consumed-content store — the store that autosaves when it changes.
	loot_system.attach_content_state(_stage_save.content_state)
	# Authored-stage flow: the scene hosts it, the flow owns the rules. It is given
	# the save's progress object — the flow never builds its own.
	_flow = StageFlowScript.new(_stage_save.progress)
	_flow.gameplay_requested.connect(_apply_stage_entry)
	# Authored content layer. It reads the flow's current area and the stage's
	# authored entries; consumed state is kept separately from map progress and is
	# restored from the same save.
	_stage_content = StageContentControllerScript.new()
	_stage_content.name = "StageContentController"
	add_child(_stage_content)
	_stage_content.configure(grid, player, stage_manager, _flow, gold_system, _stage_save.content_state)
	_stage_content.content_resolved.connect(_on_stage_content_resolved)
	# Autosave: the save subscribes to the one writer of progress and to consumed
	# content, so every path that changes either persists without a save call here.
	_stage_save.bind(_flow)
	hud.area_stage_enter_requested.connect(_on_hud_area_stage_enter_requested)
	# Battlefield clicks: the HUD owns the GUI pipeline (the grid is drawn behind a
	# Control), this scene owns what a click means.
	hud.battlefield_clicked.connect(_on_hud_battlefield_clicked)
	# World map host — the map view is refreshed from PlayerProgress and its
	# stage clicks route through the same enter_area_stage entry.
	hud.world_map_toggle_requested.connect(_on_hud_world_map_toggle_requested)
	hud.world_map_stage_enter_requested.connect(_on_world_map_stage_enter_requested)
	# Town close is routed through the host so a town visit opened from the world
	# map returns to the refreshed map while every other close keeps restoring
	# the combat view.
	hud.town_close_requested.connect(_on_town_close_requested)
	auto_combat.attach_systems(player, turn_manager, combat_system, stage_manager, grid)
	auto_combat.auto_mode_changed.connect(_on_auto_mode_changed)
	auto_combat.farming_changed.connect(_on_farming_changed)
	auto_combat.auto_action_taken.connect(_on_auto_action_taken)
	auto_combat.game_speed_changed.connect(_on_game_speed_changed)
	# AUTO asks the host to advance instead of moving the stage itself, so an AUTO
	# advance and the manual NEXT STAGE button take the same path.
	auto_combat.stage_advance_requested.connect(_on_auto_stage_advance_requested)
	# FARMING waits on the presentation layer before it re-spawns a cleared stage,
	# so the last enemy's damage number and death animation play out before the
	# wave is rebuilt.
	auto_combat.set_presentation_waiter(combat_presentation)
	hud.set_farming_mode(auto_combat.is_farming_enabled())
	hud.set_game_speed(auto_combat.get_game_speed())
	_sync_sub_hero_combatants()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_layout_portrait_grid()
	_start_first_stage()
	_refresh_arena_markers()
	queue_redraw()
	# The HUD's CombatSection is sized only after the first container sort, so
	# run the layout again once that rect becomes measurable.
	_relayout_when_combat_ready()


## Boots the first battle of this session: the stage the save left the player on,
## or the first stage of a new game.
##
## The saved position is authoritative and is NOT pulled back into an authored
## area — a position past every area (the endless tail) is the normal state after
## the authored content runs out, and it resumes as the plain endless battle it
## belongs to. The battle level equals the global stage number, which is the same
## mapping the endless loop already uses.
##
## A save made while standing on a visit-type stage (the town) resumes the battle
## at that stage number rather than re-opening the town: the visit is already
## recorded as completed, and a boot that started no stage at all would leave the
## arena with no enemies and no way to move on. The town stays one map click away.
##
## A save that cannot be used never blocks booting: the save keeps its fresh state
## and the session starts a new game from stage 1.
func _start_first_stage() -> void:
	var resume_stage: int = _stage_save.get_resume_stage_number() if _stage_save != null else 1
	if resume_stage > 1 and stage_manager.initialize_stage(resume_stage):
		# _on_stage_started has already reported the battle; replace that with what
		# actually happened, so a restored session is visible rather than silent.
		_last_move_text = "SAVE RESTORED — STAGE %02d" % resume_stage
		queue_redraw()
		return
	stage_manager.initialize_stage(1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_auto") and turn_manager.get_phase() != TurnState.DEFEAT:
		auto_combat.toggle_auto()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("primary_action") and _is_current_stage_cleared():
		# SPACE is the keyboard twin of the NEXT STAGE button, but only on the
		# cleared path: during a fight the same press already ends the player's
		# turn (PlayerController.action_completed), and the replay skip must not
		# fight that press for the same key.
		if _advance_after_clear():
			get_viewport().set_input_as_handled()


func _on_hud_move_requested(direction: Vector2i) -> void:
	player.try_input_move(direction)


# ---------------------------------------------------------------------------
# Battlefield click HOST (click-to-move / click-to-attack).
# The HUD reports the click position; the RULES stay where they already live: the
# movement range is the grid's reachable set (PlayerController.can_move_to, the
# same set the grid highlights) and attack validity is CombatSystem.can_attack, so
# a click and the D-pad / ATTACK button can never disagree.
# ---------------------------------------------------------------------------

func _on_hud_battlefield_clicked(screen_position: Vector2) -> void:
	if grid == null or player == null:
		return
	var cell: Vector2i = grid.world_to_grid(screen_position)
	if not grid.is_valid_cell(cell):
		return
	var enemy: EnemyController = _get_living_enemy_at(cell)
	if enemy != null:
		_click_attack_enemy(enemy)
		return
	_click_move_to(cell)


## An enemy under the cursor is the more specific command, so it wins over the
## cell it stands on: the hero is told to fight it, never to walk into it.
## Only a legal attack is issued — during the player's own turn, out of free roam,
## with the target inside the current attack range. An out-of-range click just
## selects the target and says so, so it cannot burn the turn on a miss.
func _click_attack_enemy(enemy: EnemyController) -> void:
	if turn_manager.get_phase() != TurnState.PLAYER_TURN or not player.is_input_enabled() or player.is_free_moving():
		_last_move_text = "CANNOT ATTACK — not the player's turn"
		queue_redraw()
		return
	player.set_target(enemy)
	if not combat_system.can_attack(player, enemy):
		_last_move_text = "%s IS OUT OF RANGE — move closer" % enemy.get_display_name().to_upper()
		queue_redraw()
		return
	player.attack_requested.emit(player, enemy)


## A cell click is a move request, allowed only inside the movement range (free
## roam is unbounded, exactly like the AUTO walk to the stage exit).
##
## Clicking the hero's OWN cell is a no-op that re-selects the hero, never a
## deselect: a deselected hero ignores every click and every D-pad step (both
## refuse to move while `is_selected` is false), so a stray tap on the hero would
## silently freeze the player — most visibly in free roam, where walking freely is
## the whole point.
##
## With no movement points left the click cannot be a walk, so it ends the turn
## instead — see _move_settles_the_turn().
func _click_move_to(cell: Vector2i) -> void:
	if cell == player.get_grid_position():
		player.set_selected(true)
		return
	# A live enemy-attack movement lock is not a range problem, so it gets its own
	# message instead of the misleading "beyond the movement range" one.
	if player.is_movement_locked():
		_last_move_text = "CANNOT MOVE YET — enemy attack in progress"
		queue_redraw()
		return
	# No movement points left: the click cannot be a walk, so the turn ends here
	# instead of the click being refused — see _move_settles_the_turn(). Nothing was
	# walked, so there is no move to follow up with an attack.
	if _move_settles_the_turn():
		_last_move_text = "NO MOVEMENT LEFT — TURN ENDED"
		queue_redraw()
		turn_manager.complete_player_turn()
		return
	if not player.can_move_to(cell):
		_last_move_text = "CANNOT MOVE THERE — beyond the movement range"
		queue_redraw()
		return
	player.try_move_to(cell)


## True when the hero has no movement points left and the turn's action is therefore
## the only thing still open — the moment a manual turn settles itself instead of
## waiting for another input. Called from BOTH movement seams: the end of a walk
## (_on_player_moved) and a move click with an empty tank (_click_move_to), which is
## the state a turn starts in when the hero's stats grant no movement.
##
## A cleared stage's free roam spends no points and is exempt exactly like its
## movement gates are, and an out-of-turn or movement-locked hero still refuses
## rather than settling a turn the player does not own.
##
## AUTO is exempt too: it walks the hero and attacks in the SAME turn, so settling the
## turn on the last step of its walk would cancel the attack it walked there for.
## AUTO settles its own turn.
func _move_settles_the_turn() -> bool:
	if player == null or turn_manager == null:
		return false
	if turn_manager.get_phase() != TurnState.PLAYER_TURN:
		return false
	if player.is_free_moving() or not player.is_input_enabled():
		return false
	if auto_combat != null and auto_combat.is_auto_enabled():
		return false
	return player.movement_points_remaining <= 0


## The turn's action once the movement is spent: an enemy in reach is struck, and
## with nothing in reach the turn simply ends. The strike goes out through the same
## `attack_requested` seam the ATTACK button and an enemy click use, so damage,
## presentation and the end of the turn behave exactly as they do for a manual
## attack.
func _settle_action_after_move() -> void:
	var target: EnemyController = _reachable_attack_target()
	if target == null:
		_last_move_text = "NO MOVEMENT LEFT — TURN ENDED"
		queue_redraw()
		turn_manager.complete_player_turn()
		return
	player.set_target(target)
	_last_move_text = "NO MOVEMENT LEFT — ATTACKING %s" % target.get_display_name().to_upper()
	queue_redraw()
	player.attack_requested.emit(player, target)


## The enemy the auto-attack after a move strikes: the player's CURRENT target when it
## is alive and inside the attack range (clicking an enemy selects it as the target),
## otherwise the closest living enemy in range. Null when nothing is in reach, or when
## the turn's action is no longer the player's to spend.
##
## Reachability is CombatSystem.can_attack — the ONE attack-range rule the ATTACK
## button, the enemy click and AUTO already share — so the automatic strike can never
## disagree with a manual one about what is hittable.
func _reachable_attack_target() -> EnemyController:
	if not turn_manager.is_action_available(player):
		return null
	var selected := player.get_target() as EnemyController
	if _can_strike(selected):
		return selected
	var best: EnemyController = null
	var best_distance: int = 0
	for enemy_node in _active_enemies:
		var enemy := enemy_node as EnemyController
		if not _can_strike(enemy):
			continue
		var distance: int = _cell_distance(player.grid_position, enemy.grid_position)
		if best == null or distance < best_distance:
			best = enemy
			best_distance = distance
	return best


func _can_strike(enemy: EnemyController) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_defeated():
		return false
	return combat_system.can_attack(player, enemy)


func _cell_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


func _get_living_enemy_at(cell: Vector2i) -> EnemyController:
	for enemy_node in _active_enemies:
		var enemy := enemy_node as EnemyController
		if enemy == null or not is_instance_valid(enemy) or enemy.is_defeated():
			continue
		if enemy.grid_position == cell:
			return enemy
	return null


func _on_hud_attack_requested() -> void:
	if turn_manager.get_phase() != TurnState.PLAYER_TURN or not player.is_input_enabled():
		return
	player.attack_requested.emit(player, player.get_target())


func _on_hud_skill_requested(skill_id: StringName) -> void:
	if turn_manager.get_phase() != TurnState.PLAYER_TURN or not player.is_input_enabled():
		return
	player.skill_requested.emit(player, player.get_target(), skill_id)


func can_use_skill(skill_id: StringName) -> bool:
	if player == null or combat_system == null:
		return false
	return combat_system.can_use_skill(player, skill_id, player.get_target())


func _on_hud_item_requested() -> void:
	if turn_manager.get_phase() != TurnState.PLAYER_TURN or not player.is_input_enabled():
		return
	if player.use_healing_item():
		_last_move_text = "Used healing item"
		turn_manager.complete_player_turn()
		queue_redraw()


func _on_hud_end_turn_requested() -> void:
	if turn_manager.get_phase() == TurnState.PLAYER_TURN:
		turn_manager.complete_player_turn()


func _on_hud_next_stage_requested() -> void:
	if _advance_after_clear():
		get_viewport().set_input_as_handled()


## THE single advance seam. Both the manual NEXT STAGE button / primary action and
## AUTO (via AutoCombatController.stage_advance_requested) end up here, so the two
## paths cannot drift apart. That drift was the bug this replaces: AUTO used to
## call StageManager.start_next_stage() directly, bypassing the host entirely, so
## an AUTO clear and a manual clear behaved differently.
##
## Advancing is always "the battle moves one stage on". The game is primarily
## endless, so a cleared stage continues to the next battle and the world map is
## an always-available status view / shortcut rather than a hub the player is
## forced back to after every clear.
##
## Automation is NOT consulted, so an AUTO clear and a manual clear produce the
## same result. FARMING is the single deliberate exception: it means "stay on this
## stage", so it keeps the player from advancing at all — that is a chosen mode,
## not automation changing an outcome.
##
## The gate also admits one NON-cleared case — a stage the player walked back into
## whose next stage is already cleared — and the move itself is identical, so both
## cases still leave through this one seam (see _can_advance_to_next_stage).
func _advance_after_clear() -> bool:
	if not _can_advance_to_next_stage():
		return false
	return stage_manager.start_next_stage()


## AUTO reached the exit of a cleared stage and asked to move on. Routed into the
## same seam as the manual press; the outcome is reported back so AUTO can stop
## when the next stage could not start.
func _on_auto_stage_advance_requested() -> void:
	auto_combat.notify_advance_result(_advance_after_clear())


func _player_is_on_stage_exit() -> bool:
	if player == null or stage_manager == null:
		return false
	if not stage_manager.has_method("get_stage_exit_cell"):
		return false
	return player.get_grid_position() == stage_manager.get_stage_exit_cell()


## The classic gate: this stage has been fully cleared.
func _is_current_stage_cleared() -> bool:
	if stage_manager == null or stage_manager.stage_state == null:
		return false
	return turn_manager.get_phase() == TurnState.VICTORY and stage_manager.stage_state.is_complete


## True when the stage AFTER this one is already cleared, i.e. the player is
## standing on a replay of content that is already done. Reads the progress rule
## through the flow instead of keeping a second copy of it, and does not depend on
## whose turn it is — the "the exit is open" status hint needs it mid-fight too.
func _next_stage_is_cleared() -> bool:
	if _flow == null or stage_manager == null or stage_manager.stage_state == null:
		return false
	return _flow.is_next_stage_cleared(stage_manager.stage_state.stage_number)


## True when this stage may be left through the Next Stage Point WITHOUT being
## cleared, because the stage after it is already cleared.
##
## The player is free to walk back into an already-cleared stage (from the world
## map, or a defeat that pushed them back); walking back OUT of it must not demand
## the fight again, so the exit opens during the player's own turn even with
## enemies still standing. The fight is simply abandoned: the skipped stage is NOT
## recorded as cleared, and the next stage was already recorded when it was played.
##
## Deliberately narrow, and a complete answer on its own: the player's own turn
## (never the enemy turn — a resolution is in flight — and never after a defeat),
## the next stage already cleared, and neither mode that pins the battle down
## (AUTO fights the stage it stands on; FARMING means "stay on this stage").
##
## Public because the HUD's NEXT STAGE button needs the exact same answer as the
## gate below; a second copy of the rule in the HUD is what would drift.
func can_leave_stage_uncleared() -> bool:
	if turn_manager.get_phase() != TurnState.PLAYER_TURN:
		return false
	if auto_combat != null and (auto_combat.is_auto_enabled() or auto_combat.is_farming_enabled()):
		return false
	return _next_stage_is_cleared()


## True when the player may leave this stage through the exit RIGHT NOW: either a
## full clear with the hero standing on the exit cell, or the replay skip above.
func _can_advance_to_next_stage() -> bool:
	if stage_manager.stage_state == null or auto_combat.is_farming_enabled():
		return false
	if not _player_is_on_stage_exit():
		return false
	return _is_current_stage_cleared() or can_leave_stage_uncleared()


# ---------------------------------------------------------------------------
# Authored-stage HOST + WorldMap HOST.
# The scene resolves an authored stage through StageFlow (stage_type driven,
# never stage-number hard-coded) and starts the matching gameplay: COMBAT/BOSS ->
# battle via the existing StageManager, TOWN -> the town view. It also hosts the
# world map: it feeds PlayerProgress into the view, toggles it, and routes stage
# clicks through the same entry with the flow's unlock gate. The rules themselves
# live in StageFlow; this section only performs them.
# ---------------------------------------------------------------------------

## The map / area progress object this scene displays and the flow advances.
## Public so tests and later wiring can read the current position.
func get_stage_progress() -> PlayerProgress:
	return _flow.get_progress() if _flow != null else null


## The player-side progress save this scene owns (Phase 8): the object holding the
## progress and the consumed-content state that were restored on boot and that every
## progress change is written back to. Public so tests, and later save-slot UI, can
## reach it without poking private fields.
func get_stage_save() -> StageProgressSave:
	return _stage_save


## Requests entry to an authored stage by its GLOBAL stage number, e.g.
## enter_area_stage(8). The area is derived from the number by the flow, so
## there is no area argument to get wrong. Returns true when the stage is
## authored and its gameplay has been started. Returns false (with a status
## message) for un-authored / out-of-range numbers. `from_world_map` marks an
## entry clicked on the world map, so a town visit opened from the map closes
## back to the refreshed map.
func enter_area_stage(stage_number: int, from_world_map: bool = false) -> bool:
	if _flow == null:
		return false
	if _flow.request_enter(stage_number, from_world_map):
		return true
	_last_move_text = _flow.get_entry_failure_reason(stage_number)
	queue_redraw()
	return false


## Forwarded from the HUD (DEV panel's AREA STAGES section).
func _on_hud_area_stage_enter_requested(stage_number: int) -> void:
	enter_area_stage(stage_number)


## Refreshes the WorldMapView against the live progress and shows it.
func open_world_map() -> bool:
	var progress: PlayerProgress = get_stage_progress()
	if progress == null:
		return false
	var map_view := hud.get_world_map_view()
	if map_view == null:
		return false
	map_view.set_progress(progress)
	map_view.refresh()
	hud.show_world_map()
	return true


## MAP button toggle: an open map closes back to the combat view; otherwise the
## map is (re)built from the current progress and shown.
func _on_hud_world_map_toggle_requested() -> void:
	var map_view := hud.get_world_map_view()
	if map_view != null and bool(map_view.visible):
		hud.show_combat()
	else:
		open_world_map()


## Stage clicks from the world map. Unlike the DEV panel (which intentionally
## bypasses lock gating for QA), the map only lets the player enter stages the
## linear progression has actually unlocked — the lock rule lives in
## PlayerProgress and is reached through the flow so map and flow share one rule.
func _on_world_map_stage_enter_requested(stage_number: int) -> void:
	if _flow != null and not _flow.is_stage_unlocked(stage_number):
		var area_id: StringName = StageDatabaseScript.area_for_stage(stage_number)
		_last_move_text = "AREA %s // STAGE %d LOCKED — CLEAR THE PREVIOUS STAGE FIRST" % [String(area_id).to_upper(), stage_number]
		queue_redraw()
		return
	enter_area_stage(stage_number, true)


# ---------------------------------------------------------------------------
# Completion / town-return HOST.
# The policy lives in StageFlow; this section only performs it. The authored loop
#   WorldMap → Stage → Gameplay → Complete (PlayerProgress) → unlock next →
#   next battle (or the map, whenever the player opens it)
# Completion depends only on the stage number resolved through the router /
# StageDatabase, and never on AUTO / FARMING, so automation cannot change a
# result.
#
# Position bookkeeping is NOT done here: the flow writes the position from
# StageManager.stage_started (forwarded in _on_stage_started below), which every
# stage-changing path reaches — boot, a map / DEV entry, an advance (AUTO and
# manual share one seam), a defeat fallback and a FARMING re-spawn. That single
# writer is why the stage bar, the map's HERE marker and PlayerProgress agree.
# ---------------------------------------------------------------------------

## Town close routed through the host: a town visit opened from the world map
## returns to the refreshed map (its completion was recorded on entry); every
## other close keeps restoring the combat view.
func _on_town_close_requested() -> void:
	var return_to_map: bool = _flow != null and _flow.on_town_closed()
	if return_to_map:
		_last_move_text = "BACK TO WORLD MAP — pick the next stage on the map"
		queue_redraw()
		open_world_map()
	elif hud != null:
		hud.show_combat()


## Dispatches one resolved authored stage into the matching gameplay. Connected to
## StageFlow.gameplay_requested, so any entry request lands here. The flow has
## already done the entry bookkeeping (current area / stage, visit completion);
## this method only opens the gameplay and converges the HUD onto its view, which
## also hides the world map when the entry came from a stage click on the map.
func _apply_stage_entry(route: Dictionary) -> void:
	if not bool(route.get("ok", false)):
		return
	var area_id: StringName = StringName(route.get("area_id", &""))
	var stage_number: int = int(route.get("stage_number", 0))
	var stage_id: String = str(route.get("stage_id", ""))
	var destination: int = int(route.get("destination", StageRouter.Destination.NONE))
	match destination:
		StageRouter.Destination.COMBAT:
			_start_battle_for_area_stage(stage_id, stage_number)
			hud.show_combat()
		StageRouter.Destination.TOWN:
			# Entering a town stage IS the visit: the flow already recorded the
			# clear (so the linear chain can move past it) and resolved the
			# authored "what's next" text.
			_last_move_text = "AREA %s // TOWN STAGE %02d VISITED — %s" % [
				String(area_id).to_upper(),
				stage_number,
				str(route.get("next_text", "")),
			]
			hud.show_town()
		_:
			_last_move_text = "AREA %s // no gameplay destination yet" % stage_id
			hud.show_combat()
	queue_redraw()


## Starts a battle for an authored COMBAT/BOSS stage. The battle level defaults to
## the authored stage number (Forest 01..10 <-> battle level 1..10); an authored
## override can later be read from StageData.combat_data here without touching
## callers or the routing table.
func _start_battle_for_area_stage(stage_id: String, stage_number: int) -> bool:
	_last_move_text = "AREA %s // COMBAT begins" % stage_id
	if stage_manager == null:
		return false
	return stage_manager.initialize_stage(maxi(stage_number, 1))


func _refresh_arena_markers() -> void:
	if grid == null or stage_manager == null or not stage_manager.has_method("get_stage_exit_cell"):
		return
	if grid.has_method("set_arena_marker"):
		grid.set_arena_marker(stage_manager.get_stage_exit_cell(), Color("e0c06a"))
		grid.set_arena_marker(stage_manager.get_stage_start_cell(), Color("8fb3b7"))


func _on_hud_auto_toggle_requested() -> void:
	auto_combat.toggle_auto()


func _on_hud_farming_toggle_requested() -> void:
	auto_combat.toggle_farming()


func _on_hud_game_speed_requested(speed: int) -> void:
	auto_combat.set_game_speed(speed)


func _on_game_speed_changed(speed: int) -> void:
	hud.set_game_speed(speed)
	_last_move_text = "GAME SPEED %s" % auto_combat.get_game_speed_label()
	queue_redraw()


func _on_auto_mode_changed(enabled: bool) -> void:
	hud.set_auto_mode(enabled)
	_last_move_text = "AUTO MODE %s" % ("ENABLED" if enabled else "DISABLED")
	queue_redraw()


func _on_farming_changed(enabled: bool) -> void:
	hud.set_farming_mode(enabled)
	_last_move_text = "FARMING ON — STAY & REFRESH THIS STAGE" if enabled else "FARMING OFF — NEXT STAGE AFTER CLEAR"
	queue_redraw()


func _on_auto_action_taken(description: String) -> void:
	if not description.is_empty():
		_last_move_text = description
		queue_redraw()


func _on_viewport_size_changed() -> void:
	_layout_portrait_grid()
	queue_redraw()


func _layout_portrait_grid() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var combat_rect: Rect2 = hud.get_combat_section_rect()
	if combat_rect.size.x <= 0.0 or combat_rect.size.y <= 0.0:
		return
	var background_size: Vector2 = dungeon_background.texture.get_size()
	dungeon_background.position = viewport_size * 0.5
	dungeon_background.scale = Vector2.ONE * maxf(
		viewport_size.x / background_size.x,
		viewport_size.y / background_size.y
	)
	# The battlefield spans the full screen width up to MAX_GRID_WIDTH and hugs
	# the combat area's left edge. Cell size is driven by that width, but never
	# grows past what fits vertically so the grid cannot overlap the HUD below.
	var target_width: float = minf(viewport_size.x, MAX_GRID_WIDTH)
	var cell_size: int = maxi(floori(minf(
		target_width / float(grid.grid_size.x),
		combat_rect.size.y / float(grid.grid_size.y)
	)), 1)
	var grid_pixel_size := Vector2(grid.grid_size * cell_size)
	grid.cell_size = cell_size
	grid.origin = Vector2(
		combat_rect.position.x,
		combat_rect.position.y + (combat_rect.size.y - grid_pixel_size.y) * 0.5
	)
	_grid_play_area = Rect2(grid.origin - Vector2(8.0, 8.0), grid_pixel_size + Vector2(16.0, 16.0))
	grid.queue_redraw()
	player.global_position = grid.grid_to_world(player.grid_position)
	for enemy_node in _active_enemies:
		var enemy := enemy_node as EnemyController
		if enemy != null and is_instance_valid(enemy):
			enemy.global_position = grid.grid_to_world(enemy.grid_position)
	# Units were teleported; clear residual presentation-token offsets.
	combat_presentation.notify_layout_changed()


## CombatSection is a Control that only receives its real size after the first
## container sort, which runs after _ready. Retry the layout for a few frames
## until the battlefield rect is measurable, so the grid does not stay stuck on
## its editor defaults (the viewport never resizes on a fixed-size phone).
func _relayout_when_combat_ready() -> void:
	var attempts: int = 0
	while attempts < 10:
		await get_tree().process_frame
		if hud == null or not is_instance_valid(self):
			return
		if hud.get_combat_section_rect().size.y > 0.0:
			_layout_portrait_grid()
			return
		attempts += 1
	_layout_portrait_grid()


func _on_stage_started(stage_state: StageState, enemies: Array[Node]) -> void:
	# THE single position writer: every stage-changing path reaches
	# StageManager.initialize_stage() -> stage_started, so forwarding it here keeps
	# PlayerProgress, the stage bar and the world map's HERE marker on one number.
	if _flow != null:
		_flow.on_stage_started(stage_state.stage_number)
	player.set_free_movement(false)
	# Every stage generation (defeat retreat included) frees the enemies whose swing
	# was still animating, so their strike lock is dropped here before the new turn
	# starts: the hero must be fully playable on a fresh arena.
	combat_presentation.reset_enemy_attack_presentation()
	_active_enemies = enemies
	for enemy_node in _active_enemies:
		_register_enemy(enemy_node as EnemyController)
	if not _active_enemies.is_empty():
		player.set_target(_active_enemies[0])
	combat_system.set_combat_targets(_active_enemies)
	turn_manager.start_combat(player, _active_enemies)
	_sync_sub_hero_combatants()
	sub_hero_combat_manager.start_combat(_active_enemies)
	var encounter_label: String = "MINI BOSS" if stage_state.is_mini_boss_stage else "NORMAL"
	if stage_state.is_special_encounter:
		encounter_label = SpecialEncounterTypeResource.get_display_name(stage_state.special_encounter_type).to_upper()
	_last_move_text = "%s // %s started" % [stage_manager.current_definition.display_name, encounter_label]
	if _next_stage_is_cleared():
		# Replaying a stage whose next stage is already cleared: the exit is open
		# without a fight, so say it up front instead of letting the player assume
		# the whole stage has to be played again.
		_last_move_text += " · STAGE %02d ALREADY CLEARED — THE EXIT IS OPEN" % (stage_state.stage_number + 1)
	# Authored content appears whenever the stage starts, however the player got
	# here (map click, previous-stage exit, or the endless loop). Stages that
	# author nothing are left untouched — they are plain normal stages.
	if _stage_content != null:
		_stage_content.spawn_for_stage(stage_state.stage_number)
	hud.log_event("log.stage_start", {"stage": stage_state.stage_number})
	queue_redraw()


## Reports what authored content did, e.g. "CACHE — 120 GOLD + Vicious Blade".
func _on_stage_content_resolved(description: String) -> void:
	if description.is_empty():
		return
	_last_move_text = description
	queue_redraw()


func _on_enemy_spawned(enemy: Node) -> void:
	var enemy_controller := enemy as EnemyController
	if enemy_controller == null:
		return
	_active_enemies.append(enemy_controller)
	_register_enemy(enemy_controller)
	combat_system.set_combat_targets(_active_enemies)
	turn_manager.add_enemy(enemy_controller)
	sub_hero_combat_manager.add_enemy(enemy_controller)
	_last_move_text = "%s summoned" % enemy_controller.get_display_name()
	hud.log_event("log.enemy_summoned", {"name": enemy_controller.get_display_name()})
	queue_redraw()


func _register_enemy(enemy: EnemyController) -> void:
	if enemy == null:
		return
	combat_system.connect_actor(enemy)
	if enemy.has_signal("moved") and not enemy.moved.is_connected(_on_enemy_moved):
		enemy.moved.connect(_on_enemy_moved)
	if enemy.has_signal("attack_requested") and not enemy.attack_requested.is_connected(_on_enemy_attack_requested):
		enemy.attack_requested.connect(_on_enemy_attack_requested)


func _on_stage_completed(stage_state: StageState) -> void:
	sub_hero_combat_manager.stop_combat()
	# An authored battle that clears records the completion in the flow (policy)
	# and reports the authored "what's next"; a clear with no authored stage to
	# advance returns "" and keeps the classic endless text below. AUTO / FARMING
	# are not consulted here, so the recorded result never depends on automation.
	var authored_next: String = _flow.on_battle_cleared(stage_state.stage_number) if _flow != null else ""
	if authored_next.is_empty():
		if auto_combat.is_farming_enabled():
			_last_move_text = "STAGE %d CLEARED — FARMING STAYS ON STAGE" % stage_state.stage_number
		else:
			# Free roam lets the player walk to the right exit cell to advance.
			player.set_free_movement(true)
			_last_move_text = "STAGE %d CLEARED — REACH THE RIGHT EXIT TO ADVANCE" % stage_state.stage_number
	else:
		var area_label: String = String(_flow.get_current_area_id()).to_upper()
		if auto_combat.is_farming_enabled():
			_last_move_text = "AREA %s // STAGE %02d CLEARED — %s · FARMING STAYS ON STAGE" % [
				area_label,
				stage_state.stage_number,
				authored_next,
			]
		else:
			# Free roam lets the player walk to the right exit cell; the exit /
			# NEXT STAGE press then moves the endless loop one stage on.
			player.set_free_movement(true)
			_last_move_text = "AREA %s // STAGE %02d CLEARED — %s · REACH THE EXIT / PRESS NEXT TO CONTINUE" % [
				area_label,
				stage_state.stage_number,
				authored_next,
			]
	hud.log_event("log.stage_clear", {"stage": stage_state.stage_number})
	turn_manager.set_victory()
	queue_redraw()


func _on_stage_generation_failed(stage_number: int, reason: String) -> void:
	_last_move_text = "Stage %d failed: %s" % [stage_number, reason]
	queue_redraw()


func _on_player_moved(from_cell: Vector2i, to_cell: Vector2i, points_remaining: int) -> void:
	_last_move_text = "Moved %s → %s" % [from_cell, to_cell]
	if _player_is_on_stage_exit():
		if _is_current_stage_cleared():
			_last_move_text = "ON THE EXIT — NEXT STAGE READY"
		elif can_leave_stage_uncleared():
			_last_move_text = "ON THE EXIT — NEXT STAGE READY (STAGE %02d ALREADY CLEARED)" % (
				stage_manager.stage_state.stage_number + 1
			)
	# Every movement path — click-to-move, the D-pad and the keyboard arrows — ends
	# in this signal, so a walk that spends the turn's last movement point settles the
	# turn here: strike a reachable enemy, or simply be done. Either way the player
	# never has to click again to finish the turn.
	if _move_settles_the_turn():
		_settle_action_after_move()
		return
	queue_redraw()


func _on_enemy_moved(from_cell: Vector2i, to_cell: Vector2i) -> void:
	_last_move_text = "Enemy moved %s → %s" % [from_cell, to_cell]
	queue_redraw()


func _on_enemy_attack_requested(_enemy: EnemyController, _target: Node) -> void:
	_last_move_text = "Enemy attack requested"
	queue_redraw()


## An enemy attack animation started/finished. Movement (never acting from the
## current cell) is held until it has completely finished.
func _on_enemy_attack_presentation_changed(active: bool) -> void:
	player.set_movement_locked(active)
	if active:
		_last_move_text = "Enemy attack — movement locked until it finishes"
		queue_redraw()


func _on_attack_resolved(result: DamageResult) -> void:
	if result.is_miss:
		_last_move_text = "Attack missed: target out of range"
	else:
		_last_move_text = "Critical hit for %d" % result.final_damage if result.is_critical else "Hit for %d" % result.final_damage
		if result.is_critical:
			hud.show_critical_indicator(result.final_damage)
	queue_redraw()


func _on_skill_resolved(skill_id: StringName, hit_count: int) -> void:
	var skill := SkillCatalog.get_skill(skill_id)
	_last_move_text = "%s hit %d target%s" % [skill.display_name, hit_count, "" if hit_count == 1 else "s"]
	queue_redraw()


func _on_skill_failed(skill_id: StringName, reason: String) -> void:
	var skill := SkillCatalog.get_skill(skill_id)
	_last_move_text = "%s unavailable: %s" % [skill.display_name, reason]
	queue_redraw()


func _on_experience_awarded(amount: int, _current_experience: int, _required_experience: int, source_name: String) -> void:
	_last_move_text = "Gained %d EXP%s" % [amount, " from %s" % source_name if not source_name.is_empty() else ""]
	queue_redraw()


func _on_level_up(new_level: int, _max_hp_gain: int, _attack_gain: int, _defense_gain: int) -> void:
	_last_move_text = "LEVEL UP — Player reached level %d" % new_level
	hud.log_event("log.level_up", {"level": new_level})
	queue_redraw()


func _on_gold_awarded(amount: int, _current_gold: int, source_name: String) -> void:
	_last_move_text = "Gained %d Gold%s" % [amount, " from %s" % source_name if not source_name.is_empty() else ""]
	hud.log_event("log.gold_gained", {"amount": amount})
	queue_redraw()


func _on_loot_dropped(_enemy: Node, loot: Array[EquipmentInstance]) -> void:
	var loot_names: Array[String] = []
	var new_best_items: Array[EquipmentInstance] = []
	var added_count: int = 0
	var stowed_count: int = 0
	for item in loot:
		if item == null:
			continue
		loot_names.append(item.get_display_name())
		var comparison: EquipmentComparison = player.get_inventory().create_comparison(item)
		var is_upgrade: bool = comparison != null and comparison.is_upgrade()
		if player.add_equipment(item):
			added_count += 1
		elif player.add_to_storage(item):
			stowed_count += 1
		else:
			continue
		if is_upgrade:
			new_best_items.append(item)
	var inventory: EquipmentInventory = player.get_inventory()
	if added_count + stowed_count == loot.size():
		_last_move_text = "Loot added: %s (%d/%d)" % [", ".join(loot_names), inventory.get_item_count(), inventory.capacity]
	else:
		_last_move_text = "Loot added %d/%d — bag full" % [added_count + stowed_count, loot.size()]
	if stowed_count > 0:
		_last_move_text += "  (%d stored)" % stowed_count
	if not loot_names.is_empty():
		hud.log_event("log.loot_found", {"items": ", ".join(loot_names)})
	hud.present_loot(loot, new_best_items, str(_enemy.get("enemy_id")) if _enemy != null else "")
	queue_redraw()


func _on_equipment_effect_triggered(_effect_id: StringName, description: String) -> void:
	_last_move_text = "EFFECT // %s" % description
	queue_redraw()


func _on_sub_hero_slots_changed() -> void:
	_sync_sub_hero_combatants()


func _sync_sub_hero_combatants() -> void:
	sub_hero_combat_manager.clear_active_sub_heroes()
	if player == null or not player.has_method("get_active_sub_hero_entries"):
		return
	for entry in player.get_active_sub_hero_entries():
		var data := entry.get("data") as SubHeroData
		var instance := entry.get("instance") as SubHeroInstance
		if data != null and instance != null:
			sub_hero_combat_manager.register_active_sub_hero(instance, data)
	if sub_hero_combat_manager.is_combat_running():
		sub_hero_combat_manager.start_combat(_active_enemies)


func _on_sub_hero_attack_resolved(result: DamageResult) -> void:
	if result == null or result.is_miss:
		return
	hud.show_sub_hero_attack_feedback(result.attacker_id, result.final_damage)
	_last_move_text = "Sub Hero hit for %d" % result.final_damage
	queue_redraw()


func _on_sub_hero_attack_feedback_requested(result: DamageResult, target: Node) -> void:
	if result == null or result.is_miss or target == null or not is_instance_valid(target) or not target is Node2D:
		return
	var origin: Vector2 = hud.get_sub_hero_attack_origin(result.attacker_id)
	var destination: Vector2 = (target as Node2D).get_global_transform_with_canvas().origin
	if origin == Vector2.ZERO:
		origin = destination + Vector2(0.0, 40.0)
	var effect := SubHeroAttackEffectResource.new()
	hud.add_child(effect)
	effect.setup(origin, destination)


func _on_sub_hero_cooldown_started(hero_id: StringName, duration: float) -> void:
	hud.start_sub_hero_cooldown(hero_id, duration)


func _on_sub_hero_combat_state_changed(is_running: bool) -> void:
	if is_running:
		hud.reset_sub_hero_cooldowns()


func _on_sub_hero_combat_cleared() -> void:
	stage_manager.complete_stage_if_cleared()


func _on_actor_died(actor: Node) -> void:
	if actor == player:
		sub_hero_combat_manager.stop_combat()
		player.set_free_movement(false)
		_last_move_text = "PLAYER DEFEATED"
		hud.log_event("log.player_defeated")
		turn_manager.set_defeat()
		if not _defeat_retry_scheduled:
			_defeat_retry_scheduled = true
			call_deferred("_retry_previous_stage_after_defeat")
	else:
		var enemy := actor as EnemyController
		_last_move_text = "Enemy defeated"
		if enemy != null:
			hud.log_event("log.kill_exp", {
				"name": enemy.get_display_name(),
				"amount": experience_system.calculate_enemy_experience(enemy),
			})
		_select_next_target()
	queue_redraw()


func _retry_previous_stage_after_defeat() -> void:
	_defeat_retry_scheduled = false
	if turn_manager.get_phase() != TurnState.DEFEAT or not player.is_defeated():
		return

	player.revive_for_retry()
	var retry_stage: int = maxi(stage_manager.stage_state.stage_number - 1, 1)
	if stage_manager.start_previous_stage():
		_last_move_text = "DEFEAT — RETURNED TO STAGE %02d" % retry_stage
	else:
		player.handle_defeat()
		_last_move_text = "DEFEAT — RETRY FAILED"
	queue_redraw()


func _select_next_target() -> void:
	for enemy_node in _active_enemies:
		var enemy := enemy_node as EnemyController
		if enemy != null and is_instance_valid(enemy) and not enemy.is_defeated():
			player.set_target(enemy)
			return


func _on_turn_state_changed(_state: TurnState) -> void:
	queue_redraw()


func _on_selection_changed(selected: bool) -> void:
	_last_move_text = "Player %s" % ("selected" if selected else "deselected")
	queue_redraw()


func _draw() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("090811"), true)
	draw_rect(Rect2(Vector2(10.0, 10.0), viewport_size - Vector2(20.0, 20.0)), Color("12101c"), true)
	draw_rect(Rect2(Vector2(10.0, 10.0), viewport_size - Vector2(20.0, 20.0)), Color("6c5331"), false, 2.0)
	if _grid_play_area.size.x > 0.0:
		draw_rect(_grid_play_area, Color("0b0a10", 0.92), true)
		draw_rect(_grid_play_area, Color("4d465e", 0.85), false, 1.0)


func _turn_label() -> String:
	if turn_manager == null:
		return "-"
	match turn_manager.get_phase():
		TurnState.PLAYER_TURN:
			return "PLAYER"
		TurnState.ENEMY_TURN:
			return "ENEMY"
		TurnState.VICTORY:
			return "VICTORY"
		TurnState.DEFEAT:
			return "DEFEAT"
		_:
			return "-"
