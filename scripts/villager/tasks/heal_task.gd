class_name HealTask
extends VillagerTask
## A healer brings herbs (food from the stockpile) to an injured or sick
## villager and treats them.

const HEAL_PER_SECOND := 2.5

var patient: Villager
var _treating := 0.0


func start() -> bool:
	patient = ctx.society.find_patient(villager)
	if patient == null or ctx.tribe.stockpile.take(ResourceType.FOOD, 1) <= 0:
		return false
	villager.set_state(VillagerState.DELIVERING)
	return villager.movement.move_to(patient.global_position, 3)


func tick(dt: float) -> int:
	if not is_instance_valid(patient) or patient.is_dead:
		return _fail("The patient is gone")
	if villager.global_position.distance_to(patient.global_position) > 2.8:
		if villager.movement.status != VillagerMovement.MOVING and not villager.movement.move_to(patient.global_position, 3):
			return _fail("Can't reach the patient")
		return Status.RUNNING
	villager.movement.stop()
	villager.set_state(VillagerState.BUILDING)
	villager.face_towards(patient.global_position)
	villager.practice(&"healing", dt)
	patient.needs.health = minf(100.0, patient.needs.health + HEAL_PER_SECOND * villager.work_efficiency(&"healing") * dt)
	_treating += dt
	if patient.needs.health >= 90.0 or _treating > 25.0:
		ctx.social.remember(patient, &"was_helped", villager.villager_id)
		ctx.social.remember(villager, &"helped", patient.villager_id)
		return Status.SUCCEEDED
	return Status.RUNNING


func describe() -> String:
	return "Treating %s" % (patient.villager_name if is_instance_valid(patient) else "a patient")
