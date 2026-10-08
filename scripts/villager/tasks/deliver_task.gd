class_name DeliverTask
extends VillagerTask
## Carry whatever is in the inventory to the stockpile.

var _delivering := false
var _timer := 0.0


func start() -> bool:
	if villager.inventory.is_empty():
		return false
	villager.set_state(VillagerState.RETURNING)
	return _go_to_stockpile()


func tick(dt: float) -> int:
	if _delivering:
		_timer += dt
		if _timer >= 0.6:
			ctx.tribe.deposit_inventory(villager)
			return Status.SUCCEEDED
		return Status.RUNNING
	match villager.movement.status:
		VillagerMovement.ARRIVED:
			_delivering = true
			villager.set_state(VillagerState.DELIVERING)
		VillagerMovement.FAILED:
			return _fail("Can't reach the stockpile")
	return Status.RUNNING


func _on_finish() -> void:
	villager.movement.stop()


func describe() -> String:
	return "Delivering %s" % villager.inventory.describe() if _delivering else "Bringing %s to the stockpile" % villager.inventory.describe()
