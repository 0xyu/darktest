extends SceneTree

const SubHeroDataScript = preload("res://scripts/sub_hero/sub_hero_data.gd")
const SubHeroInstanceScript = preload("res://scripts/sub_hero/sub_hero_instance.gd")
const SubHeroQualityScript = preload("res://scripts/sub_hero/sub_hero_quality.gd")

const RESOURCE_PATHS: Array[String] = [
	"res://resources/sub_heroes/common/SkeletonArcher.tres",
	"res://resources/sub_heroes/common/GoblinGunner.tres",
	"res://resources/sub_heroes/common/DarkServant.tres",
	"res://resources/sub_heroes/rare/PoisonWitch.tres",
	"res://resources/sub_heroes/rare/DarkRanger.tres",
	"res://resources/sub_heroes/rare/PlagueDoctor.tres",
	"res://resources/sub_heroes/legendary/DeathKnight.tres",
	"res://resources/sub_heroes/legendary/DemonMage.tres",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var quality_counts: Dictionary = {}
	for resource_path in RESOURCE_PATHS:
		var data: Resource = load(resource_path)
		_expect(data != null, "%s should load as SubHeroData" % resource_path)
		if data == null:
			continue
		_expect(data.get_script() == SubHeroDataScript, "%s should use SubHeroData" % resource_path)
		_expect(bool(data.call("is_valid")), "%s should contain valid definition data" % data.get("display_name"))
		quality_counts[int(data.get("quality"))] = int(quality_counts.get(int(data.get("quality")), 0)) + 1

	_expect(quality_counts.get(SubHeroQualityScript.COMMON, 0) == 3, "three Common Sub Heroes should exist")
	_expect(quality_counts.get(SubHeroQualityScript.RARE, 0) == 3, "three Rare Sub Heroes should exist")
	_expect(quality_counts.get(SubHeroQualityScript.LEGENDARY, 0) == 2, "two Legendary Sub Heroes should exist")

	var original: Resource = SubHeroInstanceScript.new(&"skeleton_archer", 3)
	original.call("add_duplicate", 2)
	var restored: Resource = SubHeroInstanceScript.from_save_data(original.call("to_save_data"))
	_expect(restored.get("hero_id") == original.get("hero_id"), "instance hero id should round-trip")
	_expect(restored.get("level") == original.get("level"), "instance level should round-trip")
	_expect(restored.get("duplicate_count") == original.get("duplicate_count"), "duplicate count should round-trip")

	if _failures.is_empty():
		print("Sub Hero data smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
