class_name CraftTask
extends WorkSiteTask
## Toolmaking: fetch wood and stone from the stockpile, take them to the
## workshop and turn them into a tool. Nothing is made from nothing.

const WOOD_COST := 3
const STONE_COST := 2
const WORK_NEEDED := 18.0

var _have_materials := false
var _fetching := false
var _work := 0.0


func start() -> bool:
	site = ctx.society.find_workplace(villager, &"workshop")
	if site == null or not villager.inventory.is_empty():
		return false
	var stock := ctx.tribe.stockpile
	if stock.get_amount(ResourceType.WOOD) < WOOD_COST or stock.get_amount(ResourceType.STONE) < STONE_COST:
		return false
	_fetching = true
	villager.set_state(VillagerState.RETURNING)
	return _go_to_stockpile()


func tick(dt: float) -> int:
	if not is_instance_valid(site):
		return _fail("The workshop is gone")
	if _fetching:
		match villager.movement.status:
			VillagerMovement.ARRIVED:
				var stock := ctx.tribe.stockpile
				if stock.get_amount(ResourceType.WOOD) < WOOD_COST or stock.get_amount(ResourceType.STONE) < STONE_COST:
					return _fail("Not enough materials")
				stock.take(ResourceType.WOOD, WOOD_COST)
				stock.take(ResourceType.STONE, STONE_COST)
				villager.inventory.add(ResourceType.STONE, 1)  # visibly carrying materials
				_have_materials = true
				_fetching = false
				villager.set_state(VillagerState.DELIVERING)
				if not _go_to_site():
					return _fail("Can't reach the workshop")
			VillagerMovement.FAILED:
				return _fail("Can't reach the stockpile")
		return Status.RUNNING
	var t := _travel()
	if t != Status.SUCCEEDED:
		return t
	villager.set_state(VillagerState.BUILDING)
	villager.activity = 0.9
	villager.practice(&"toolmaking", dt)
	_work += dt * villager.work_efficiency(&"toolmaking")
	if _work >= WORK_NEEDED:
		villager.inventory.take_all()
		_have_materials = false
		ctx.society.economy.tool_made(villager)
		return Status.SUCCEEDED
	return Status.RUNNING


func _on_finish() -> void:
	# Materials taken but no tool made: they go back to the stockpile.
	if _have_materials:
		villager.inventory.take_all()
		ctx.tribe.stockpile.add(ResourceType.WOOD, WOOD_COST)
		ctx.tribe.stockpile.add(ResourceType.STONE, STONE_COST)
	super()


func describe() -> String:
	if _fetching:
		return "Fetching wood and stone for a tool"
	return "Making a tool" if _at_site else "Carrying materials to the workshop"
