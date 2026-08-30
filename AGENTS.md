# AI Agent Development Rules

## Project Overview

This is a Godot 4.x 2D dark-fantasy RPG focused on:

- Grid-based movement
- Turn-based combat
- Move + one action per player turn
- Auto combat
- Sequential stage progression
- Random enemies
- Mini Bosses every 10 stages
- Random special encounters
- Equipment-driven progression
- Diablo-inspired dark fantasy UI
- Clicker Heroes-inspired exponential progression philosophy

Read these documents before making gameplay changes:

- `README.md`
- `docs/game-design.md`

---

## Core Development Rules

1. Implement only the requested feature.
2. Do not silently implement unrelated or future systems.
3. Inspect the existing project before creating new files or systems.
4. Reuse existing systems before introducing new abstractions.
5. Do not modify unrelated files.
6. Keep the project runnable after every change.
7. Prefer small, testable changes.
8. Use typed GDScript where practical.
9. Avoid unnecessary dependencies and plugins.
10. Do not introduce C# unless explicitly requested.
11. Prefer composition over deep inheritance.
12. Use signals for loosely coupled communication.
13. Avoid unnecessary autoloads and global state.
14. Keep configuration/tuning values outside gameplay logic when practical.
15. Do not hard-code balance values in multiple places.
16. Do not create speculative systems for future features.

---

## Feature-Based Development

The completed MVP phase plan is archived under `archive/mvp/` and is historical
reference only. Current work follows the user's request and the existing
playable architecture.

The agent MUST:

- Implement only the requested feature.
- Preserve the current playable state.
- Verify the affected behavior before moving forward.
- Avoid speculative architecture.
- Avoid large rewrites of working code.
- Keep changes focused on the current feature.

Before a non-trivial implementation:

1. Read the relevant design documentation.
2. Inspect existing scenes/scripts/resources.
3. Identify reusable systems.
4. State the implementation approach briefly.
5. Implement incrementally.
6. Run the project.
7. Check Godot errors and warnings introduced by the change.

---

## Architecture Rules

### Scenes

Scenes should primarily describe node composition and scene-specific configuration.

### Scripts

Gameplay logic should live in modular scripts rather than being concentrated in a single large script.

### Resources

Use Godot `Resource` classes for configurable game data such as:

- Enemy definitions
- Equipment definitions
- Loot tables
- Stage definitions
- Stat configurations

### Systems

Prefer modular systems such as:

- Grid system
- Turn manager
- Combat system
- Stage manager
- Loot generator
- Equipment system
- Save system
- Auto combat system

Avoid putting unrelated responsibilities into these systems.

---

## Naming Convention

### Files

- Scene files: `PascalCase.tscn`
- GDScript files: `snake_case.gd`
- Resource files: descriptive `PascalCase.tres` when appropriate

### GDScript

- Classes: `PascalCase`
- Variables: `snake_case`
- Functions: `snake_case`
- Signals: `snake_case`
- Constants: `UPPER_SNAKE_CASE`

---

## Folder Structure

Target structure:

```text
res://
├── scenes/
│   ├── player/
│   ├── enemies/
│   ├── combat/
│   ├── world/
│   ├── ui/
│   └── items/
├── scripts/
│   ├── player/
│   ├── enemies/
│   ├── combat/
│   ├── systems/
│   ├── items/
│   └── ui/
├── resources/
│   ├── enemies/
│   ├── items/
│   ├── stages/
│   └── characters/
├── assets/
│   ├── characters/
│   ├── enemies/
│   ├── environment/
│   ├── ui/
│   ├── items/
│   └── effects/
├── autoload/
└── docs/
```

---

## Godot Rules

- Prefer typed GDScript.
- Use `@export` for tunable gameplay properties when appropriate.
- Use `@onready` instead of repeatedly calling `get_node()` when suitable.
- Prefer signals over direct cross-system coupling.
- Keep Node references clear and intentional.
- Avoid deeply nested scene dependencies.
- Keep gameplay logic independent from presentation where practical.
- Keep balance values centralized or resource-driven.

---

## Combat Rules

