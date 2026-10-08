class_name NavGrid
extends RefCounted
## Grid navigation built on Godot's AStarGrid2D.
##
## * Terrain decides base walkability (water, steep slopes, world boundary).
## * Trees, rocks and buildings carve obstacles with reference counting.
## * Connected regions are tracked so the AI never picks targets it can't reach.
## * Paths are smoothed with line-of-sight checks so villagers walk naturally.

const INVALID_CELL := Vector2i(-1, -1)

var cell_size := 1.0
var width := 0
var height := 0
var origin := Vector2.ZERO
var terrain: Terrain

var _astar := AStarGrid2D.new()
var _base_walkable := PackedByteArray()
var _occupancy := PackedInt32Array()
var _region := PackedInt32Array()
var _regions_dirty := true
var _main_region := -1
## Incremented whenever walkability changes, so dependents can refresh caches.
var version := 0


func build(t: Terrain, cfg: GameConfig) -> void:
	terrain = t
	cell_size = maxf(0.5, cfg.nav_cell_size)
	width = int(ceil(t.size / cell_size))
	height = width
	origin = Vector2(-t.half, -t.half)
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2(cell_size, cell_size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()

	var n := width * height
	_base_walkable.resize(n)
	_occupancy.resize(n)
	_region.resize(n)
	_occupancy.fill(0)
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			var w := cell_center_2d(c)
			var walkable := t.is_in_playable_area(w.x, w.y, 0.5) and not t.is_water(w.x, w.y)
			var slope := 1.0 - t.normal_at(w.x, w.y).y
			if walkable and t.normal_at(w.x, w.y).y < cfg.max_walkable_slope_normal_y:
				walkable = false
			_base_walkable[_idx(c)] = 1 if walkable else 0
			_astar.set_point_solid(c, not walkable)
			if walkable:
				# Uphill and slopes cost more, so paths prefer flat ground.
				_astar.set_point_weight_scale(c, 1.0 + slope * 6.0)
	_regions_dirty = true


# --------------------------------------------------------------------------
# Coordinates
# --------------------------------------------------------------------------

func _idx(c: Vector2i) -> int:
	return c.y * width + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / cell_size)), int(floor((p.z - origin.y) / cell_size)))


func cell_center_2d(c: Vector2i) -> Vector2:
	return origin + Vector2((c.x + 0.5) * cell_size, (c.y + 0.5) * cell_size)


func cell_to_world(c: Vector2i) -> Vector3:
	var p := cell_center_2d(c)
	return Vector3(p.x, terrain.height_at(p.x, p.y), p.y)


func is_walkable_cell(c: Vector2i) -> bool:
	return in_bounds(c) and not _astar.is_point_solid(c)


func is_walkable(p: Vector3) -> bool:
	return is_walkable_cell(world_to_cell(p))


func is_base_walkable(p: Vector3) -> bool:
	var c := world_to_cell(p)
	return in_bounds(c) and _base_walkable[_idx(c)] == 1


func is_occupied(p: Vector3) -> bool:
	var c := world_to_cell(p)
	return in_bounds(c) and _occupancy[_idx(c)] > 0


# --------------------------------------------------------------------------
# Obstacles
# --------------------------------------------------------------------------

func add_obstacle(center: Vector3, radius: float) -> void:
	_change_obstacle(center, radius, 1)


func remove_obstacle(center: Vector3, radius: float) -> void:
	_change_obstacle(center, radius, -1)


func _change_obstacle(center: Vector3, radius: float, delta: int) -> void:
	var cells := cells_in_radius(center, radius)
	for c in cells:
		var i := _idx(c)
		_occupancy[i] = maxi(0, _occupancy[i] + delta)
		_astar.set_point_solid(c, _base_walkable[i] == 0 or _occupancy[i] > 0)
	_regions_dirty = true
	version += 1


