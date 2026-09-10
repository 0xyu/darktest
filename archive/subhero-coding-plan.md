# Sub Hero Coding Plan

## 1. Goal

Implement the **Sub Hero** system described in the updated game design:

- Sub Heroes are positioned **outside the combat grid**, in a fixed row below the grid.
- They **never move** and are not grid entities.
- They attack enemies automatically and continuously, independent of player input and grid position.
- They can attack from any distance and ignore grid/pathfinding constraints.
- Sub Heroes are obtained through the Shop / Summon system.
- Initial qualities:
  - White — Common
  - Purple — Rare
  - Gold — Legendary
- Sub Heroes add an **idle/persistent progression layer** without replacing the existing Grid Combat + Equipment progression loop.

The implementation must remain **mobile portrait-first** and integrate with the existing stage, combat, loot, progression, and auto-combat architecture.

---

## 2. Design Principles

### 2.1 Separate Combat Responsibilities

Main Hero:
- Grid movement
- Positioning
- Turn-based action
- Equipment/build interaction
- Manual/Auto combat

Sub Hero:
- Persistent automatic attacks
- No grid occupancy
- No movement
- No normal enemy pathfinding interaction
- Independent attack timer
- Target selection
- Additional DPS and selected utility effects

Do not implement Sub Heroes as normal grid units.

### 2.2 Preserve Existing Core Loop

Existing core loop:

```text
Fight
→ Loot
→ Inspect
→ Equip / Upgrade
→ Power Spike
→ Push Stage
```

Sub Heroes should extend this loop:

```text
Fight
→ Sub Hero attacks continuously
→ Loot
→ Upgrade Equipment / Sub Hero
→ Power Spike
→ Push Stage
```

Sub Heroes must not make Equipment irrelevant.

### 2.3 Idle-Friendly, Not Full Auto-Stage Replacement

Sub Hero attacks should continue while combat is active even if the player does nothing.

For the initial implementation:
- Support continuous combat-time attacks.
- Do not implement unrestricted offline Stage progression in the MVP.
- Offline progression can be added later as a separate system using already-cleared/proven progression limits.

---

# 3. Architecture

## 3.1 New Domain Objects

Create data-driven Sub Hero definitions.

Recommended structure:

```text
SubHeroData
├── id
├── display_name
├── quality
├── attack_damage
├── attack_interval
├── target_rule
├── unique_effect
├── tags
└── icon / portrait reference
```

Quality:

```text
SubHeroQuality
├── COMMON
├── RARE
└── LEGENDARY
```

Use the project's existing naming/style conventions if equivalent enums/resources already exist.

### Tags

Support optional tags for future synergy:

```text
DPS
Poison
Critical
Boss
Undead
Mage
Assassin
Support
```

Do not implement a full synergy system in the MVP; only make the data model extensible.

---

# 4. Sub Hero Runtime State

Create runtime state separately from static data.

Recommended:

```text
SubHeroInstance
├── hero_id
├── level
└── duplicate_count / progression value
```

Do not store mutable progression directly in shared `SubHeroData` resources.

A Sub Hero instance should be serializable for save/load.

---

# 5. Sub Hero Slots

Initial implementation:

```text
3 active Sub Hero slots
```

Layout:

```text
┌─────────────────────────────┐
│                             │
│        Combat Grid          │
│                             │
│                             │
├─────────────────────────────┤
│ [Sub A] [Sub B] [Sub C]     │
└─────────────────────────────┘
```

Requirements:

- Fixed position.
- Outside the grid.
- Does not occupy grid cells.
- Does not affect pathfinding.
- Does not block enemy movement.
- Does not move during combat.
- Slot UI remains visible during combat.

Future slot unlocking can be added later.

---

# 6. Combat Integration

## 6.1 Dedicated Sub Hero Combat Manager

Create a dedicated runtime system, e.g.:

```text
SubHeroCombatManager
```

Responsibilities:

1. Register active Sub Heroes at combat start.
2. Maintain attack timers.
3. Select targets.
4. Execute attacks.
5. Apply Sub Hero effects.
6. React to enemy death.
7. Stop/reset when combat ends.
8. Avoid interfering with the existing player/enemy turn state machine.

Sub Hero attacks should be **time-based**, not player-turn-based.

Example:

```text
Sub Hero A
interval = 1.5 sec

Sub Hero B
interval = 2.5 sec

Sub Hero C
interval = 4.0 sec
```