The basic player turn is:

```text
Move 0..MovementPoints cells
+
One Action
```

An action can be:

- Attack
- Use Skill
- Use Item

Default movement points:

```text
3
```

Do not change this gameplay rule unless the game design document is updated.

---

## Testing Rules

After meaningful changes:

1. Run the Godot project.
2. Check the debugger for errors.
3. Check warnings introduced by the change.
4. Verify the requested gameplay behavior manually.
5. Do not leave known runtime errors unresolved.

For systems that support tests, add focused tests rather than broad end-to-end tests first.

### UI Testing Fixtures

A deterministic fixture system exists for UI testing — see `docs/testing-fixtures.md`.
Use `UIFixture` (at `res://tests/fixtures/ui_fixture.gd`) to build equipment,
inventory, and character data instead of hand-crafting it via `game_eval`. In the
running game, the **DEV** button on the combat HUD opens a development panel that
generates items/characters straight into the player's inventory. Fixture tests live
in `res://tests/test_ui_fixture.gd`.

---

## Git Rules

- Keep commits small and meaningful.
- Do not rewrite Git history unless explicitly requested.
- Do not commit generated temporary files such as `.godot/`.
- Do not create a commit unless requested by the user or the current workflow explicitly requires it.

Suggested commit prefixes:

- `feat:`
- `fix:`
- `refactor:`
- `chore:`
- `docs:`

---

## MCP / Plugin Rules

Do not install or introduce Godot MCP servers, editor plugins, or external dependencies unless explicitly requested or the current implementation is materially blocked without them.

Prefer built-in Godot functionality for the MVP.

### Godot MCP Workflow

The project has a connected Godot AI MCP server available during editor and
runtime work. Prefer Godot MCP over Windows-level Computer Use for Godot-specific
inspection, testing, and interaction.

Use the following capabilities when the MCP session is connected:

- `session_manage` — list and identify the active Godot editor session.
- `project_run` — start the main scene, current scene, or a selected scene.
- `editor_screenshot` — capture the running game with `source="game"`, or the
  2D editor viewport with `source="viewport_2d"`. With `include_image=true`,
  the result is an MCP image that can be visually inspected. `user_prompt`
  may be supplied to describe what should be checked in the image.
- `game_manage.get_ui_elements` — inspect visible runtime Control nodes,
  including paths, text, disabled state, and rectangles.
- `game_manage.input_mouse` — send runtime mouse motion or button events.
- `game_manage.input_key`, `input_action`, and `input_sequence` — simulate
  keyboard, project actions, and frame-timed input.
- `game_manage.get_scene_tree` and `get_node_info` — inspect the runtime tree
  and node properties.
- `editor_manage.game_eval` — query or exercise running-game state with
  GDScript when structured runtime inspection is insufficient.
- `test_run` and `test_manage` — run and inspect project GDScript tests when present.
- `tileset_get_atlas_image` and `tileset_get_atlas_tiles` — inspect TileSet
  atlas images and occupied atlas cells.

Recommended runtime verification flow:

1. Find and activate the unique project session with `session_manage`.
2. Start the project with `project_run` and confirm the game helper is live.
3. Use `game_manage.get_ui_elements` to locate controls instead of guessing
   coordinates when possible.
4. Use `game_manage.input_mouse` / `input_action` for one interaction at a
   time, then re-check the UI or capture a fresh `editor_screenshot`.
5. Visually inspect the returned MCP image after layout or interaction changes.

The MCP game tools require a Godot editor session with the runtime game helper
connected. If the game was launched externally without that bridge, stop and
re-run it through the MCP workflow before concluding that MCP cannot access
the game. Use Computer Use only for Godot interactions that MCP cannot expose
or when the task explicitly requires Windows-level control.

---

## Asset Rules

AI-generated assets belong under `assets/`.

Do not embed large binary assets inside scripts.

Keep source assets and runtime-ready assets organized where practical.

---

## Documentation Rules

Update documentation when a design or architecture decision materially changes.

Do not rewrite documentation for minor implementation details.

`docs/game-design.md` is the source of truth for gameplay rules.
