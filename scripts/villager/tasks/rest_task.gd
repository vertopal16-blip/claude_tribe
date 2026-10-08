class_name RestTask
extends VillagerTask
## Go home (a hut bed if one is free, otherwise beside the campfire) and rest.
## At night villagers sleep until morning.

var hut: Building
var _resting := false
var _multiplier := 1.0


func start() -> bool:
	hut = ctx.tribe.claim_bed(villager)
	var target: Vector3
	if hut != null:
		target = hut.global_position
		_multiplier = hut.def.rest_multiplier
	else:
		target = ctx.tribe.find_campfire_rest_spot(villager)
		_multiplier = ctx.tribe.campfire.def.rest_multiplier
	villager.set_state(VillagerState.RETURNING)
	if not villager.movement.move_to(target, 4):
		# Can't get anywhere better: rest where we stand (less effective).
		_begin_rest(0.7, false)
	return true


func _begin_rest(mult: float, inside: bool) -> void:
	_resting = true
	_multiplier = mult
	villager.movement.stop()
	villager.set_state(VillagerState.RESTING)
	villager.set_hidden(inside)
	if not inside:
		villager.face_towards(ctx.tribe.campfire.global_position)


func tick(_dt: float) -> int:
	if not _resting:
		match villager.movement.status:
			VillagerMovement.ARRIVED:
				_begin_rest(_multiplier, hut != null)
			VillagerMovement.FAILED:
				_begin_rest(0.7, false)
		return Status.RUNNING
	if hut != null and not is_instance_valid(hut):
		return _fail("Shelter lost")
	villager.activity = 0.0
	villager.rest_multiplier = _multiplier
	var needs := villager.needs
	if SimClock.is_night():
		return Status.RUNNING
	if needs.energy >= 95.0:
		return Status.SUCCEEDED
	return Status.RUNNING


func _on_finish() -> void:
	villager.rest_multiplier = 0.0
	villager.set_hidden(false)
	villager.movement.stop()


func describe() -> String:
	if not _resting:
		return "Going to %s to rest" % ("their hut" if hut else "the campfire")
	if hut != null:
		return "Sleeping in hut" if SimClock.is_night() else "Resting in hut"
	return "Sleeping by the campfire" if SimClock.is_night() else "Resting by the campfire"