---

# 7. Attack Timer

Each active Sub Hero has an independent timer.

Pseudo-flow:

```text
combat_start
    ↓
initialize timers
    ↓
timer reaches 0
    ↓
select target
    ↓
attack
    ↓
reset timer
    ↓
repeat
```

Important:

- Do not wait for Player Turn.
- Do not wait for Enemy Turn.
- Do not require a click.
- Do not require the Main Hero to have acted.
- Attack continuously while combat is running.

The implementation should use the project's normal frame/timer architecture rather than spawning unnecessary nodes per attack.

---

# 8. Target Selection

Initial target priority:

1. Alive Boss / Elite if the Sub Hero has a Boss/Elite targeting rule.
2. Lowest HP enemy if configured.
3. Closest-to-defeat enemy.
4. Default: deterministic valid enemy.

For MVP, use one consistent default rule:

```text
Select the alive enemy with the lowest current HP.
```

This is simple, predictable, and easy to test.

Target selection must:

- Ignore grid distance.
- Ignore line of sight.
- Ignore pathfinding.
- Ignore occupied cells.
- Never select dead enemies.
- Re-select if the current target dies.

---

# 9. Damage

MVP Sub Hero damage should be deterministic and easy to tune.

Recommended:

```text
SubHeroDamage =
SubHeroBaseDamage
× LevelMultiplier
× QualityMultiplier
```

Do not immediately reuse every Main Hero combat modifier.

Instead, provide a clear integration point for future modifiers:

```text
calculate_subhero_damage(...)
```

Future modifiers may include:

- Main Hero build effects
- Sub Hero synergy
- Boss damage
- Critical
- Status effects

The first implementation should keep Sub Hero damage independent enough that balancing is straightforward.

---

# 10. Sub Hero Effects

MVP should support:

```text
Basic Damage
```

and one extensible effect interface.

Example:

```text
SubHeroEffect
├── None
├── Poison
├── Execute
├── BossDamage
└── Support
```

Do not implement every effect initially.

Recommended first content set:

### White

Pure DPS.

### Purple

DPS + one simple utility effect.

Example:
- Poison chance
- Armor reduction
- Boss damage

### Gold

DPS + unique mechanic.

Example:
- Execute low-HP enemies
- Periodic burst
- Boss-focused attack

The exact content values should remain data-driven.

---

# 11. Quality

Initial quality hierarchy:

```text
White
Purple
Gold
```

Recommended gameplay identity:

```text
White
= reliable base DPS

Purple
= DPS + special mechanic

Gold
= stronger DPS + unique mechanic
```

Do not make quality only a direct DPS multiplier.

Avoid:

```text
White = 100 DPS
Purple = 500 DPS
Gold = 5000 DPS
```

because that makes lower qualities irrelevant and turns the system into pure stat replacement.

---

# 12. Shop / Summon Integration

Add a Shop entry point:

```text
Shop
└── Sub Hero Summon
```

MVP should support:

- Single summon
- Multi summon if existing Shop architecture supports it
- Quality roll
- Sub Hero instance creation
- Duplicate handling

Use the existing currency/economy architecture where possible.

Do not create an unnecessary second economy system.

---

# 13. Summon Quality Roll

Create a configurable summon table:

```text
SubHeroSummonTable
├── Common weight
├── Rare weight
└── Legendary weight
```

Do not hard-code probabilities in UI code.

Initial probabilities should be tuning data.

Add an explicit bad-luck / pity integration point, but keep the exact pity numbers configurable and out of the combat code.

---

# 14. Duplicate Handling

When a player obtains a Sub Hero they already own:

```text
Duplicate
    ↓
Convert to Sub Hero Shards / progression value
    ↓
Upgrade that Sub Hero
```

MVP may use a simple duplicate counter if the project's progression architecture is not ready for a shard currency.

Recommended abstraction:

```text
SubHeroProgressionService
```

Responsibilities:

- Add new instance.
- Detect duplicate.
- Add duplicate progression.
- Calculate current level/stat value.

Do not make duplicate handling part of the Shop UI itself.

---

# 15. Sub Hero Leveling

MVP:

```text
Level 1
→ Level 2
→ Level 3
...
```

Use a data-driven level curve.

Recommended conceptual model:

```text
Damage = BaseDamage × LevelMultiplier
```

