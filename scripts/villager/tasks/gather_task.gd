class_name GatherTask
extends VillagerTask
## Find a resource node -> walk there -> harvest until full -> carry it to the
## stockpile -> deliver. Switches to a nearby node when one runs out.

enum Step { TO_RESOURCE, GATHERING, TO_STOCKPILE, DELIVERING }

const NEARBY_SEARCH := 14.0
const DELIVER_TIME := 0.6
## Distance at which a villager notices a target has been emptied.
const SIGHT_RANGE := 10.0

var resource_type: int
var node: ResourceNode
var step: int = Step.TO_RESOURCE

var _timer := 0.0
var _reserved := false


func _init(v: Villager, goal: StringName, type: int) -> void:
	super(v, goal)
	resource_type = type


const SKILL_FOR := {ResourceType.FOOD: &"foraging", ResourceType.WOOD: &"woodcutting", ResourceType.STONE: &"stonework"}


func start() -> bool:
	if villager.inventory.free_space_for(resource_type) <= 0:
		return false
	ctx.society.economy.equip(villager)
	return _acquire_node(INF)


func _acquire_node(max_distance: float) -> bool:
	for attempt in 3:
		var candidate := villager.knowledge.find_resource(resource_type, 0.6, max_distance)
		if candidate == null:
			return false
		if not candidate.reserve():
			continue
		if villager.movement.move_to(candidate.global_position, 3):
			node = candidate
			_reserved = true
			step = Step.TO_RESOURCE
			villager.set_state(VillagerState.MOVING_TO_RESOURCE)
			return true
		candidate.release()
		villager.brain.mark_unreachable(candidate)
	return false


func _release() -> void:
	if _reserved and is_instance_valid(node):
		node.release()
	_reserved = false


func tick(dt: float) -> int:
	match step:
		Step.TO_RESOURCE:
			if not is_instance_valid(node):
				_release()
				return _next_source_or_return()
			if not node.is_harvestable() and _distance_flat(villager.global_position, node.global_position) < SIGHT_RANGE:
				# Close enough to see it has been emptied since we last heard of it.
				villager.knowledge.verify(node)
				_release()
				return _next_source_or_return()
			match villager.movement.status:
				VillagerMovement.FAILED:
					villager.brain.mark_unreachable(node)
					_release()
					return _next_source_or_return()
				VillagerMovement.ARRIVED:
					if _distance_flat(villager.global_position, node.global_position) > node.interact_radius * node.scale.x + 1.2:
						villager.brain.mark_unreachable(node)
						_release()
						return _next_source_or_return()
					step = Step.GATHERING
					_timer = 0.0
					villager.set_state(VillagerState.GATHERING)
					villager.face_towards(node.global_position)
		Step.GATHERING:
			villager.activity = 1.0
			if not is_instance_valid(node) or not node.is_harvestable():
				villager.knowledge.verify(node)
				_release()
				return _next_source_or_return()
			var skill: StringName = SKILL_FOR[resource_type]
			_timer += dt * villager.work_efficiency(skill)
			villager.practice(skill, dt)
			if _timer >= ctx.config.gather_interval:
				_timer -= ctx.config.gather_interval
				var got := node.harvest(1)
				villager.inventory.add(resource_type, got)
				if got > 0 and node.amount == 0 and node.kind == ResourceNode.Kind.TREE:
					ctx.society.culture.on_tree_felled(villager, node)
			if villager.inventory.free_space_for(resource_type) <= 0:
				_release()
				return _start_return()
		Step.TO_STOCKPILE:
			villager.activity = 0.8
			match villager.movement.status:
				VillagerMovement.ARRIVED:
					step = Step.DELIVERING
					_timer = 0.0
					villager.set_state(VillagerState.DELIVERING)
					villager.face_towards(ctx.tribe.storage.global_position)
				VillagerMovement.FAILED:
					return _fail("Can't reach the stockpile")
		Step.DELIVERING:
			_timer += dt
			if _timer >= DELIVER_TIME:
				ctx.tribe.deposit_inventory(villager)
				return Status.SUCCEEDED
	return Status.RUNNING


## Current node is gone: try another close one, otherwise bring home what we have.
func _next_source_or_return() -> int:
	if villager.inventory.free_space_for(resource_type) > 0 and _acquire_node(NEARBY_SEARCH):
		return Status.RUNNING
	if villager.inventory.is_empty():
		return _fail("No reachable %s" % ResourceType.display_name(resource_type).to_lower())
	return _start_return()


func _start_return() -> int:
	# Carrying food home while someone we care about is going hungry: stop and
	# let the brain weigh helping them against delivering to the stockpile.
	if resource_type == ResourceType.FOOD and ctx.social.find_person_to_help(villager) != null:
		return Status.SUCCEEDED
	step = Step.TO_STOCKPILE
	villager.set_state(VillagerState.RETURNING)
	if not _go_to_stockpile():
		return _fail("Can't reach the stockpile")
	return Status.RUNNING


func _on_finish() -> void:
	_release()
	villager.movement.stop()


func describe() -> String:
	var res := ResourceType.display_name(resource_type).to_lower()
	match step:
		Step.TO_RESOURCE: return "Heading out to gather %s" % res
		Step.GATHERING: return "Gathering %s" % res
		Step.TO_STOCKPILE: return "Carrying %s to the stockpile" % res
		Step.DELIVERING: return "Delivering %s" % res
	return super()