func cells_in_radius(center: Vector3, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cc := world_to_cell(center)
	var r := int(ceil(radius / cell_size))
	var c2 := Vector2(center.x, center.z)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := cc + Vector2i(dx, dy)
			if not in_bounds(c):
				continue
			if cell_center_2d(c).distance_to(c2) <= radius or (dx == 0 and dy == 0):
				out.append(c)
	return out


## True when every cell in the radius is free terrain without obstacles.
func is_area_free(center: Vector3, radius: float) -> bool:
	for c in cells_in_radius(center, radius):
		var i := _idx(c)
		if _base_walkable[i] == 0 or _occupancy[i] > 0:
			return false
	return true


# --------------------------------------------------------------------------
# Regions (connectivity)
# --------------------------------------------------------------------------

func ensure_regions() -> void:
	if not _regions_dirty:
		return
	_regions_dirty = false
	# Flood fill over flat indices (hot path: runs whenever obstacles change).
	var n := width * height
	_region.fill(-1)
	var next_id := 0
	var best_size := 0
	var queue := PackedInt32Array()
	queue.resize(n)
	for start in n:
		if _region[start] != -1 or _base_walkable[start] == 0 or _occupancy[start] > 0:
			continue
		_region[start] = next_id
		queue[0] = start
		var head := 0
		var tail := 1
		while head < tail:
			var cur := queue[head]
			head += 1
			var cx := cur % width
			var nb := cur - 1
			if cx > 0 and _region[nb] == -1 and _base_walkable[nb] == 1 and _occupancy[nb] == 0:
				_region[nb] = next_id
				queue[tail] = nb
				tail += 1
			nb = cur + 1
			if cx < width - 1 and _region[nb] == -1 and _base_walkable[nb] == 1 and _occupancy[nb] == 0:
				_region[nb] = next_id
				queue[tail] = nb
				tail += 1
			nb = cur - width
			if nb >= 0 and _region[nb] == -1 and _base_walkable[nb] == 1 and _occupancy[nb] == 0:
				_region[nb] = next_id
				queue[tail] = nb
				tail += 1
			nb = cur + width
			if nb < n and _region[nb] == -1 and _base_walkable[nb] == 1 and _occupancy[nb] == 0:
				_region[nb] = next_id
				queue[tail] = nb
				tail += 1
		if tail > best_size:
			best_size = tail
			_main_region = next_id
		next_id += 1


func region_of_cell(c: Vector2i) -> int:
	ensure_regions()
	if not in_bounds(c):
		return -1
	return _region[_idx(c)]


## Region of the walkable cell nearest to `p` (works for obstacles too).
func access_region(p: Vector3, search_radius: int = 4) -> int:
	var c := nearest_walkable_cell(world_to_cell(p), search_radius)
	return -1 if c == INVALID_CELL else region_of_cell(c)


func main_region() -> int:
	ensure_regions()
	return _main_region


# --------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------

func nearest_walkable_cell(c: Vector2i, max_radius: int = 6) -> Vector2i:
	if is_walkable_cell(c):
		return c
	for r in range(1, max_radius + 1):
		var best := INVALID_CELL
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if is_walkable_cell(n):
					var d := float(dx * dx + dy * dy)
					if d < best_d:
						best_d = d
						best = n
		if best != INVALID_CELL:
			return best
	return INVALID_CELL


## Returns smoothed world-space waypoints (excluding the start), or an empty
## array when the goal can't be reached.
func find_path(from: Vector3, to: Vector3, goal_search_radius: int = 4) -> PackedVector3Array:
	var result := PackedVector3Array()
	var start := nearest_walkable_cell(world_to_cell(from), 3)
	var goal := nearest_walkable_cell(world_to_cell(to), goal_search_radius)
	if start == INVALID_CELL or goal == INVALID_CELL:
		return result
	if region_of_cell(start) != region_of_cell(goal):
		return result
	if start == goal:
		result.append(_waypoint(goal, to, true))
		return result
	var ids: Array[Vector2i] = _astar.get_id_path(start, goal)
	if ids.is_empty():
		return result
	var smoothed := _smooth(ids)
	for i in range(1, smoothed.size()):
		result.append(_waypoint(smoothed[i], to, i == smoothed.size() - 1))
	return result


func _waypoint(c: Vector2i, original_goal: Vector3, is_last: bool) -> Vector3:
	# When the final cell *is* the goal cell, use the exact goal position.
	if is_last and world_to_cell(original_goal) == c:
		return terrain.snap_to_ground(original_goal)
	return cell_to_world(c)


## Maximum straight segment (in cells) the smoother tries; bounds the cost
## of line-of-sight checks so long paths stay cheap.
const SMOOTH_MAX_SEGMENT := 14


func _smooth(ids: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = [ids[0]]
	var anchor := 0
	var i := 2
	while i < ids.size():
		if i - anchor > SMOOTH_MAX_SEGMENT or not _line_clear(ids[anchor], ids[i]):
			out.append(ids[i - 1])
			anchor = i - 1
		i += 1
	out.append(ids[ids.size() - 1])
	return out


func _free_xy(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	var i := y * width + x
	return _base_walkable[i] == 1 and _occupancy[i] == 0


func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	var pa := Vector2(a) + Vector2(0.5, 0.5)
	var pb := Vector2(b) + Vector2(0.5, 0.5)
	var dist := pa.distance_to(pb)
	var steps := int(ceil(dist / 0.4))
	# Check a slightly widened corridor so villagers don't clip obstacle corners.
	var side := (pb - pa).normalized().orthogonal() * 0.35
	for s in range(steps + 1):
		var p := pa.lerp(pb, float(s) / maxf(1.0, steps))
		if not _free_xy(int(p.x), int(p.y)):
			return false
		var q := p + side
		if not _free_xy(int(q.x), int(q.y)):
			return false
		q = p - side
		if not _free_xy(int(q.x), int(q.y)):
			return false
	return true
