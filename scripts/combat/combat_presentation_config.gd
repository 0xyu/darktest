class_name CombatPresentationConfig
extends RefCounted

## Central tuning table for the combat presentation layer. Every animation
## duration, offset and color lives here so presentation scripts never
## hard-code balance/tuning values inline. Gameplay code must not read this.

# --- Movement ---
const MOVE_DURATION_PER_CELL: float = 0.18
const MOVE_DURATION_PER_CELL_FAST: float = 0.10
const MOVE_HOP: float = 3.0

# --- Attack sequence ---
const ANTICIPATION: float = 0.10
const DASH: float = 0.13
const IMPACT_PAUSE: float = 0.06
const RECOVERY: float = 0.20
## Longest an enemy strike may keep the hero's movement locked while its attack
## animation is on screen. A sequence whose animation never reports back (its
## attacker freed mid-swing) must not strand the hero's movement.
const ENEMY_ATTACK_LOCK_TIMEOUT: float = 3.0
const ANTICIPATION_OFFSET: float = 8.0
const LUNGE_DISTANCE: float = 26.0
const HEAVY_LUNGE_DISTANCE: float = 34.0
const HEAVY_ANTICIPATION_SCALE: float = 1.6
const PLAYER_INTENSITY: float = 1.2

# --- Hit reactions ---
const WHITE_FLASH: float = 0.04
const FLASH: float = 0.10
const REACTION_SHAKE: float = 0.10
const KNOCKBACK: float = 6.0
const CRIT_KNOCKBACK: float = 10.0
const HEAVY_KNOCKBACK: float = 12.0
const REACTION_SHAKE_AMPLITUDE: float = 3.0

# --- Hit stop (never Engine.time_scale; pauses token motion tweens only) ---
const HITSTOP_NORMAL: float = 0.04
const HITSTOP_CRIT: float = 0.065
const HITSTOP_HEAVY: float = 0.08

# --- Camera shake (x = intensity px, y = duration seconds) ---
const SHAKE_NORMAL: Vector2 = Vector2(1.5, 0.06)
const SHAKE_CRIT: Vector2 = Vector2(4.0, 0.10)
const SHAKE_HEAVY: Vector2 = Vector2(6.5, 0.14)

# --- Damage numbers ---
const NUMBER_LIFETIME: float = 0.8
const NUMBER_RISE: float = 34.0
const NUMBER_FONT_SIZE: int = 19
const NUMBER_FONT_SIZE_CRIT: int = 26
const NUMBER_OUTLINE_COLOR: Color = Color("0d0810", 0.9)

# --- VFX ---
const IMPACT_LIFETIME: float = 0.22
const PROJECTILE_TRAVEL: float = 0.18

# --- Death ---
const DEATH_DURATION: float = 0.45
const DEATH_DELAY: float = 0.12

# --- Colors (dark-gothic palette) ---
const COLOR_DAMAGE: Color = Color("f1e6d0")
const COLOR_CRIT: Color = Color("f1d277")
const COLOR_HEAL: Color = Color("82d49b")
const COLOR_POISON: Color = Color("9fd35a")
const COLOR_MISS: Color = Color("b9b2c4")
const COLOR_BLOCK: Color = Color("9fb6c9")
const COLOR_FIRE: Color = Color("e07840")
const COLOR_ICE: Color = Color("9fd8e8")
const COLOR_LIGHTNING: Color = Color("d8c8ff")
const COLOR_DARK: Color = Color("b06ae0")
const COLOR_HOLY: Color = Color("e8d8a0")
const COLOR_BLEED: Color = Color("c9556e")


## Single conversion point from the Auto/Farm speed state (owned by
## AutoCombatController — the only speed system) to a presentation duration
## multiplier. Lower value = faster presentation.
static func get_speed_multiplier(auto_or_farming: bool, game_speed: int) -> float:
	match game_speed:
		AutoCombatController.GameSpeed.FASTEST:
			return 0.45
		AutoCombatController.GameSpeed.X2:
			return 0.7
	if auto_or_farming:
		return 0.7
	return 1.0
