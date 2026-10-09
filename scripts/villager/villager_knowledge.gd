class_name VillagerKnowledge
extends RefCounted
## What a villager knows about the world. Every AI lookup of "where is food /
## wood / stone" goes through here.
##
## Villagers only know resource locations they have personally seen (within
## PERCEPTION_RADIUS while going about their day) or been told about in
## conversation. Facts are snapshots and can be stale. Live world state is
## consulted only for things the tribe coordinates openly: whether a node
## still exists and how many people have already claimed it.

const PERCEPTION_RADIUS := 14.0
## A regrowing node seen empty is worth re-checking after this long.
const REGROW_RECHECK := 120.0

## Re-perceiving is skipped while a villager stays put (nothing new in view).
const PERCEIVE_MOVE := 3.0
const PERCEIVE_MAX_AGE := 8.0

var villager: Villager
var store := KnowledgeStore.new()
var _last_perceive_pos := Vector3.INF
var _last_perceive_time := -INF


func _init(v: Villager) -> void:
	villager = v


## Looks around (if anything could have changed) and refreshes what is in sight.
func perceive_if_needed() -> void:
	if villager.global_position.distance_to(_last_perceive_pos) < PERCEIVE_MOVE \
			and SimClock.sim_time - _last_perceive_time < PERCEIVE_MAX_AGE:
		return
	perceive()


## Looks around and refreshes facts about everything in sight.
func perceive(radius: float = PERCEPTION_RADIUS) -> void:
	var now := SimClock.sim_time
	_last_perceive_pos = villager.global_position
	_last_perceive_time = now
	for node in villager.ctx.resources.nodes_near(villager.global_position, radius):
		store.observe(node, now)


## Re-checks a node seen up close. If it turns out empty although someone told
## us it had something, that is reported as having been misled.
func verify(maybe_node) -> void:
	# May receive a node freed meanwhile (e.g. a mined-out rock): nothing to check.
	if maybe_node == null or not is_instance_valid(maybe_node):
		return
	var node := maybe_node as ResourceNode
	# A used-up node may still exist until the end of the frame. Treat it as
	# gone already, or results would depend on how many ticks share a frame.
	if node.is_queued_for_deletion() or villager.ctx.resources.get_by_id(node.entity_id) == null:
		store.forget(node.entity_id)
		return
	var fact = store.get_fact(node.entity_id)
	var told_by := -1 if fact == null else int(fact["source"])
	var told_amount := 0 if fact == null else int(fact["amount"])
	store.observe(node, SimClock.sim_time)
	if told_by >= 0 and told_amount > 0 and node.amount <= 0 and villager.ctx.social != null:
		villager.ctx.social.on_misled(villager, told_by, ResourceType.display_name(node.resource_type).to_lower())


func knows_available(type: int) -> bool:
	return store.count_available(type) > 0


## Best known, reachable, unclaimed node of `type`. `home_weight` biases the
## choice toward nodes close to the stockpile (used when hauling home).
func find_resource(type: int, home_weight: float = 0.0, max_distance: float = INF) -> ResourceNode:
	var ctx := villager.ctx
	var pos := villager.global_position
	var region := villager.get_region()
	var blacklist := villager.brain.get_blacklist()
	var home := ctx.tribe.storage.global_position
	var now := SimClock.sim_time
	var best: ResourceNode = null
	var best_cost := INF
	var stale: Array[int] = []
	for id in store.ids_of_type(type):
		var fact: Dictionary = store.facts[id]
		var penalty := 0.0
		if int(fact["amount"]) <= 0:
			if not fact["regrows"] or now - float(fact["time"]) < REGROW_RECHECK:
				continue
			penalty = 15.0  # might have regrown - worth a look if nothing better
		var fpos: Vector3 = fact["pos"]
		var d := pos.distance_to(fpos)
		if d > max_distance:
			continue
		var cost := d + penalty + (home.distance_to(fpos) * home_weight if home_weight > 0.0 else 0.0)
		if cost >= best_cost:
			continue
		var node := ctx.resources.get_by_id(id)
		if node == null:
			stale.append(id)  # gone for good (e.g. a mined-out rock)
			continue
		if node.reservations >= node.max_reservations or not node.is_inside_tree():
			continue
		if region >= 0 and node.region_id != region:
			continue
		if blacklist.has(node.get_instance_id()):
			continue
		best_cost = cost
		best = node
	for id in stale:
		store.forget(id)
	return best


## A location this villager could tell `listener` about: something believed
## available that the listener has no (or older) knowledge of. -1 if none.
func shareable_fact(type: int, listener: VillagerKnowledge) -> int:
	var best := -1
	var best_d := INF
	var camp := villager.ctx.tribe.center
	for id in store.ids_of_type(type):
		var f: Dictionary = store.facts[id]
		if int(f["amount"]) <= 0:
			continue
		var theirs = listener.store.get_fact(id)
		if theirs != null and float(theirs["time"]) >= float(f["time"]):
			continue
		var d := camp.distance_to(f["pos"])
		if d < best_d:
			best_d = d
			best = id
	return best
