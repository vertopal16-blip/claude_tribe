class_name ExploreTask
extends VillagerTask
## Walk somewhere little-known to discover resources. Picks the direction
## where the villager knows the fewest places; finishes early once the wanted
## resource has been spotted.

const MIN_RADIUS := 16.0
const MAX_RADIUS := 50.0
const CANDIDATES := 12

## Resource being searched for, or ResourceType.NONE for plain curiosity.
var wanted_type: int = ResourceType.NONE
var _look_timer := 0.0


func _init(v: Villager, goal: StringName, wanted: int) -> void:
	super(v, goal)
	wanted_type = wanted


func start() -> bool:
	var center := ctx.tribe.center
	var region := villager.get_region()
	var best := Vector3.INF
	var best_score := -INF
	var facts := villager.knowledge.store.facts
	for i in CANDIDATES:
		var a := TAU * i / CANDIDATES + villager.brain.rng.randf() * 0.4
		var r := villager.brain.rng.randf_range(MIN_RADIUS, MAX_RADIUS)
		var p := ctx.terrain.snap_to_ground(center + Vector3(cos(a), 0, sin(a)) * r)
		if ctx.nav.access_region(p) != region:
			continue
		var known := 0
		for node in ctx.resources.nodes_near(p, 14.0):
			if facts.has(node.entity_id):
				known += 1
		var score := -known + villager.brain.rng.randf() * 3.0 - villager.global_position.distance_to(p) * 0.02
		if score > best_score:
			best_score = score
			best = p
	if best == Vector3.INF or not villager.movement.move_to(best, 4):
		return false
	villager.set_state(VillagerState.SEARCHING_FOOD if wanted_type == ResourceType.FOOD else VillagerState.EXPLORING)
	return true


func tick(dt: float) -> int:
	villager.activity = 0.7
	_look_timer += dt
	if _look_timer >= 1.0:
		_look_timer = 0.0
		villager.knowledge.perceive_if_needed()
		if wanted_type != ResourceType.NONE and villager.knowledge.knows_available(wanted_type):
			villager.record_event(&"discovered", {"resource_type": wanted_type})
			return Status.SUCCEEDED
	match villager.movement.status:
		VillagerMovement.ARRIVED:
			villager.knowledge.perceive()
			return Status.SUCCEEDED
		VillagerMovement.FAILED:
			return _fail("Couldn't get there")
	return Status.RUNNING


func _on_finish() -> void:
	villager.movement.stop()


func describe() -> String:
	if wanted_type == ResourceType.NONE:
		return "Exploring the valley"
	return "Searching the valley for %s" % ResourceType.display_name(wanted_type).to_lower()