Keep level scaling moderate.

Equipment remains the primary source of exciting player power.

Future:
- Stars
- Skill levels
- Unique ability upgrades
- Synergy bonuses

These should not be required for MVP.

---

# 16. UI Implementation

## 16.1 Combat HUD

Add a fixed Sub Hero row beneath the grid.

Each slot should display:

```text
Portrait
Name or compact identifier
Quality frame
Level
Attack / status feedback
```

During an attack, provide lightweight feedback:

- Projectile/attack animation
- Damage number or hit effect
- Small cooldown indicator if useful

Do not cover the main grid.

## 16.2 Mobile Portrait Requirements

Follow the existing project rules:

- Portrait is the source of truth.
- Use responsive Godot Containers.
- Avoid hard-coded screen coordinates.
- Respect safe areas.
- Keep touch targets usable.
- Ensure the grid remains clearly visible.
- The Sub Hero row must not consume excessive vertical space.

Target:

```text
Grid
↓
Sub Hero row
↓
Combat actions
```

or the existing HUD equivalent, provided the grid remains the dominant combat area.

---

# 17. Sub Hero Management Screen

Add a simple management screen:

```text
Sub Heroes
├── Active
├── Owned
└── Upgrade
```

Required interactions:

- View owned Sub Heroes.
- Select active slot.
- Assign a Sub Hero.
- Remove/replace a Sub Hero.
- View quality.
- View level.
- View basic stats/effect.
- Upgrade using duplicate progression.

Do not build Collection Book or Synergy UI in MVP.

---

# 18. Save / Load

Sub Hero ownership and progression must persist.

Save:

```text
Owned Sub Heroes
Active Slot Assignments
Level
Duplicate / Shard Progression
```

Do not save runtime combat timers.

At combat start, timers are initialized from Sub Hero data.

Save/load must be compatible with the project's existing save system.

---

# 19. Stage / Enemy Integration

Sub Heroes must interact correctly with:

- Normal enemies
- Elite enemies
- Special enemies
- Mini Bosses

They should be able to target any alive enemy regardless of grid distance.

When an enemy dies:

```text
EnemyDeath
    ↓
SubHeroCombatManager
    ↓
Validate current targets
    ↓
Retarget if required
```

Do not allow Sub Hero attacks to damage an already-dead enemy.

---

# 20. Boss Integration

MVP:

- Sub Heroes can attack Mini Bosses.
- Sub Heroes can attack special enemies.
- Bosses use the same basic targeting rules unless a Sub Hero has a Boss-specific effect.

Future:

```text
Boss Killer
+Damage vs Boss
Execute
Boss-specific mechanics
```

Do not build a separate boss combat pipeline.

---

# 21. Auto Combat Integration

Sub Heroes are independent of the Main Hero's Manual/Auto toggle.

Expected behavior:

```text
Manual Main Hero
+
Sub Heroes attacking
```

and:

```text
Auto Main Hero
+
Sub Heroes attacking
```

Both should work.

The Sub Hero system should not pause because Main Hero Auto is disabled.

---

# 22. Combat Pause / End Rules

Sub Hero attacks should stop when:

```text
Combat Paused
Combat Won
Combat Lost
Scene Exited
```

On new combat:

```text
Reset timers
Register active Sub Heroes
Start attacking
```

No attack should leak across stages.

---

# 23. Offline Progression — Future Phase

Do not implement full offline progression in the initial Sub Hero task.

Future architecture should support:

```text
last_active_timestamp
        ↓
offline_duration
        ↓
eligible_progression
        ↓
offline reward summary
```

Recommended future constraints:

- Offline cap.
- Only farm already-proven stages.
- Do not allow offline progress to freely unlock unknown content.
- Present a return summary.

This should be implemented as a separate progression feature rather than embedded into SubHeroCombatManager.

---

# 24. Retention Features — Future Phase

Do not implement in the first coding milestone, but keep extension points for:

### Daily

- Daily Sub Hero missions.
- Summon ticket rewards.
- Upgrade materials.

### Weekly

- Weekly Boss.
- Weekly Sub Hero rewards.

### Collection

- Sub Hero Collection Book.
- Completion rewards.

### Synergy

- Tags.
- Team bonuses.
- Build interaction.

These features should extend Sub Hero data rather than require a rewrite.

---

# 25. Recommended Initial Content

For the first playable implementation, create approximately:

