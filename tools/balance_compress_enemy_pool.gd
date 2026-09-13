extends SceneTree

## §4.2 one-time data transform: compress the 24 generated enemies' combat stats into the
## reference band `0.9 .. 1.1` of the normal reference enemy.
##
##     new_X = reference_X * (0.9 + 0.2 * (old_X - pool_min_X) / (pool_max_X - pool_min_X))
##
## The old values are read from the resources as they are TODAY, and the result is written into
## the same `[sub_resource]` block textually: the `uid`, the ext_resource table and every other
## field of the file stay exactly as they were, because a `ResourceSaver` round trip would rewrite
## the whole file and could drop the uid the registry references.
##
## It runs ONCE. Applying it twice would compress the already-compressed band towards its own
## middle, so the tool refuses to run when every stat is already inside the band, and it writes
## the old → new table to `docs/balance-enemy-pool.md` as the record of what it changed.
##
## EXP and Gold are deliberately NOT touched: §4.2 normalizes EXP to 100 together with the reward
## formula switch (R2), and R1 moves the combat stats only.
##
## Usage: godot --headless --path . -s res://tools/balance_compress_enemy_pool.gd [--force]

const POOL_DIR: String = "res://resources/enemies/generated"
const RECORD_PATH: String = "res://docs/balance-enemy-pool.md"
const PROFILE_PATH: String = "res://resources/balance/balance_profile_default.tres"

## Below this share of the band the pool counts as "already compressed" (the guard against a
## second run).
const BAND_TOLERANCE: float = 0.001

const STAT_FIELDS: Array[String] = ["max_hp", "attack", "defense"]
const REFERENCE_FIELDS: Dictionary = {
	"max_hp": "reference_enemy_hp",
	"attack": "reference_enemy_attack",
	"defense": "reference_enemy_defense",
}


func _init() -> void:
	var profile: BalanceProfile = load(PROFILE_PATH) as BalanceProfile
	if profile == null:
		push_error("balance_compress_enemy_pool: cannot load %s" % PROFILE_PATH)
		quit(1)
		return
	var paths: Array[String] = _pool_paths()
	if paths.is_empty():
		push_error("balance_compress_enemy_pool: no enemy resources under %s" % POOL_DIR)
		quit(1)
		return
	var values: Dictionary = {}
	for path in paths:
		var enemy_data: EnemyData = load(path) as EnemyData
		if enemy_data == null or enemy_data.base_stats == null:
			push_warning("balance_compress_enemy_pool: skipping %s (no base stats)" % path)
			continue
		values[path] = {
			"max_hp": float(enemy_data.base_stats.max_hp),
			"attack": float(enemy_data.base_stats.attack),
			"defense": float(enemy_data.base_stats.defense),
		}
	if _already_compressed(profile, values):
		print("balance_compress_enemy_pool: pool already inside the reference band; nothing to do.")
		quit(0)
		return

	var rows: Array[String] = []
	var changed_files: int = 0
	for path in values:
		var old_values: Dictionary = values[path]
		var new_values: Dictionary = {}
		for field in STAT_FIELDS:
			new_values[field] = _compress(
				profile,
				field,
				float(old_values[field]),
				_pool_extreme(values, field, true),
				_pool_extreme(values, field, false)
			)
		if _rewrite_resource(path, old_values, new_values):
			changed_files += 1
		rows.append(_record_row(path, old_values, new_values))
	_write_record(profile, values, rows)
	print("balance_compress_enemy_pool: compressed %d enemies, %d files rewritten." % [values.size(), changed_files])
	print("balance_compress_enemy_pool: record written to %s" % RECORD_PATH)
	quit(0)


func _pool_paths() -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open(POOL_DIR)
	if directory == null:
		return paths
	for file_name in directory.get_files():
		if file_name.ends_with(".tres"):
			paths.append("%s/%s" % [POOL_DIR, file_name])
	paths.sort()
	return paths


## The first-order guard against running the transform twice: every stat of every enemy already
## inside the band means the pool has been compressed once and doing it again would only squeeze
## the identities together.
func _already_compressed(profile: BalanceProfile, values: Dictionary) -> bool:
	for path in values:
		var entry: Dictionary = values[path]
		for field in STAT_FIELDS:
			var reference: float = float(profile.get(REFERENCE_FIELDS[field]))
			var ratio: float = float(entry[field]) / reference
			if ratio < 0.9 - BAND_TOLERANCE or ratio > 1.1 + BAND_TOLERANCE:
				return false
	return not values.is_empty()


