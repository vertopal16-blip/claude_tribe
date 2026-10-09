class_name CeremonyTask
extends VillagerTask
## Take part in a ceremony (funeral, feast, festival): go to the place and
## stay until it ends. The CultureSystem applies its effects to attendees.

var ceremony: Dictionary
var _arrived := false


func _init(v: Villager, goal: StringName, c: Dictionary) -> void:
	super(v, goal)
	ceremony = c


func start() -> bool:
	villager.set_state(VillagerState.SOCIALIZING)
	var a := villager.brain.rng.randf() * TAU
	var spot: Vector3 = ceremony["pos"] + Vector3(cos(a), 0, sin(a)) * villager.brain.rng.randf_range(2.5, 4.5)
	return villager.movement.move_to(spot, 4)


func tick(_dt: float) -> int:
	if not ctx.society.culture.is_active(ceremony):
		return Status.SUCCEEDED
	if not _arrived:
		match villager.movement.status:
			VillagerMovement.ARRIVED:
				_arrived = true
				ctx.society.culture.attend(ceremony, villager)
				villager.face_towards(ceremony["pos"])
			VillagerMovement.FAILED:
				return _fail("Couldn't get there")
	villager.activity = 0.2
	return Status.RUNNING


func describe() -> String:
	return "At the %s" % ceremony.get("name", "ceremony")
