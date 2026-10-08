class_name VillagerTask
extends RefCounted
## Base class for an activity a villager performs over time.
##
## Lifecycle: start() once -> tick() every sim tick until it returns SUCCEEDED
## or FAILED -> finish() exactly once (also on interruption) to release any
## reservations. Each task is its own small state machine.

enum Status { RUNNING, SUCCEEDED, FAILED }

var villager: Villager
var ctx: WorldContext
var goal_id: StringName
var fail_reason := ""
var _finished := false


func _init(v: Villager, goal: StringName) -> void:
	villager = v
	ctx = v.ctx
	goal_id = goal


## Returns false when the task can't be performed right now.
func start() -> bool:
	return true


func tick(_dt: float) -> int:
	return Status.SUCCEEDED


func finish() -> void:
	if _finished:
		return
	_finished = true
	_on_finish()


## Override for cleanup (release reservations, stop movement...).
func _on_finish() -> void:
	pass


func is_interruptible() -> bool:
	return true


func describe() -> String:
	return VillagerState.label(villager.state)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _fail(reason: String) -> int:
	fail_reason = reason
	return Status.FAILED


func _distance_flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Starts walking to the stockpile.
func _go_to_stockpile() -> bool:
	var stock := ctx.tribe.storage
	return villager.movement.move_to(stock.global_position, int(ceil(stock.def.footprint_radius)) + 3)


func _near_building(b: Building, slack: float = 1.6) -> bool:
	return _distance_flat(villager.global_position, b.global_position) <= b.def.footprint_radius + slack
