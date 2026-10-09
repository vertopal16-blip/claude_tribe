class_name IdleTask
extends VillagerTask
## Filler activity: stroll around the camp for a few seconds, then let the
## brain re-evaluate. Never the first choice when useful work exists.

var _wait := 0.0
var _walking := false


func start() -> bool:
	villager.set_state(VillagerState.IDLE)
	var center := ctx.tribe.campfire.global_position
	# Children play close to a parent (or home).
	if villager.is_child():
		for pid in villager.parent_ids:
			var parent := ctx.social.get_villager(pid)
			if parent != null and not parent.is_hidden():
				center = parent.global_position
				break
	var a := ctx.rng.randf() * TAU
	var r := ctx.rng.randf_range(3.0, 7.0)
	var target := center + Vector3(cos(a) * r, 0, sin(a) * r)
	_walking = villager.movement.move_to(target, 3)
	_wait = ctx.rng.randf_range(2.0, 4.0)
	return true


func tick(dt: float) -> int:
	villager.activity = 0.3
	if _walking and villager.movement.status == VillagerMovement.MOVING:
		return Status.RUNNING
	_walking = false
	_wait -= dt
	return Status.SUCCEEDED if _wait <= 0.0 else Status.RUNNING


func _on_finish() -> void:
	villager.movement.stop()


func describe() -> String:
	if villager.is_child():
		return "Playing"
	return "Wandering around the camp" if _walking else "Idle"
