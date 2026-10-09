class_name ConverseTask
extends VillagerTask
## Standing with another villager, talking. Created by the ConversationSystem,
## which also decides when it ends (`done`).

const SAFETY_TIMEOUT := 15.0

var partner: Villager
var done := false
## &"talk", &"warm", &"romance", &"argue", &"fight" - drives the animation.
var style: StringName = &"talk"
var _elapsed := 0.0


func _init(v: Villager, other: Villager) -> void:
	super(v, &"converse")
	partner = other


func start() -> bool:
	villager.movement.stop()
	villager.set_state(VillagerState.SOCIALIZING)
	if is_instance_valid(partner):
		villager.face_towards(partner.global_position)
	return true


func tick(dt: float) -> int:
	villager.activity = 0.2
	_elapsed += dt
	if done:
		return Status.SUCCEEDED
	if _elapsed > SAFETY_TIMEOUT or not is_instance_valid(partner):
		return _fail("Conversation broke off")
	villager.face_towards(partner.global_position)
	return Status.RUNNING


func describe() -> String:
	return "Talking with %s" % (partner.villager_name if is_instance_valid(partner) else "someone")
