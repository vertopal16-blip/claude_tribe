class_name VillagerNeeds
extends RefCounted
## Physical needs of a villager: hunger, energy and the health they drive.
## Pure data + rules; knows nothing about tasks, AI or the scene.

var health := 100.0
var hunger := 0.0  # 0 = full, 100 = starving
var energy := 100.0

var _cfg: GameConfig


func _init(cfg: GameConfig) -> void:
	_cfg = cfg


## activity: 0 = resting .. 1 = hard work. rest_multiplier > 0 while resting.
func tick(dt: float, activity: float, rest_multiplier: float) -> void:
	# Sleeping slows hunger a bit.
	var hunger_mult := 0.6 if rest_multiplier > 0.0 else 1.0
	hunger = minf(100.0, hunger + _cfg.hunger_rate * hunger_mult * dt)
	if rest_multiplier > 0.0:
		energy = minf(100.0, energy + _cfg.energy_recovery * rest_multiplier * dt)
	else:
		energy = maxf(0.0, energy - _cfg.energy_drain * lerpf(0.35, 1.0, activity) * dt)

	if hunger >= 100.0:
		health -= _cfg.starvation_damage * dt
	if energy <= 0.0:
		health -= _cfg.exhaustion_damage * dt
	if hunger < _cfg.hungry_threshold and energy > _cfg.tired_threshold:
		health += _cfg.health_regen * dt
	health = clampf(health, 0.0, 100.0)


func eat(food_units: int) -> void:
	hunger = maxf(0.0, hunger - food_units * _cfg.food_hunger_value)


## Food units needed to become (almost) full.
func food_wanted() -> int:
	return int(ceil(maxf(0.0, hunger - 5.0) / _cfg.food_hunger_value))


func is_hungry() -> bool:
	return hunger >= _cfg.hungry_threshold


func is_starving() -> bool:
	return hunger >= _cfg.critical_hunger


func is_tired() -> bool:
	return energy <= _cfg.tired_threshold


func is_exhausted() -> bool:
	return energy <= _cfg.tired_threshold * 0.4


func is_dead() -> bool:
	return health <= 0.0


## Movement/work slow down when exhausted or starving.
func performance() -> float:
	var p := 1.0
	if energy < 10.0:
		p *= 0.6
	if hunger >= 100.0:
		p *= 0.75
	return p
