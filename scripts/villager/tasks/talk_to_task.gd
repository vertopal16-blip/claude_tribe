class_name TalkToTask
extends VillagerTask
## Seek out one particular person for a purposeful conversation (mediating a
## feud, campaigning, persuading about a project).

const RANGE := 2.8

var target: Villager
var topic: StringName
var _repath := 0.0
var _elapsed := 0.0


func _init(v: Villager, goal: StringName, who: Villager, what: StringName) -> void:
	super(v, goal)
	target = who
	topic = what


func start() -> bool:
	if target == null or not SocializeTask.approachable(target):
		return false
	villager.set_state(VillagerState.SOCIALIZING)
	return villager.movement.move_to(target.global_position, 3)


func tick(dt: float) -> int:
	_elapsed += dt
	if not is_instance_valid(target) or target.is_dead or _elapsed > 45.0:
		return _fail("Couldn't find them")
	if villager.global_position.distance_to(target.global_position) <= RANGE:
		if not SocializeTask.approachable(target):
			return _fail("They were busy")
		if not ctx.social.conversations.start(villager, target, topic):
			return _fail("They were busy")
		return Status.RUNNING
	_repath += dt
	if _repath >= 2.0 or villager.movement.status != VillagerMovement.MOVING:
		_repath = 0.0
		if not villager.movement.move_to(target.global_position, 3):
			return _fail("Can't reach them")
	return Status.RUNNING


func _on_finish() -> void:
	villager.movement.stop()


func describe() -> String:
	return "Going to talk with %s" % (target.villager_name if is_instance_valid(target) else "someone")
