class_name EnemyType
extends RefCounted

enum {
	NORMAL,
	ELITE,
	SPECIAL,
	MINI_BOSS,
	TREASURE,
	GOLD,
	CURSED,
}


static func is_boss(enemy_type: int) -> bool:
	return enemy_type == MINI_BOSS
