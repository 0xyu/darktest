# Auto Navigation & Grid Pathfinding

> **Status: IMPLEMENTED.** This document is the design brief that was reviewed
> against the codebase and then built. Where the review changed the brief, the
> section below is marked **`REVIEW:`** and the authoritative record of every
> deviation, file and test is in **§30 Implementation Record** at the end.
>
> Read §30 first if you are looking for what the build actually does.

## 1. Objective

Improve the player's grid movement system in the Godot 4.x turn-based RPG.

The new system must:

1. Automatically find an alternate route when the direct route is blocked.
2. Allow the player to click a destination outside the current movement range.
3. Automatically navigate toward the selected destination across multiple turns.
4. Treat enemies as dynamic obstacles.
5. If an enemy blocks the navigation route, prioritize dealing with that enemy before continuing navigation.
6. After the blocking enemy is defeated, recalculate the path and continue toward the original destination.
7. Preserve the current `Auto` and `Farming` states during navigation.
8. Show `"Auto Navigating"` while automatic navigation is active.
9. Preserve the existing movement animation, turn system, combat system, and existing gameplay behavior.

---

# 2. Recommended Technology

> **`REVIEW:` this section was REVERSED by the review. `AStarGrid2D` was NOT
> introduced.** The project already owns a grid with obstacles, occupancy and a
> pathfinder (`scripts/systems/grid_map_2d.gd`: `find_path`, `get_reachable_cells`,
> `is_walkable`, `is_occupied`, plus the arena's gate-lane rule). A second,
> `AStarGrid2D`-based walkability/occupancy source would duplicate exactly the
> "single source of truth for cell occupancy" this brief demands in §8, and would
> have to re-implement the gate-lane rule, the `blocked_cells` list and actor
> occupancy to stay in sync.
>
> Navigation therefore reuses `GridMap2D.find_path()` (a BFS over the same
> walkable/occupancy rules every existing walker — click-to-move, AUTO, the exit
> roam — already uses). One small, documented extension was added to it:
> `find_path(start, goal, ignored_occupied)` treats the named occupied cells as free
> **for that query only**, so navigation can prove that an ACTOR — and not the
> terrain — is what blocks a destination (see §8 and §30).

Do NOT introduce `NavigationAgent2D` for this grid-based turn-based movement system.

The game uses discrete grid cells, therefore a grid pathfinder is the right
mechanism — the grid one the project already has.

Conceptually (as implemented):

```text
GridMap2D
  ↓
find_path(start_cell, target_cell)      # occupancy- and wall-aware
  ↓
Array[Vector2i]                         # inclusive of both ends
  ↓
Move one grid cell at a time
```

---

# 3. Architecture

Do not put all pathfinding logic directly into the Player script.

Use a dedicated navigation responsibility.

Recommended architecture:

```text
Stage / Grid Manager
│
├── AStarGrid2D
├── Static Obstacles
└── Dynamic Obstacles
     ├── Enemy
     ├── NPC
     └── Other blocking entities
     
Player
│
├── MovementController
├── CombatController
└── NavigationController
```

If the current project architecture uses different names, follow the existing architecture instead of introducing unnecessary new abstractions.

The important responsibility separation is:

### Movement

Responsible for:

* Moving the player one cell.
* Movement points.
* Movement animation.
* Valid movement.
* Turn movement consumption.

### Combat

Responsible for:

* Attack.
* Attack range.
* Damage.
* Enemy death.
* Combat turn handling.

### Navigation

Responsible for:

* Navigation target.
* Pathfinding.
* Path recalculation.
* Detecting blockers.
* Resuming navigation.
* Cancelling navigation.
* Automatic navigation state.

Do not duplicate movement or combat logic inside the navigation system.

---

# 4. Navigation Target

Add a persistent navigation target.

Example:

```gdscript
var navigation_target: Vector2i
var is_navigating: bool
```

The exact implementation should follow the existing project architecture.

When the player clicks a valid destination:

```text
Set navigation target
        ↓
Calculate path
        ↓
Start automatic navigation
```

The destination should remain stored while navigating.

The navigation target must NOT be limited to the player's current movement range.

For example:

```text
Player
  ↓
Current movement range = 3 cells

Target = 10 cells away
```

The target is still valid.

The player should automatically move toward it over multiple turns.

---

# 5. Player Clicking Outside Current Movement Range

Current behavior may only allow clicking cells inside the current movement range.

Change this behavior.

The player should be able to click a reachable destination outside the current movement range.

Example:

```text
P . . . . . . . . T
```

If the player only has 3 movement points:

```text
P → → →
```

The player stops when movement points are exhausted.

The target remains:

```text
T
```

At the next turn:

```text
P → → → ...
```

Navigation continues automatically.

The player should NOT need to click the destination again.

---

# 6. Pathfinding

Use `AStarGrid2D`.

The pathfinding system should calculate a path from:

```text
player_cell
```

to:

```text
navigation_target
```

Example:

```text
P . . X . . T
. . . X . . .
. . . . . . .
```

The direct route is blocked.

A* should find:

```text
P
↓
↓
→
→
↑
→ T
```

instead of failing simply because the direct route is blocked.

---

# 7. Static Obstacles

Static terrain obstacles must be represented in the A* grid.

Examples:

* Walls
* Unusable cells
* Permanent terrain obstacles
* Other cells that cannot ever be entered

These should be marked as solid/unwalkable in `AStarGrid2D`.

Example conceptual state:

```text
Walkable:
. . . . .

Blocked:
X X X X X
```

Static obstacles should not require path recalculation unless the stage/grid itself changes.

---

# 8. Dynamic Obstacles

Enemies and other dynamic entities should be handled separately from permanent terrain.

Examples:

```text
Enemy
NPC
Companion
Summon
Other blocking entity
```

Do not permanently modify the static A* grid whenever an enemy moves.

The navigation system must account for dynamic blockers at runtime.

Recommended approach:

```text
AStarGrid2D
     ↓
Calculate candidate path
     ↓
Check dynamic blockers
     ↓
Validate path
     ↓
Move
```

If the project architecture already has a reliable occupancy/grid system, reuse it.

Do not create a second independent source of truth for cell occupancy.

---

# 9. Enemy Blocking Navigation

An enemy blocking the path must NOT simply cause navigation to fail permanently.

Example:

```text
P → → E → → → T
```

Where:

```text
E = Enemy
```

The navigation system should identify the enemy as a dynamic blocker.

Then determine whether the enemy can be handled.

The preferred behavior is:

```text
Player
  ↓
Navigation path
  ↓
Enemy blocks route
  ↓
Can move toward enemy?
  ↓
Yes
  ↓
Move toward enemy
  ↓
Enter attack range
  ↓
Attack enemy
  ↓
Enemy defeated
  ↓
Recalculate path
  ↓
Continue toward original target
```

---

# 10. Enemy Blocker Handling

When an enemy blocks the current path:

## Case A: Enemy is already in attack range

Attack the blocking enemy.

```text
P E → → T
```

Player:

```text
Attack E
```

After the enemy dies:

```text
P → → → T
```

Recalculate the path.

---

## Case B: Enemy is not yet in attack range

The player should move toward the enemy if a valid path exists.

Example:

```text
P . . E . . T
```

The player should navigate toward the enemy:

```text
P → → E
```

Once the player enters attack range:

```text
Attack E
```

After the enemy dies:

```text
Recalculate path to T
```

Then continue navigation.

---

## Case C: Enemy cannot be reached

If the enemy cannot be reached because of terrain or other blockers:

```text
P . X E . T
```

Do not blindly attack or move into an invalid cell.

The navigation system should:

1. Recalculate the path.
2. Look for an alternate route around the enemy.
3. If an alternate route exists, use it.
4. If no route exists, stop navigation safely.

---

# 11. Priority Rules

When an enemy is encountered during automatic navigation:

```text
1. Check whether an alternate valid path exists.
2. If the enemy is the meaningful blocker on the selected route:
      Handle the enemy.
3. If the enemy can be bypassed:
      Prefer bypassing when appropriate.
4. If the enemy blocks all viable routes:
      Move toward / attack the enemy.
5. After enemy death:
      Recalculate the path.
6. Resume original navigation target.
```

Do not permanently replace the player's original navigation target with the enemy.

The enemy is an intermediate blocker.

Example:

```text
Original target = Stage 7

Enemy = intermediate blocker

Enemy dies

Navigation target must still be Stage 7.
```

---

# 12. Navigation State

Navigation should have an explicit state.

> **`REVIEW:` the seven-state list was trimmed to the states that actually change
> behaviour.** `MOVING_TO_BLOCKER` and `ATTACKING_BLOCKER` are not separate states in
> this architecture: walking toward a blocker IS the ordinary walk (same pathfinder,
> same step), and which enemy is being dealt with is reported by `get_blocker()`.
> `BLOCKED` is not sticky either — the walk is either being pursued or it has stopped.
> Inventing states with identical behaviour would be speculative.

Implemented states:

```text
NONE        -- no destination
NAVIGATING  -- a destination is being walked to (get_blocker() says why, if blocked)
COMPLETED   -- the hero arrived (terminal)
CANCELLED   -- the walk stopped for any other reason (terminal)
```

The exact enum/state implementation should follow the existing project architecture.
It does: `NavigationController.State`, modelled on `TurnState`.

Important:

`Auto` and `Farming` are NOT navigation states.

They are independent systems.

Example:

```text
Auto Mode      = ON
Farming Mode   = ON
Navigation     = NAVIGATING
```

Starting navigation must not disable or reset either `Auto` or `Farming`.

---

# 13. "Auto Navigating" UI

While automatic navigation is active, display:

```text
AUTO NAVIGATING
```

> **`REVIEW:` the wording is uppercased to match the HUD.** Every other battle
> indicator is uppercase (`AUTO: ON`, `FARMING: OFF`, `VICTORY`), so the mixed-case
> `Auto Navigating` of this brief would be the only sentence-case label on screen.
>
> **`REVIEW:` the indicator is a label, not a banner.** It is built in code by
> `CombatActions` and placed under the AUTO / FARMING buttons — the cluster whose
> state it reports — instead of a scene node or a center-screen banner (which would
> cover the battlefield and collide with the VICTORY / DEFEAT banner).

The indicator should remain visible while the player is automatically navigating toward the selected destination.

Suggested lifecycle:

```text
Player clicks destination
        ↓
NAVIGATING
        ↓
Show "Auto Navigating"
        ↓
Move / handle blockers
        ↓
Destination reached
        ↓
Hide "Auto Navigating"
```

If navigation is cancelled:

```text
Hide "Auto Navigating"
```

Do not change the existing Auto/Farming UI state.

---

# 14. Turn-Based Movement

This is critical.

Automatic navigation must respect the existing movement-point system.

It must NOT give the player unlimited movement.

Example:

```text
Navigation path:

P → → → → → → → T
```

Current turn:

```text
Movement Points = 3
```

The player moves:

```text
P → → →
```

Then:

```text
Movement Points = 0
```

The player must follow the existing turn-end behavior.

At the next turn:

```text
Recalculate path
Continue toward T
```

Do not assume the previously calculated path is still valid.

---

# 15. Recalculate Path Frequently

The path should be recalculated whenever the environment can have changed.

At minimum:

```text
After player movement
After enemy movement
After enemy death
After entering a new turn
After a dynamic blocker changes position
After the navigation target changes
```

Do not blindly reuse a stale path.

Example:

```text
Turn 1:

P → → E → T

Enemy moves

Turn 2:

P → → . E → T
```

The navigation system must recalculate.

---

# 16. One-Cell-at-a-Time Movement

The existing player movement animation must remain compatible.

Navigation should request:

```text
Move to next cell
```

rather than teleporting the player to the destination.

Example:

```text
Path:

(2,4)
(3,4)
(4,4)
(4,5)
(4,6)
```

Movement:

```text
(2,4)
 ↓
(3,4)
 ↓
(4,4)
 ↓
(4,5)
 ↓
(4,6)
```

Each cell transition should use the existing player movement implementation and animation.

Do not create a separate movement animation system for navigation.

---

# 17. Interaction With Existing Combat

Do not duplicate combat logic.

When navigation determines that the player needs to attack an enemy, call the existing combat/attack flow.

Conceptually:

```text
NavigationController
        ↓
request_attack(enemy)
        ↓
Existing CombatController
        ↓
Attack
        ↓
Enemy dies
        ↓
NavigationController notified
        ↓
Recalculate path
```

Do not implement damage, EXP, loot, enemy death, or turn-resolution logic inside `NavigationController`.

This is especially important because the existing game already has combat, loot, EXP, and turn logic.

---

# 18. Navigation Completion

Navigation is complete when:

```text
player_cell == navigation_target
```

Then:

```text
is_navigating = false
navigation_target = invalid
navigation_state = COMPLETED
```

Hide:

```text
Auto Navigating
```

Do not automatically change:

```text
Auto Mode
Farming Mode
```

---

# 19. Navigation Cancellation

Navigation should be cancelled when appropriate.

Examples:

* Player manually chooses another destination.
* Player performs an action that invalidates navigation.
* Stage changes.
* Player enters a state where movement is impossible.
* Existing game logic explicitly cancels movement.

When cancelled:

```text
navigation_target = invalid
is_navigating = false
```

Do not accidentally disable Auto/Farming unless existing game rules explicitly require it.

---

# 20. Manual Input Priority

Manual player input should have priority over automatic navigation when appropriate.

For example:

```text
Player is Auto Navigating
        ↓
Player manually selects another destination
        ↓
Cancel current navigation
        ↓
Set new navigation target
        ↓
Start new path
```

Do not allow two navigation commands to run simultaneously.

There must only be one active navigation target at a time.

---

# 21. Pathfinding Failure

If no valid path exists:

```text
find_path() returns empty
```

The navigation system should stop safely.

> **`REVIEW:` "no path" is not one case but four, and they must not read the same.**
> The implemented stop reasons are reported by `navigation_finished(reason)` and
> turned into an on-screen message by the combat host:
>
> ```text
> arrived        the hero reached the destination (COMPLETED)
> no_route       terrain alone blocks it, or an actor blocks it and cannot be reached
> no_movement    the hero's stats grant no movement points at all
> stage_changed  a new arena was built (a stage change invalidates the walk)
> defeat         the hero fell
> cancelled      the player stopped the walk (a tap on the hero's own cell)
> ```

Expected behavior:

```text
Navigation failed
        ↓
Stop automatic navigation
        ↓
Clear navigation target
        ↓
Hide "AUTO NAVIGATING"
```

Do not crash.

Do not repeatedly calculate the same impossible path every frame.

> **`REVIEW:` a walk with no route stops on the FIRST attempt** — it is not retried
> per turn — because `_advance()` is event-driven and the failing recalculation ends
> the navigation session instead of leaving it armed (see §22).

---

# 22. Avoid Per-Frame Pathfinding

Do not run A* every frame.

Bad:

```gdscript
func _process(delta):
    calculate_path()
```

Preferred:

```text
Path calculation
    ↓
Only when navigation state/environment changes
```

Pathfinding should be event/state driven.

---

# 23. Avoid Breaking Existing Movement

Before implementation, inspect the existing codebase and identify:

* Player movement script
* Movement point handling
* Grid coordinate conversion
* Combat system
* Attack range calculation
* Enemy occupancy/blocking logic
* Turn manager
* Auto mode
* Farming mode
* Stage transition
* Current movement animation

Reuse existing systems.

Do not replace working systems unnecessarily.

---

# 24. Important Existing Gameplay Compatibility

The implementation must preserve:

### Auto Mode

Automatic navigation must not disable Auto.

### Farming Mode

Automatic navigation must not disable Farming.

### Combat

Existing combat rules remain authoritative.

### Movement Points

Navigation consumes movement points exactly like manual movement.

### Turn System

Navigation must respect the existing turn lifecycle.

### Animation

Use the existing player movement animation.

### Stage Navigation

If the player uses navigation to move toward another stage/cell, preserve the existing stage transition rules.

---

# 25. Example: Basic Obstacle Avoidance

Given:

```text
Row 1: . . . . . . .
Row 2: . . X X X . .
Row 3: P . . . . . T
```

A* should find:

```text
P → → → → → T
    ↑
    ↑
  around X
```

The player must never enter:

```text
X
```

---

# 26. Example: Enemy Blocking

Given:

```text
P . . E . . T
```

Navigation:

```text
P → → E
```

If E is attackable:

```text
Attack E
```

After E dies:

```text
P → → → → T
```

The original target remains `T`.

---

# 27. Example: Multiple Turns

Given:

```text
P . . . . . . . . . T
```

Movement Points:

```text
3
```

Turn 1:

```text
P → → →
```

Turn 2:

```text
→ → →
```

Turn 3:

```text
→ → → T
```

No additional player input should be required after the initial destination click.

---

# 28. Example: Enemy Dies During Navigation

```text
Target = T

P → → E → → T
```

Turn 1:

```text
P → E
```

Turn 2:

```text
Attack E
```

Enemy dies.

Immediately:

```text
Recalculate path P → T
```

Continue:

```text
P → → → T
```

---

# 29. Implementation Guidelines

Before modifying code:

1. Inspect the existing player movement implementation.
2. Inspect grid/cell coordinate handling.
3. Inspect obstacle/occupancy handling.
4. Inspect enemy movement and blocking behavior.
5. Inspect combat attack-range logic.
6. Inspect turn/movement-point lifecycle.
7. Inspect Auto/Farming state handling.
8. Identify the smallest integration point for pathfinding.

Then implement the pathfinder using the existing grid coordinate system.

Do not introduce duplicate grid-coordinate conversions unless necessary.

None were introduced.

Do not replace a working system: the existing grid, movement, turn, combat, AUTO and
FARMING systems were reused as they are.

---

# 30. Implementation Record

Everything below is what the build actually does, verified by the suites named in §30.6.

## 30.1 What was built

| Piece | File | Role |
|---|---|---|
| Grid probe | `scripts/systems/grid_map_2d.gd` | `find_path(start, goal, ignored_occupied = [])` — the existing pathfinder, extended with an occupancy-ignore **probe** |
| Navigation | `scripts/systems/navigation_controller.gd` | `NavigationController` — the destination, the walk, the blocker, the stop reasons |
| AUTO hold | `scripts/systems/auto_combat_controller.gd` | `set_navigation_hold()` — AUTO keeps its state but leaves the turn's movement to the walk |
| Host wiring | `scripts/world/grid_combat.gd` + `scenes/world/grid_combat.tscn` | Click handling, cancellation, recalculation triggers, indicator updates, messages |
| Indicator | `scripts/ui/combat_actions.gd`, `scripts/ui/mobile_combat_hud.gd` | `set_navigating()` — the `AUTO NAVIGATING` label, built in code |
| Tests | `tools/ui_harness/suites/test_grid_navigation.gd` | 5 focused tests over the real scene and the real click pipeline |
| Tests | `tools/ui_harness/suites/test_grid_click_actions.gd` | the out-of-range click contract, updated from "does not move" to "arms a destination" |

## 30.2 Responsibility split (as implemented)

```text
grid_combat (HOST)
│  what a click means, when the walk is cancelled, what the player reads
│
├── GridMap2D            walkability + occupancy + routes (unchanged owner)
├── NavigationController destination, recalculation, blocker handling, stop reasons
├── PlayerController     the step (try_input_move), movement points, animation, lock
├── CombatSystem         can_attack / the attack itself (damage, crits, death, EXP)
├── TurnManager          whose turn it is; navigation obeys it and ends its own turn
└── AutoCombatController AUTO / FARMING state (untouched), held during a walk
```

No movement rule, damage rule, turn rule, loot rule or EXP rule exists inside
`NavigationController`. It calls `PlayerController.try_input_move()` per cell and
emits `PlayerController.attack_requested` to strike — the same seams the D-pad and the
ATTACK button use.

## 30.3 Behaviour

- **Click inside the range** — unchanged: the hero walks there now (`try_move_to`), and
  any active destination is dropped.
- **Click beyond the range** — on the hero's own turn, a `NavigationController`
  destination is armed. The hero walks the cells this turn can pay for, and the walk
  continues by itself on every following PLAYER TURN until the hero arrives.
- **One destination** — a second click replaces the first; there is never a queue of
  walks. A click the hero can walk right now cancels navigation and simply walks.
- **Turn lifecycle** — a step is a real player step, so it costs a movement point, obeys
  the enemy-attack movement lock, and the last movement point settles the turn exactly
  as a manual walk does (the combat host's existing rule). Navigation ends the turn
  itself only when the host will not (AUTO held) — so the hero never gets free movement.
- **Recalculation** — the route is recomputed on every navigation beat, and a beat is
  triggered by: arming a destination, a `moved` signal, `player_turn_started`, an enemy
  move, an enemy death, an enemy summon. Never per frame, and never cached (see §22).
- **Blockers** — an enemy is treated as the blocker **only** when both hold:
  1. removing every living enemy's cell opens a route to the destination (a probe on
     `find_path(..., ignored_occupied)`), i.e. ACTORS — not the terrain — are in the way;
  2. the hero can reach a free cell inside its own attack range of that enemy.

  Among those, the closest one wins (tie: the one nearest the destination). In reach, the
  hero strikes it through `attack_requested`; otherwise it walks into reach first. The
  clicked destination stays the navigation target throughout — the enemy never replaces
  it — and the route is recalculated when the enemy dies or the turn turns.
- **No route** — if neither condition holds (terrain walls the destination off, or an
  actor does and cannot be approached), the walk stops safely and says so. It never
  attacks an unrelated enemy in reach to force a route open.
- **Stop/cancel** — a tap on the hero's own cell cancels the walk (and re-selects the
  hero); a stage change, a cleared stage (free roam) and victory/defeat cancel it too.
