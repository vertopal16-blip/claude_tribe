class_name FarmTask
extends WorkSiteTask
## Tend a farm until the crop ripens, then harvest it and carry the food home.

const TEND_PER_SECOND := 0.012
const BASE_YIELD := 10.0

var _harvested := false
var _delivering := false
var _work_time := 0.0


func start() -> bool:
	site = ctx.society.find_workplace(villager, &"farm")
	if site == null or not villager.inventory.is_empty():
		return false
	villager.set_state(VillagerState.MOVING_TO_RESOURCE)
	return _go_to_site()


func tick(dt: float) -> int:
	if not is_instance_valid(site):
		return _fail("The farm is gone")
	if _delivering:
		match villager.movement.status:
			VillagerMovement.ARRIVED:
				ctx.tribe.deposit_inventory(villager)
				return Status.SUCCEEDED
			VillagerMovement.FAILED:
				return _fail("Can't reach the stockpile")
		return Status.RUNNING
	var t := _travel()
	if t != Status.SUCCEEDED:
		return t
	villager.set_state(VillagerState.GATHERING)
	villager.activity = 1.0
	var eff := villager.work_efficiency(&"farming")
	villager.practice(&"farming", dt)
	_work_time += dt
	if site.tend(TEND_PER_SECOND * eff * dt):
		var food := int(round(BASE_YIELD * eff))
		site.harvest_crop()
		ctx.society.on_harvest(villager, site, food)
		villager.inventory.add(ResourceType.FOOD, mini(food, villager.inventory.capacity))
		_delivering = true
		villager.set_state(VillagerState.RETURNING)
		if not _go_to_stockpile():
			return _fail("Can't reach the stockpile")
		return Status.RUNNING
	# A long session of tending is enough for now.
	return Status.SUCCEEDED if _work_time > 40.0 else Status.RUNNING


func describe() -> String:
	if _delivering:
		return "Carrying the harvest home"
	return "Tending the farm" if _at_site else "Walking to the farm"