### White — 3

1. Skeleton Archer — basic ranged DPS
2. Goblin Gunner — faster attacks, lower damage
3. Dark Servant — slow attack, higher damage

### Purple — 3

1. Poison Witch — poison effect
2. Dark Ranger — bonus damage to low-HP targets
3. Plague Doctor — simple enemy debuff

### Gold — 2

1. Death Knight — periodic burst / execute
2. Demon Mage — high damage with slower attack interval

Keep the actual numbers in `SubHeroData` resources.

---

# 26. Suggested Project Structure

Adapt paths to the repository's existing structure.

Conceptually:

```text
scripts/
  sub_hero/
    sub_hero_data.gd
    sub_hero_instance.gd
    sub_hero_combat_manager.gd
    sub_hero_targeting.gd
    sub_hero_progression.gd
    sub_hero_summon_service.gd

scenes/
  sub_hero/
    sub_hero_slot.tscn
    sub_hero_row.tscn
    sub_hero_management.tscn

resources/
  sub_heroes/
    common/
    rare/
    legendary/
```

If equivalent systems already exist, integrate into them rather than creating duplicate abstractions.

---

# 27. Implementation Order

## Phase 1 — Data

- [x] Create SubHeroQuality.
- [x] Create SubHeroData.
- [x] Create SubHeroInstance.
- [x] Create initial Sub Hero resources.
- [x] Add configurable attack interval/damage.
- [x] Add effect/tag extension points.

## Phase 2 — Combat

- [x] Create SubHeroCombatManager.
- [x] Register active Sub Heroes at combat start.
- [x] Implement independent attack timers.
- [x] Implement target selection.
- [x] Implement distance-independent attacks.
- [x] Apply damage.
- [x] Handle target death / retargeting.
- [x] Reset state at combat end.

## Phase 3 — UI

- [x] Add Sub Hero row below combat grid.
- [x] Create slot component.
- [x] Display portrait, quality, level.
- [x] Add attack feedback.
- [x] Add assignment interaction.
- [ ] Verify portrait responsive layout.

## Phase 4 — Ownership / Progression

- [x] Add owned Sub Hero collection.
- [x] Add active slot assignment.
- [x] Add level progression.
- [x] Add duplicate handling.
- [ ] Connect to save/load.

## Phase 5 — Shop

- [x] Add Sub Hero summon entry.
- [x] Add quality roll.
- [x] Add Sub Hero selection/result UI.
- [x] Add duplicate conversion.
- [x] Add configurable summon weights.

## Phase 6 — Integration

- [ ] Test normal enemy combat.
- [ ] Test Elite combat.
- [ ] Test Special encounter.
- [ ] Test Mini Boss.
- [ ] Test Manual Main Hero + Sub Hero.
- [ ] Test Auto Main Hero + Sub Hero.
- [ ] Test stage transition.
- [ ] Test death/retry.
- [ ] Test save/load.

---

# 28. Testing Plan

## Unit Tests

### Targeting

- [ ] Dead enemies are never selected.
- [ ] Lowest-HP rule is deterministic.
- [ ] Target selection ignores grid distance.
- [ ] Target is replaced after death.

### Damage

- [ ] Damage is at least 1 where applicable.
- [ ] Damage scales with Sub Hero level.
- [ ] Quality data loads correctly.
- [ ] Attack interval is respected.

### Timers

- [ ] Each Sub Hero attacks independently.
- [ ] Main Hero turns do not affect timers.
- [ ] Enemy turns do not affect timers.
- [ ] Pause stops attacks.
- [ ] Combat end stops attacks.
- [ ] New combat resets timers.

### Progression

- [ ] New Sub Hero can be added.
- [ ] Duplicate is detected.
- [ ] Duplicate progression is applied.
- [ ] Level persists after save/load.
- [ ] Active slot assignment persists.

---

# 29. Integration Test Scenarios

### Scenario A — No Player Input

```text
Start combat
↓
Do nothing
↓
Sub Heroes attack
↓
Enemy HP decreases
```

Pass condition:

> Combat state changes because Sub Heroes continue attacking without player interaction.

### Scenario B — Main Hero Manual

```text
Main Hero = Manual
Sub Heroes = Active
```

Pass:

> Both systems work simultaneously.

### Scenario C — Main Hero Auto

```text
Main Hero = Auto
Sub Heroes = Active
```

