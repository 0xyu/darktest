class_name SubHeroCatalog
extends RefCounted

## Content lookup for the initial Sub Hero definitions. The catalog is kept
## separate from ownership so save data only needs to store hero ids.
const DATA_PATHS: Array[String] = [
	"res://resources/sub_heroes/common/SkeletonArcher.tres",
	"res://resources/sub_heroes/common/GoblinGunner.tres",
	"res://resources/sub_heroes/common/DarkServant.tres",
	"res://resources/sub_heroes/rare/PoisonWitch.tres",
	"res://resources/sub_heroes/rare/DarkRanger.tres",
	"res://resources/sub_heroes/rare/PlagueDoctor.tres",
	"res://resources/sub_heroes/legendary/DeathKnight.tres",
	"res://resources/sub_heroes/legendary/DemonMage.tres",
]


static func get_data(hero_id: StringName) -> SubHeroData:
	for data_path in DATA_PATHS:
		var data := load(data_path) as SubHeroData
		if data != null and data.id == hero_id:
			return data
	return null


static func get_all_data() -> Array[SubHeroData]:
	var result: Array[SubHeroData] = []
	for data_path in DATA_PATHS:
		var data := load(data_path) as SubHeroData
		if data != null:
			result.append(data)
	return result
