class_name ResourceRegistry
extends RefCounted
## Spatial bookkeeping for every harvestable node.
##
## AI queries go through here instead of scanning the scene tree, so resource
## nodes never need to know about villagers and vice versa.

var nav: NavGrid
var _by_type: Dictionary = {}  # type -> Array[ResourceNode]
var _regrowing: Array[ResourceNode] = []
var _by_id: Dictionary = {}  # entity_id -> ResourceNode
## Spatial buckets (resource nodes never move) for perception queries.
var _buckets: Dictionary = {}  # Vector2i -> Array[ResourceNode]
const BUCKET_SIZE := 16.0
var _nav_version := -1
## Region refreshes (a flood fill + one lookup per node) are rate-limited:
## connectivity changes are rare and a few seconds of staleness is harmless.
const REGION_REFRESH_INTERVAL := 5.0
var _refresh_cooldown := 0.0


func _init(nav_grid: NavGrid) -> void:
	nav = nav_grid
	for t in ResourceType.ALL:
		_by_type[t] = [] as Array[ResourceNode]


func register(node: ResourceNode) -> void:
	_by_type[node.resource_type].append(node)
	_by_id[node.entity_id] = node
	var key := _bucket_key(node.global_position)
	if not _buckets.has(key):
		_buckets[key] = [] as Array[ResourceNode]
	_buckets[key].append(node)
	node.depleted.connect(_on_depleted)
	node.harvested.connect(notify_harvested)
	node.region_id = nav.access_region(node.global_position)


func unregister(node: ResourceNode) -> void:
	_by_type[node.resource_type].erase(node)
	_regrowing.erase(node)
	_by_id.erase(node.entity_id)
	var key := _bucket_key(node.global_position)
	if _buckets.has(key):
		_buckets[key].erase(node)


func _bucket_key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / BUCKET_SIZE)), int(floor(p.z / BUCKET_SIZE)))


## Node by stable entity id, or null if it no longer exists.
func get_by_id(entity_id: int) -> ResourceNode:
	return _by_id.get(entity_id)


## All nodes within `radius` of `pos` (any type, depleted included).
func nodes_near(pos: Vector3, radius: float) -> Array[ResourceNode]:
	var out: Array[ResourceNode] = []
	var r2 := radius * radius
	var lo := _bucket_key(pos - Vector3(radius, 0, radius))
	var hi := _bucket_key(pos + Vector3(radius, 0, radius))
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var bucket = _buckets.get(Vector2i(bx, bz))
			if bucket == null:
				continue
			for node: ResourceNode in bucket:
				var d := node.global_position - pos
				if d.x * d.x + d.z * d.z <= r2:
					out.append(node)
	return out


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


const REGROW_STEP := 1.0
var _regrow_accum := 0.0


func sim_tick(dt: float) -> void:
	_refresh_cooldown -= dt
	if _nav_version != nav.version and _refresh_cooldown <= 0.0:
		_nav_version = nav.version
		_refresh_cooldown = REGION_REFRESH_INTERVAL
		refresh_regions()
	# Regrowth is slow; advancing it once per second is plenty.
	_regrow_accum += dt
	if _regrow_accum < REGROW_STEP:
		return
	var step := _regrow_accum
	_regrow_accum = 0.0
	for i in range(_regrowing.size() - 1, -1, -1):
		var node := _regrowing[i]
		if not is_instance_valid(node):
			_regrowing.remove_at(i)
			continue
		node.sim_tick(step)
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
