class_name WorkSiteTask
extends VillagerTask
## Shared base for work done at a building (farm, workshop): walk there,
## claim a work spot, work, and release the spot when finished.

var site: Building
var _at_site := false
var _claimed := false


func _go_to_site() -> bool:
	if site == null:
		return false
	site.workers += 1
	_claimed = true
	if _near_building(site, 2.2):
		_at_site = true
		return true
	return villager.movement.move_to(site.global_position, int(ceil(site.def.footprint_radius)) + 3)


## Returns RUNNING while walking, SUCCEEDED once there, FAILED if unreachable.
func _travel() -> int:
	if _at_site:
		return Status.SUCCEEDED
	match villager.movement.status:
		VillagerMovement.ARRIVED:
			_at_site = true
			villager.movement.stop()
			villager.face_towards(site.global_position)
			return Status.SUCCEEDED
		VillagerMovement.FAILED:
			return Status.FAILED
	return Status.RUNNING


func _on_finish() -> void:
	if _claimed and is_instance_valid(site):
		site.workers = maxi(0, site.workers - 1)
	_claimed = false
	villager.movement.stop()
