class_name SubHeroSummonTable
extends Resource

## Data-driven quality weights for Sub Hero summons.
## The values are deliberately kept outside the summon UI and combat code so
## balance changes do not require a script edit.
@export_range(0.0, 1000000.0, 0.1) var common_weight: float = 70.0
@export_range(0.0, 1000000.0, 0.1) var rare_weight: float = 25.0
@export_range(0.0, 1000000.0, 0.1) var legendary_weight: float = 5.0


func get_total_weight() -> float:
	return maxf(common_weight, 0.0) + maxf(rare_weight, 0.0) + maxf(legendary_weight, 0.0)


func is_valid() -> bool:
	return get_total_weight() > 0.0


func roll_quality(random_number_generator: RandomNumberGenerator) -> int:
	if random_number_generator == null or not is_valid():
		return SubHeroQuality.COMMON
	var roll: float = random_number_generator.randf() * get_total_weight()
	var common: float = maxf(common_weight, 0.0)
	if roll < common:
		return SubHeroQuality.COMMON
	roll -= common
	var rare: float = maxf(rare_weight, 0.0)
	if roll < rare:
		return SubHeroQuality.RARE
	return SubHeroQuality.LEGENDARY


func get_weight(quality: int) -> float:
	match quality:
		SubHeroQuality.COMMON:
			return maxf(common_weight, 0.0)
		SubHeroQuality.RARE:
			return maxf(rare_weight, 0.0)
		SubHeroQuality.LEGENDARY:
			return maxf(legendary_weight, 0.0)
		_:
			return 0.0
