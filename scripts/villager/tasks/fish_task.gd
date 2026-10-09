class_name FishTask
extends VillagerTask
## Fish from the lake shore until the basket is full, then bring the catch home.

const CATCH_INTERVAL := 4.0

var _spot := Vector3.INF
var _fishing := false
var _timer := 0.0
var _returning := false


func start() -> bool:
	if not villager.inventory.is_empty():
		return false
	_spot = ctx.society.fishing_spot(villager)
	if _spot == Vector3.INF:
		return false
	villager.set_state(VillagerState.MOVING_TO_RESOURCE)
	return villager.movement.move_to(_spot, 4)


func tick(dt: float) -> int:
	if _returning:
		match villager.movement.status:
			VillagerMovement.ARRIVED:
				ctx.tribe.deposit_inventory(villager)
				return Status.SUCCEEDED
			VillagerMovement.FAILED:
				return _fail("Can't reach the stockpile")
		return Status.RUNNING
	if not _fishing:
		match villager.movement.status:
			VillagerMovement.ARRIVED:
				_fishing = true
				villager.set_state(VillagerState.GATHERING)
				var lake := ctx.terrain.lake_center
				villager.face_towards(Vector3(lake.x, 0, lake.y))
			VillagerMovement.FAILED:
				return _fail("Can't reach the water")
		return Status.RUNNING
	villager.activity = 0.6
	villager.practice(&"fishing", dt)
	_timer += dt
	if _timer >= CATCH_INTERVAL:
		_timer = 0.0
		# Skill decides how often something bites.
		if ctx.society.rng.randf() < clampf(0.25 + 0.5 * villager.work_efficiency(&"fishing") / 1.5, 0.1, 0.9):
			villager.inventory.add(ResourceType.FOOD, 1)
	if villager.inventory.is_full():
		_returning = true
		villager.set_state(VillagerState.RETURNING)
		if not _go_to_stockpile():
			return _fail("Can't reach the stockpile")
	return Status.RUNNING


func _on_finish() -> void:
	villager.movement.stop()


func describe() -> String:
	if _returning:
		return "Bringing the catch home"
	return "Fishing at the lake" if _fishing else "Walking to the lake"
