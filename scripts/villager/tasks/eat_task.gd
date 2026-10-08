class_name EatTask
extends VillagerTask
## Eat from (in order of preference) carried food, the stockpile, or a bush.

enum Source { INVENTORY, STOCKPILE, BUSH }

const EAT_TIME := 2.0

var source: int = Source.INVENTORY
var bush: ResourceNode
var _eating := false
var _timer := 0.0
var _reserved := false


func start() -> bool:
	if villager.needs.food_wanted() <= 0:
		return false
	if villager.inventory.carried_type == ResourceType.FOOD:
		source = Source.INVENTORY
		_begin_eating()
		return true
	if ctx.tribe.stockpile.get_amount(ResourceType.FOOD) > 0 and _go_to_stockpile():
		source = Source.STOCKPILE
		villager.set_state(VillagerState.RETURNING)
		return true
	return _find_bush()


func _find_bush() -> bool:
	var region := villager.get_region()
	for attempt in 3:
		var candidate := ctx.resources.find_best(ResourceType.FOOD, villager.global_position, region,
				villager.brain.get_blacklist())
		if candidate == null or not candidate.reserve():
			return false
		if villager.movement.move_to(candidate.global_position, 3):
			bush = candidate
			_reserved = true
			source = Source.BUSH
			villager.set_state(VillagerState.SEARCHING_FOOD)
			return true
		candidate.release()
		villager.brain.mark_unreachable(candidate)
	return false


func _begin_eating() -> void:
	_eating = true
	_timer = 0.0
	villager.set_state(VillagerState.EATING)


func tick(dt: float) -> int:
	if _eating:
		villager.activity = 0.2
		_timer += dt
		if _timer < EAT_TIME:
			return Status.RUNNING
		return _consume()
	if source == Source.BUSH and (not is_instance_valid(bush) or not bush.is_harvestable()):
		_release()
		return Status.SUCCEEDED if not villager.needs.is_hungry() else _retry_bush()
	match villager.movement.status:
		VillagerMovement.ARRIVED:
			if source == Source.BUSH:
				villager.face_towards(bush.global_position)
			_begin_eating()
		VillagerMovement.FAILED:
			if source == Source.BUSH:
				villager.brain.mark_unreachable(bush)
				_release()
				return _retry_bush()
			return _fail("Can't reach the stockpile")
	return Status.RUNNING


func _retry_bush() -> int:
	return Status.RUNNING if _find_bush() else _fail("No food nearby")


func _consume() -> int:
	var wanted := villager.needs.food_wanted()
	var got := 0
	match source:
		Source.INVENTORY:
			got = villager.inventory.remove(wanted)
		Source.STOCKPILE:
			got = ctx.tribe.stockpile.take(ResourceType.FOOD, wanted)
		Source.BUSH:
			if is_instance_valid(bush):
				got = bush.harvest(wanted)
	if got <= 0:
		return _fail("The food was gone")
	villager.needs.eat(got)
	EventBus.villager_event.emit(villager, &"ate", {"amount": got, "source": source})
	return Status.SUCCEEDED


func _release() -> void:
	if _reserved and is_instance_valid(bush):
		bush.release()
	_reserved = false


func _on_finish() -> void:
	_release()
	villager.movement.stop()


func is_interruptible() -> bool:
	return false


func describe() -> String:
	if _eating:
		return "Eating"
	match source:
		Source.STOCKPILE: return "Going to the stockpile to eat"
		Source.BUSH: return "Searching for berries to eat"
	return "Eating"
