class_name ResourceRegistry
extends RefCounted
## Spatial bookkeeping for every harvestable node.
##
## AI queries go through here instead of scanning the scene tree, so resource
## nodes never need to know about villagers and vice versa.

var nav: NavGrid
var _by_type: Dictionary = {}  # type -> Array[ResourceNode]
var _regrowing: Array[ResourceNode] = []
var _nav_version := -1


func _init(nav_grid: NavGrid) -> void:
	nav = nav_grid
	for t in ResourceType.ALL:
		_by_type[t] = [] as Array[ResourceNode]


func register(node: ResourceNode) -> void:
	_by_type[node.resource_type].append(node)
	node.depleted.connect(_on_depleted)
	node.harvested.connect(notify_harvested)
	node.region_id = nav.access_region(node.global_position)


func unregister(node: ResourceNode) -> void:
	_by_type[node.resource_type].erase(node)
	_regrowing.erase(node)


func get_nodes(type: int) -> Array[ResourceNode]:
	return _by_type.get(type, [] as Array[ResourceNode])


func all_nodes() -> Array[ResourceNode]:
	var out: Array[ResourceNode] = []
	for t in ResourceType.ALL:
		out.append_array(_by_type[t])
	return out


func refresh_regions() -> void:
	for t in ResourceType.ALL:
		for node: ResourceNode in _by_type[t]:
			node.region_id = nav.access_region(node.global_position)


## Finds the best available node of `type`.
## Cost = distance from the villager + `home_weight` * distance to `home`.
## `excluded` maps instance ids to anything (e.g. a villager's blacklist).
func find_best(type: int, from: Vector3, region: int, excluded: Dictionary = {},
		home: Vector3 = Vector3.INF, home_weight: float = 0.0, max_distance: float = INF) -> ResourceNode:
	var best: ResourceNode = null
	var best_cost := INF
	for node: ResourceNode in _by_type.get(type, []):
		if not node.is_available():
			continue
		if region >= 0 and node.region_id != region:
			continue
		if excluded.has(node.get_instance_id()):
			continue
		var d := from.distance_to(node.global_position)
		if d > max_distance:
			continue
		var cost := d
		if home != Vector3.INF:
			cost += home.distance_to(node.global_position) * home_weight
		if cost < best_cost:
			best_cost = cost
			best = node
	return best


func total_available(type: int) -> int:
	var total := 0
	for node: ResourceNode in _by_type.get(type, []):
		total += node.amount
	return total


func sim_tick(dt: float) -> void:
	if _nav_version != nav.version:
		_nav_version = nav.version
		refresh_regions()
	for i in range(_regrowing.size() - 1, -1, -1):
		var node := _regrowing[i]
		if not is_instance_valid(node):
			_regrowing.remove_at(i)
			continue
		node.sim_tick(dt)
		if not node.needs_regrowth():
			_regrowing.remove_at(i)


func notify_harvested(node: ResourceNode) -> void:
	if node.needs_regrowth() and not _regrowing.has(node):
		_regrowing.append(node)


func _on_depleted(node: ResourceNode) -> void:
	if node.regrows:
		notify_harvested(node)
		return
	# Non-renewable nodes disappear and free their navigation cells.
	unregister(node)
	nav.remove_obstacle(node.global_position, node.obstacle_radius)
	node.queue_free()
