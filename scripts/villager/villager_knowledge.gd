class_name VillagerKnowledge
extends RefCounted
## What a villager knows about the world. Every AI lookup of "where is food /
## wood / stone" goes through here instead of reading global registries
## directly.
##
## Today this answers from complete knowledge of the valley (the tribe is
## assumed to know its surroundings), filtered by reachability and the
## villager's short-term list of unreachable targets. The future social
## simulation replaces the lookups with the villager's own discovered and
## told-about locations, so villagers can't act on information they could not
## have learned, without touching tasks or the brain.

var villager: Villager


func _init(v: Villager) -> void:
	villager = v


## Best known, reachable, available node of `type`. `home_weight` biases the
## choice toward nodes close to the stockpile (used when hauling home).
func find_resource(type: int, home_weight: float = 0.0, max_distance: float = INF) -> ResourceNode:
	var ctx := villager.ctx
	var home := ctx.tribe.storage.global_position if home_weight > 0.0 else Vector3.INF
	return ctx.resources.find_best(type, villager.global_position, villager.get_region(),
			villager.brain.get_blacklist(), home, home_weight, max_distance)
