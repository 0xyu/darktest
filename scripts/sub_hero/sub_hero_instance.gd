class_name SubHeroInstance
extends Resource

## Mutable ownership/progression state for one owned Sub Hero.
##
## `hero_id` resolves to a SubHeroData resource through the collection or
## registry that owns this instance. The instance intentionally does not
## duplicate or mutate the shared definition.
@export var hero_id: StringName = &""
@export_range(1, 999999, 1) var level: int = 1
@export_range(0, 999999, 1) var duplicate_count: int = 0


func _init(source_hero_id: StringName = &"", source_level: int = 1) -> void:
	hero_id = source_hero_id
	level = maxi(source_level, 1)


func add_duplicate(amount: int = 1) -> void:
	duplicate_count = maxi(duplicate_count + maxi(amount, 0), 0)


func to_save_data() -> Dictionary:
	return {
		"hero_id": String(hero_id),
		"level": maxi(level, 1),
		"duplicate_count": maxi(duplicate_count, 0),
	}


static func from_save_data(save_data: Dictionary) -> SubHeroInstance:
	var instance := SubHeroInstance.new(
		StringName(str(save_data.get("hero_id", ""))),
		int(save_data.get("level", 1))
	)
	instance.duplicate_count = maxi(int(save_data.get("duplicate_count", 0)), 0)
	return instance