Pass:

> Both systems work simultaneously without timer conflicts.

### Scenario D — Target Dies

```text
Sub Hero attacks Enemy A
Enemy A dies
↓
Sub Hero selects Enemy B
```

Pass:

> No attack is wasted on dead Enemy A.

### Scenario E — Mini Boss

```text
Stage 10
↓
Mini Boss
↓
Sub Heroes attack from outside grid
```

Pass:

> Sub Heroes can damage Mini Boss regardless of grid position.

### Scenario F — Stage Transition

```text
Stage Clear
↓
Next Stage
```

Pass:

> Old timers and old targets do not carry into the new battle.

---

# 30. Balance Validation

Initial balance should verify:

```text
Main Hero power > Sub Hero power
```

for early game.

Suggested conceptual contribution:

```text
Early:
Main Hero ≈ 80%
Sub Heroes ≈ 20%

Mid:
Main Hero ≈ 65%
Sub Heroes ≈ 35%

Late:
Main Hero ≈ 50%
Sub Heroes ≈ 50%
```

These are balancing targets, not implementation constants.

Monitor:

- Average stage clear time.
- Sub Hero damage contribution.
- Main Hero damage contribution.
- Time-to-first-power-spike.
- Time between meaningful upgrades.
- Gold income vs summon cost.
- Duplicate frequency.
- Quality distribution.

---

# 31. Performance Requirements

Avoid creating excessive runtime objects for every attack.

Preferred:

```text
One SubHeroCombatManager
+
Small number of active Sub Hero runtime states
+
Timer/elapsed-time checks
```

Avoid:

- One permanent process node per projectile unless required.
- Heavy pathfinding for Sub Heroes.
- Grid queries for target distance.
- Rebuilding enemy lists unnecessarily every frame.

Target selection can be recalculated on:

- Attack event.
- Current target death.
- Explicit combat state change.

It does not need to run every frame.

---

# 32. Acceptance Criteria

The Sub Hero feature is complete when:

- [ ] Three Sub Hero slots are visible outside the grid.
- [ ] Sub Heroes never occupy grid cells.
- [ ] Sub Heroes never move.
- [ ] Sub Heroes attack regardless of distance.
- [ ] Sub Heroes attack without player input.
- [ ] Sub Heroes attack during both Manual and Auto Main Hero modes.
- [ ] Each Sub Hero has an independent attack interval.
- [ ] Targets are valid and retarget correctly.
- [ ] Sub Heroes can damage Mini Bosses and special enemies.
- [ ] White / Purple / Gold qualities are supported.
- [ ] Sub Hero ownership persists.
- [ ] Active slot assignments persist.
- [ ] Duplicate Sub Heroes progress correctly.
- [ ] Summoning is connected to Shop.
- [ ] No Sub Hero attack continues after combat ends.
- [ ] Stage transitions reset combat state correctly.
- [ ] The feature works in portrait mobile layout.
- [ ] The existing Grid Combat and Equipment progression remain functional.
- [ ] Sub Heroes provide additional progression without becoming the sole source of player power.

---

# 33. Explicit Non-Goals for This Coding Task

Do NOT implement:

- Full offline progression.
- Daily missions.
- Weekly Boss.
- Collection Book.
- Full Sub Hero synergy system.
- PvP.
- Guilds.
- Trading.
- Complex Sub Hero skill trees.
- Multiple additional currencies unless required by existing architecture.
- Landscape-first UI.
- Sub Heroes as grid entities.
- Sub Hero pathfinding.
- Sub Hero movement.

These are future extensions.

---

# 34. Final Engineering Principle

The Sub Hero system should feel like a **persistent layer sitting underneath the existing Grid Combat**, not a replacement for it.

The desired architecture is:

```text
                 Battle
                   │
        ┌──────────┴──────────┐
        │                     │
    Main Hero             Sub Heroes
        │                     │
 Grid / Turns           Independent Timers
 Movement               Target Selection
 Equipment              Persistent DPS
 Skills                 Utility Effects
        │                     │
        └──────────┬──────────┘
                   ↓
                 Enemy
                   ↓
                 Loot
                   ↓
              Progression
                   ↓
               Next Stage
```

Keep the system data-driven, deterministic where possible, extensible for future Synergy/Idle features, and isolated enough that Sub Hero logic does not destabilize the existing turn-based Grid Combat.
