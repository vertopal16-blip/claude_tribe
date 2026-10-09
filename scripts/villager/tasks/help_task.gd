class_name HelpTask
extends VillagerTask
## Bring carried food to someone close who is going hungry, then hand it over
## through a conversation (so it is validated like any other social exchange).

const HANDOVER_RANGE := 2.6
const REPATH_INTERVAL := 2.0

var target: Villager
var _repath_timer := 0.0


func start() -> bool:
	if villager.inventory.carried_type != ResourceType.FOOD:
		return false
	target = ctx.social.find_person_to_help(villager)
	if target == null:
		return false
	villager.set_state(VillagerState.DELIVERING)
	return villager.movement.move_to(target.global_position, 3)


func tick(dt: float) -> int:
	if not is_instance_valid(target) or target.is_dead or villager.inventory.carried_type != ResourceType.FOOD:
		return _fail("No one to help")
	if not target.needs.is_hungry():
		return Status.SUCCEEDED
	if villager.global_position.distance_to(target.global_position) <= HANDOVER_RANGE and not target.is_hidden():
		# Hands over to the conversation system; our task gets replaced.
		ctx.social.conversations.start(villager, target, &"offer_food")
		return Status.RUNNING
	_repath_timer += dt
	if _repath_timer >= REPATH_INTERVAL or villager.movement.status != VillagerMovement.MOVING:
		_repath_timer = 0.0
		if not villager.movement.move_to(target.global_position, 3):
			return _fail("Can't reach them")
	return Status.RUNNING


func _on_finish() -> void:
	villager.movement.stop()


func describe() -> String:
	return "Bringing food to %s" % (target.villager_name if is_instance_valid(target) else "someone")