func _pool_extreme(values: Dictionary, field: String, want_minimum: bool) -> float:
	var extreme: float = 0.0
	var has_value: bool = false
	for path in values:
		var value: float = float((values[path] as Dictionary)[field])
		if not has_value:
			extreme = value
			has_value = true
		elif want_minimum:
			extreme = minf(extreme, value)
		else:
			extreme = maxf(extreme, value)
	return extreme


## `new_X = reference_X * (0.9 + 0.2 * (old_X - min) / (max - min))`; a flat pool (min == max)
## falls back to the reference value itself, and every result is validated as a positive integer.
func _compress(profile: BalanceProfile, field: String, old_value: float, pool_min: float, pool_max: float) -> int:
	var reference: float = float(profile.get(REFERENCE_FIELDS[field]))
	var new_value: float = reference
	if not is_zero_approx(pool_max - pool_min):
		new_value = reference * (0.9 + 0.2 * (old_value - pool_min) / (pool_max - pool_min))
	return clampi(roundi(new_value), 1, int(profile.max_combat_value))


## Rewrites the three stat lines of one resource IN PLACE. A property the file never wrote (the
## resource falls back to the class default) is inserted after the script line of its
## `[sub_resource]` block, so nothing else about the file moves.
func _rewrite_resource(path: String, old_values: Dictionary, new_values: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("balance_compress_enemy_pool: cannot read %s" % path)
		return false
	var text: String = file.get_as_text()
	file.close()
	var lines: PackedStringArray = text.split("\n")
	var changed: bool = false
	for field in STAT_FIELDS:
		var new_line: String = "%s = %d" % [field, int(new_values[field])]
		var replaced: bool = false
		for index in lines.size():
			if lines[index].begins_with("%s = " % field):
				if lines[index] != new_line:
					lines[index] = new_line
					changed = true
				replaced = true
				break
		if replaced:
			continue
		# The property was never written and defaulted: put it right after the sub-resource
		# script line, which is where the resource file format expects a first property.
		for index in lines.size():
			if lines[index].begins_with("script = "):
				lines.insert(index + 1, new_line)
				changed = true
				break
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		push_error("balance_compress_enemy_pool: cannot write %s" % path)
		return false
	output.store_string("\n".join(lines))
	output.close()
	return changed


func _record_row(path: String, old_values: Dictionary, new_values: Dictionary) -> String:
	return "| %s | %d → %d | %d → %d | %d → %d |" % [
		path.get_file().trim_suffix(".tres").trim_prefix("enemy_atlas_"),
		int(old_values["max_hp"]), int(new_values["max_hp"]),
		int(old_values["attack"]), int(new_values["attack"]),
		int(old_values["defense"]), int(new_values["defense"]),
	]


func _write_record(profile: BalanceProfile, values: Dictionary, rows: Array[String]) -> void:
	var header: Array[String] = [
		"# Generated enemy pool: reference compression record",
		"",
		"> Generated once by `tools/balance_compress_enemy_pool.gd` (contract §4.2).",
		"> Do not run the tool again: the OLD column below is the pre-compression value.",
		"",
		"`new_X = reference_X * (0.9 + 0.2 * (old_X - pool_min_X) / (pool_max_X - pool_min_X))`",
		"with `reference_X` = HP %.1f / ATK %.1f / DEF %.1f." % [
			profile.reference_enemy_hp,
			profile.reference_enemy_attack,
			profile.reference_enemy_defense,
		],
		"EXP and Gold are untouched — §4.2 normalizes EXP to 100 with the R2 reward switch.",
		"",
		"| Enemy | HP | ATK | DEF |",
		"|---|---:|---:|---:|",
	]
	var text: String = "\n".join(header + rows) + "\n"
	var file := FileAccess.open(RECORD_PATH, FileAccess.WRITE)
	if file == null:
		push_error("balance_compress_enemy_pool: cannot write %s" % RECORD_PATH)
		return
	file.store_string(text)
	file.close()