- **AUTO / FARMING** — never toggled, never reset. While a destination is armed, AUTO
  *holds* its own movement decision (`set_navigation_hold`) and takes the turn back when
  the walk ends. AUTO stays ON and its button keeps saying so.

## 30.4 Deviations from this brief

| Brief | Decision | Why |
|---|---|---|
| §2 use `AStarGrid2D` | Reuse `GridMap2D.find_path` | Avoid a second walkability/occupancy source of truth (§8's own rule); the gate lane and `blocked_cells` are already modelled there |
| §12 seven navigation states | Four states + `get_blocker()` | The blocker states have no behaviour of their own in this architecture |
| §13 `Auto Navigating` | `AUTO NAVIGATING` in a code-built label | The HUD is uppercase; a center banner would cover the board and collide with VICTORY / DEFEAT |
| §10 Case C "look for an alternate route" | Already covered by the pathfinder; the walk only fights when no route exists at all | `find_path` IS the alternate-route search, and it prefers a bypass automatically |
| §21 "pathfinding failure" | Six distinct reasons, each with its own message | A refusal, a wall, a stage change and a defeat must not read the same to the player |
| §19 cancel cases | Listed above | The brief's list was kept and completed with victory/defeat and free roam, which are the states where a walk can no longer exist |

## 30.5 Notes for future work

- `blocked_cells` on `GridMap2D` is read live, so a stage may add permanent obstacles at
  any time and navigation picks them up on its next recalculation with no extra call.
- A destination armed on a turn with zero movement points (`stats.movement_points == 0`)
  stops with `no_movement` instead of looping turns forever. The click path itself cannot
  arm one, because an empty tank already ends the turn (§ the click rules).
- Navigation is deliberately NOT used in free roam: after a clear the existing unbounded
  click-walk and AUTO's exit walk already cover it, and free roam spends no points.

## 30.6 Verification

```powershell
tools\ui_harness\run_ui_harness.ps1 -Suite test_grid_navigation -Quiet      # 5 tests
tools\ui_harness\run_ui_harness.ps1 -Suite test_grid_click_actions -Quiet   # 13 tests
tools\ui_harness\run_ui_harness.ps1 -Suite test_stage_exit_advance -Quiet   # 11 tests
tools\ui_harness\run_ui_harness.ps1 -Suite test_enemy_attack_move_lock -Quiet  # 4 tests
```

`test_grid_navigation` covers, over the real scene and the real GUI click pipeline:

1. a destination beyond the range is walked over several turns with no further input,
   with the indicator on for the whole walk and AUTO / FARMING unchanged at the end;
2. an enemy standing in front of the destination is struck through the hero's own attack
   seam, and the destination survives the death of the blocker;
3. a terrain-walled destination stops the walk safely, reports why, hides the indicator,
   and does not attack an unrelated enemy in reach;
4. a tap on the hero's own cell cancels the walk and stops the hero where it stands;
5. with AUTO on, navigation — not AUTO — walks the clicked cell, AUTO stays on, and it
   takes its turn back when the walk ends.
