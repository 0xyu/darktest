# UI Testing Fixtures

Deterministic, reusable test data for UI development and agent automation.
Agents should use these fixtures instead of hand-crafting equipment/inventory/
character data via `game_eval` or debug scripting.

## Why this exists

UI panels (inventory, character, equipment) need realistic data to be tested
and developed against. Manually constructing `EquipmentInstance` /
`EquipmentInventory` / `PlayerStats` every time is slow and error-prone. The
fixture system builds all of it in one call:

- **Deterministic** — no `RandomNumberGenerator` anywhere. Affix values use the
  production median value curve.
- **No save dependency** — builds fresh in-memory resources only.
- **No production changes** — lives entirely under `res://tests/`, reuses the
  production data model (`EquipmentInstance`, `EquipmentDefinition`,
  `EquipmentAffix`, `EquipmentInventory`, `PlayerStats`, `PlayerProgression`).
- **Headless-loadable** — pure `RefCounted` with static factory methods.
- **Repeatable** — each call returns fresh, independent objects.

## Files

| Path | Purpose |
|---|---|
| `tests/fixtures/ui_fixture.gd` | `class_name UIFixture` — static factory methods |
| `tests/test_ui_fixture.gd` | `McpTestSuite` covering determinism/rarity/repeatability |
| `scripts/ui/development_panel.gd` | In-game DEV panel wired to the fixtures |
| `scenes/ui/DevelopmentPanel.tscn` | DEV panel scene (instance in `MobileCombatHUD.tscn`) |

## UIFixture API

```gdscript
# Equipment
UIFixture.create_equipment(rarity, slot, item_level, unique_effect_id, affixes) -> EquipmentInstance
UIFixture.create_affix(stat_id, value) -> EquipmentAffix
UIFixture.create_affix_scaled(stat_id, item_level, rarity) -> EquipmentAffix
UIFixture.create_rarity_set() -> Array[EquipmentInstance]   # one per rarity, fixed ids

# Inventory
UIFixture.create_empty_inventory(capacity) -> EquipmentInventory
UIFixture.create_inventory() -> EquipmentInventory  # 8 items, legendary+mythic equipped

# Character
UIFixture.create_player_stats(overrides) -> PlayerStats
UIFixture.create_player_progression(level, gold, stage) -> PlayerProgression
UIFixture.create_character(level, gold, stage) -> Dictionary  # {stats, progression, inventory}
UIFixture.apply_character_to_player(player, bundle) -> void
```

The inventory fixture guarantees at least one **Common, Rare, Epic, Legendary,
and Mythic** item. `create_rarity_set()` includes Uncommon as well.

### Usage in the running game (agent automation)

```gdscript
var F = load("res://tests/fixtures/ui_fixture.gd")
var player = get_tree().current_scene.find_child("Player", true, false)
F.apply_character_to_player(player)          # level 10, gold 2500, 8 items, 2 equipped
var item = F.create_equipment(EquipmentRarity.MYTHIC, EquipmentSlot.RING, 40)
player.add_equipment(item)
```

Applying the default demo character yields derived stats of roughly 666 HP /
125 attack at level 10 (base stats + equipped fixture bonuses).

### Usage in GDScript tests

```gdscript
const UIFixtureScript := preload("res://tests/fixtures/ui_fixture.gd")
var inventory := UIFixtureScript.create_inventory()
assert_true(inventory.get_item_count() >= 5)
```

Prefer preloading the fixture by path (as above) over the `UIFixture` global
class name in test files — path-based preload does not depend on the editor's
global class table being freshly rebuilt.

## In-game DEV panel

The combat HUD's bottom utility row has a **DEV** button. It toggles the
development panel, which exposes the fixtures in-game:

- **GENERATE ITEM** — one button per rarity; each click drops a fresh item of
  that rarity at the player's level into their inventory. The equipment slot
  rotates on every click (Weapon → Helmet → … → Amulet) so repeated clicks fill
  the bag with varied slots.
- **FILL DEMO INVENTORY** — adds `create_rarity_set()` (one per rarity).
- **APPLY DEMO CHARACTER** — applies `apply_character_to_player()`.
- **CLEAR BAG** — removes all non-equipped items.

The DEV panel also includes **SUB HERO FIXTURES**. These buttons directly add
catalog Sub Heroes without spending Gold and without using the summon table or
quality roll. They still go through the normal `SubHeroProgressionService`, so
calling the same hero again exercises duplicate conversion and level progress.

For Agent/runtime tests, use the public DEV-panel method directly:

```gdscript
var dev = get_tree().current_scene.find_child("DevelopmentPanel", true, false)
dev.dev_summon_sub_hero(&"skeleton_archer")
```

The `hero_id` may be any catalog id (`skeleton_archer`, `goblin_gunner`,
`dark_servant`, `poison_witch`, `dark_ranger`, `plague_doctor`,
`death_knight`, or `demon_mage`). The optional second argument is the starting
level. Omitting the id deterministically adds the first catalog entry. This
runtime-only helper does not persist data and does not require Gold or Shop
resources, making it the preferred direct setup path when an Agent tests
Sub Hero ownership, assignment, or duplicate progression.

The panel emits `data_changed` after every mutation; the HUD listens and
re-binds the inventory panel (required because `apply_character_to_player`
replaces the player's inventory *object*, orphaning panels bound to the old one).

## Running the fixture tests

The suite lives at `res://tests/test_ui_fixture.gd` (12 tests). To run it via
the Godot AI MCP: `test_run(suite="ui_fixture")`.

> **Known issue:** the MCP `test_run` discovery cannot instantiate *newly added*
> `res://tests/*.gd` suites until the editor is fully restarted (plugin issue
> #882 — affects even a trivial suite). Until then, run the suite headless
> through the addon's own runner:
>
> ```
> D:\IDE\godotEngine\Godot_v4.7.2-stable_win64.exe --headless --path <project> --script runner.gd
> ```
> where `runner.gd` is `extends SceneTree` and runs
> `McpTestRunner.new().run_suites([load("res://tests/test_ui_fixture.gd").new()], "", "")`.

## Gotchas

- **Instance ids are unique per generated item.** `create_equipment` uses a
  static counter so several identical items can coexist in one inventory; the
  rarity-set items use fixed ids (`fixture_common_weapon`, …). Do not rely on
  generated instance ids being stable across runs — compare *values*, not ids.
- **`create_inventory()` contents are 8 items** (6 rarity-set + 2 extra), two of
  which are equipped. Tests assert `get_item_count() == rarity_set.size() + 2`.
- Do not add game-data writing code to the fixtures — they must stay side-effect
  free (no `.tres` writes, no save files, no `project.godot` changes).
