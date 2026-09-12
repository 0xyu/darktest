# AI Agent Development Rules

## Project Overview

This is a Godot 4.x 2D dark-fantasy RPG focused on:

- Grid-based movement
- Turn-based combat
- Move + one action per player turn
- Auto combat
- Sequential stage progression
- Random enemies and special encounters
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
2. Inspect existing scenes/scripts/resources — targeted reads only, see
   "Verification & Token Budget" below.
3. Identify reusable systems.
4. State the implementation approach briefly.
5. Implement incrementally.
6. Verify with the cheapest path that proves the behavior (see below).
7. Check Godot errors and warnings introduced by the change.

---

## Verification & Token Budget

Every step re-sends the whole conversation, and everything read stays in context
for the rest of the session: **cost ≈ steps × context size**. Keep both small.
These rules are mandatory, not advisory.

### Reading (context budget)

1. Locate before reading: `grep -n` first, then `read` with `offset`/`limit`.
   Never read a file longer than ~300 lines in full.
2. Never read a file that is already in context. Re-read only after it changed,
   and state why. Never redo reconnaissance that is already in the transcript.
3. Recon budget: at most ~6 files before the first edit. For broad or uncertain
   searches, delegate to a subagent and keep only its short summary here.
4. Work from short notes (`path:line → symbol`), not from pasted file bodies.
5. Never dump large machine output into context: transcripts/logs (`*.jsonl`),
   whole `.tres` dumps, or `git diff` of unreviewed trees. Filter at the source
   (`Select-String`, `Select-Object -First 40`, `--quiet`) and cap at ~100 lines.
6. Batch independent tool calls into one step. Each extra step costs a full
   context re-send, so 2 steps that could be 1 double the bill for that work.
7. Keep reasoning short on mechanical steps (edits, reruns, renames). Do not
   narrate file contents back to yourself.
8. Locate through the CodeMap digest before grepping sources (next section).

### CodeMap digest (locate cheaply)

`tools/codemap.py` indexes the project's scripts, scenes and resources. Refresh it
(a full rebuild is ~0.3s — always rebuild, there is no incremental mode), then
grep the index instead of the sources:

```powershell
python tools\codemap.py index --root .
Select-String -Path .codemap_probe\map.sym.txt -Pattern '<symbol>'
python tools\codemap.py refs <symbol>
```

- `map.sym.txt` — one self-describing line per symbol (`path:line kind name`).
  Grep it; never read it whole. A symbol lookup returns a few lines, not a file
  body — this is the whole point of the digest.
- `map.scripts-full.txt` — per script: class / extends / signals / exports /
  `%`-unique refs / preloads / funcs with line numbers (~11k tokens). Read this
  only when you need orientation, and prefer the `map.scripts-t0.txt` variant
  (~6.6k tokens) for a first pass.
- `scenes.txt` — scene → node → type → attached script / instanced scene, plus
  signal connections (~2k tokens).
- `map.refs.txt` — every reference as `target <- file:line kind [func] detail`.
  Grep it, never read it. `refs <symbol>` prints the same rows for one symbol
  (it re-scans, ~0.6s; no index run needed first).
- Indexed line numbers are exact, so a hit can be opened directly with
  `read offset=<line>`.

The index is **symbol-exact and reference-complete over text**: names, line
ranges, and the textual references — call / emit / connect + handler / await /
string-carried name / `$` node path / preload / scene + instance edge. A wrapped
statement reports the first line of the statement, not the token's own line.

What it still cannot see: a name computed at runtime (`call(name_var)`, a
`Callable` built from a variable), a computed `get_node` path, and anything
written outside the `.tscn` text. `string_ref` rows marked `weak` are literal
matches that may be coincidental. Before a rename, a signature change or a signal
removal, always confirm with a source `grep` — treat an empty result as
"not indexed", never as "unused".

The index skips `addons/` and `archive/`.

### Verification policy

Run only what covers the change, and normally only once:

```powershell
# suite names — do not read the harness sources to find them
tools\ui_harness\run_ui_harness.ps1 -List

# the suite(s) covering the change (-Quiet = failures + one summary line)
tools\ui_harness\run_ui_harness.ps1 -Suite test_stage_exit_advance -Quiet

# a pure-data smoke test (headless, self-contained)
D:\IDE\godotEngine\Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/<name>_smoke_test.gd
```

- **Never run the full harness** (no `-Suite`) unless the user asks for it. It is
  slow, noisy, and surfaces failures that have nothing to do with the change.
- A pre-existing failure unrelated to the current feature: report it in **one
  line** and move on. Do not create a baseline worktree/tree, package the project,
  re-run the same suite repeatedly, or read unrelated systems to explain it.
- One green run is enough. Re-run only after a further change that can affect it.
- Runtime/visual checks are a last resort: at most one project run plus one state
  query and one log read — batched, never one step per question.
- Do not re-read files in order to write the final summary; summarize what is
  already in context.
- Budget: a small feature should take ~10–15 steps. If a simple change is heading
  past ~25 steps, stop and report status instead of exploring further.

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

- Scene files: `snake_case.tscn`
- GDScript files: `snake_case.gd`
- Resource files: descriptive `PascalCase.tres` when appropriate

### GDScript

- Classes: `PascalCase`
- Variables: `snake_case`
- Functions: `snake_case`
- Signals: `snake_case`
- Constants: `UPPER_SNAKE_CASE`

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

Do not change these rules unless `docs/game-design.md` is updated.

---

## Testing Rules

After meaningful changes:

1. Verify with the cheapest path that can prove the behavior — headless harness
   or smoke test before launching the game (see "Verification & Token Budget").
2. Run the Godot project only when the change needs real runtime or visual behavior.
3. Check the debugger for errors.
4. Check warnings introduced by the change.
5. Do not leave known runtime errors unresolved.

Never report a functional change as verified without at least one green run of the
suite or smoke test that covers it. Do not leave unrelated failing suites as a
reason to keep investigating — report them in one line.

For systems that support tests, add focused tests rather than broad end-to-end tests first.

### UI Testing Fixtures

A deterministic fixture system exists for UI testing — see `docs/testing-fixtures.md`.
Use `UIFixture` (at `res://tests/fixtures/ui_fixture.gd`) to build equipment,
inventory, and character data instead of assembling it by hand at runtime. In the
running game, the **DEV** button on the combat HUD opens a development panel that
generates items/characters straight into the player's inventory. The same panel
has a **SUB HERO FIXTURES** section; Agent/runtime tests can call
`DevelopmentPanel.dev_summon_sub_hero(&"skeleton_archer")` directly to add a
Sub Hero without Gold or summon resources while preserving normal duplicate
progression. Fixture tests live in `res://tests/test_ui_fixture.gd`; UI suites
that use the fixture run through the headless harness
(`tools/ui_harness/run_ui_harness.ps1 -Suite <name> -Quiet`).

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

The Godot AI MCP bridge (`addons/godot_ai`) is an **optional** accelerator and may
be disabled in this environment. Treat the CLI harness path in
"Verification & Token Budget" as the default; do not block, retry, or restructure a
session around MCP availability.

- When an MCP session *is* connected, use it only for what headless cannot show:
  `project_run`, `editor_manage.game_eval`, `logs_read`, `editor_screenshot`, and
  `game_manage` (UI elements, mouse/key input, scene tree).
- When it is not connected, verify through the CLI path and move on.
- Batch runtime MCP checks (one run, one state query, one log read). Do not spend
  one step per question.
- Prefer Godot MCP over Windows-level Computer Use for Godot-specific interaction.
  Use Computer Use only for interactions that nothing else exposes.

---

## Asset Rules

AI-generated assets belong under `assets/`.

Do not embed large binary assets inside scripts.

Keep source assets and runtime-ready assets organized where practical.

---

## Documentation Rules

Update documentation only when a design or architecture decision materially changes.

Do not rewrite documentation for minor implementation details.

`docs/game-design.md` is the source of truth for gameplay rules.
