class_name EnemySummaryPanel
extends PanelContainer

## Compact, grouped roster of the enemies currently on the battlefield.
##
## Renders one card per group of identical enemy profiles inside the row this
## scene exposes (`%EnemySummaryRow`). The combat HUD owns world access, so it
## feeds the live spawned-enemy list in through `update_enemies()` on every
## refresh. The row's children are rebuilt only when the group composition
## actually changes, so per-frame HUD ticks never churn the node tree.

const ENEMY_SUMMARY_CARD_COLOR := Color("151321")
const ENEMY_SUMMARY_CARD_BORDER := Color("49384a")
const ENEMY_SUMMARY_TITLE_COLOR := Color("d9b565")
const ENEMY_SUMMARY_TEXT_COLOR := Color("d8cfdf")
const ENEMY_SUMMARY_MUTED_COLOR := Color("9d93ae")

@onready var _enemy_summary_row: HBoxContainer = %EnemySummaryRow

var _enemy_summary_signature: String = ""


func update_enemies(spawned_enemies: Array[EnemyController]) -> void:
	if _enemy_summary_row == null:
		return
	var grouped_enemies: Dictionary = {}
	for enemy in spawned_enemies:
		if enemy == null or not is_instance_valid(enemy) or enemy.is_defeated():
			continue
		var enemy_stats: EnemyStats = enemy.enemy_stats
		if enemy_stats == null:
			continue
		var enemy_name: String = enemy.get_display_name()
		var summary_key: String = _get_enemy_summary_key(enemy, enemy_stats, enemy_name)
		if not grouped_enemies.has(summary_key):
			grouped_enemies[summary_key] = {
				"enemy_name": enemy_name,
				"enemy_level": enemy.enemy_level,
				"max_hp": enemy_stats.max_hp,
				"attack": enemy_stats.attack,
				"defense": enemy_stats.defense,
				"movement_points": enemy_stats.movement_points,
				"attack_range": enemy_stats.attack_range,
				"count": 0,
			}
		grouped_enemies[summary_key]["count"] += 1

	var summary_parts: Array[String] = []
	for summary_key: String in grouped_enemies.keys():
		summary_parts.append("%s:%d" % [summary_key, int(grouped_enemies[summary_key]["count"])])
	summary_parts.sort()
	var summary_signature: String = "|".join(summary_parts) if not summary_parts.is_empty() else "NONE"
	if summary_signature == _enemy_summary_signature:
		return
	_enemy_summary_signature = summary_signature

	for child in _enemy_summary_row.get_children():
		child.free()

	if grouped_enemies.is_empty():
		var empty_label := Label.new()
		empty_label.text = "FIELD MONSTERS  •  NONE"
		empty_label.add_theme_color_override("font_color", ENEMY_SUMMARY_MUTED_COLOR)
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_enemy_summary_row.add_child(empty_label)
		return

	for summary: Dictionary in grouped_enemies.values():
		_enemy_summary_row.add_child(_create_enemy_summary_card(summary))


func _get_enemy_summary_key(enemy: EnemyController, enemy_stats: EnemyStats, enemy_name: String) -> String:
	var enemy_type: int = enemy.enemy_definition.enemy_type if enemy.enemy_definition != null else EnemyType.NORMAL
	return "%s|%d|%d|%d|%d|%d|%d|%d" % [
		enemy_name,
		enemy.enemy_level,
		enemy_type,
		enemy_stats.max_hp,
		enemy_stats.attack,
		enemy_stats.defense,
		enemy_stats.movement_points,
		enemy_stats.attack_range,
	]


func _create_enemy_summary_card(summary: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 64.0)
	card.add_theme_stylebox_override("panel", _make_enemy_summary_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 5)
	card.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	margin.add_child(content)

	var name_label := Label.new()
	name_label.text = "%s  LV.%d  ×%d" % [str(summary["enemy_name"]).to_upper(), int(summary["enemy_level"]), int(summary["count"])]
	name_label.add_theme_color_override("font_color", ENEMY_SUMMARY_TITLE_COLOR)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(name_label)

	var primary_stats_label := Label.new()
	primary_stats_label.text = "HP %d  ATK %d  DEF %d" % [int(summary["max_hp"]), int(summary["attack"]), int(summary["defense"])]
	primary_stats_label.add_theme_color_override("font_color", ENEMY_SUMMARY_TEXT_COLOR)
	primary_stats_label.add_theme_font_size_override("font_size", 9)
	primary_stats_label.clip_text = true
	content.add_child(primary_stats_label)

	var secondary_stats_label := Label.new()
	secondary_stats_label.text = "MOV %d  RNG %d" % [int(summary["movement_points"]), int(summary["attack_range"])]
	secondary_stats_label.add_theme_color_override("font_color", ENEMY_SUMMARY_MUTED_COLOR)
	secondary_stats_label.add_theme_font_size_override("font_size", 9)
	content.add_child(secondary_stats_label)
	return card


func _make_enemy_summary_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ENEMY_SUMMARY_CARD_COLOR
	style.border_color = ENEMY_SUMMARY_CARD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
