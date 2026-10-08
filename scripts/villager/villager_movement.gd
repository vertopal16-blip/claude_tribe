class_name VillagerMovement
extends RefCounted
## Path following for one villager. Paths come from NavGrid; positions are
## snapped to the terrain surface. Includes stuck detection and repathing.

enum { IDLE, MOVING, ARRIVED, FAILED }

const STUCK_CHECK_INTERVAL := 2.0
const STUCK_MIN_PROGRESS := 0.35
const MAX_REPATHS := 2

var status: int = IDLE
## Push applied by crowd separation (set by the tribe each sim tick).
var separation := Vector3.ZERO
var speed := 3.4
var facing_target := Vector3.INF

var _owner: Node3D
var _nav: NavGrid
var _terrain: Terrain
var _path := PackedVector3Array()
var _index := 0
var _goal := Vector3.ZERO
var _goal_search := 4
var _stuck_timer := 0.0
var _last_check_pos := Vector3.ZERO
var _repaths := 0


func _init(owner_node: Node3D, nav: NavGrid, terrain: Terrain, move_speed: float) -> void:
	_owner = owner_node
	_nav = nav
	_terrain = terrain
	speed = move_speed


## Requests a path. Returns false (and sets FAILED) when the goal is unreachable.
func move_to(goal: Vector3, goal_search_radius: int = 4) -> bool:
	_goal = goal
	_goal_search = goal_search_radius
	_repaths = 0
	return _repath()


func _repath() -> bool:
	_path = _nav.find_path(_owner.global_position, _goal, _goal_search)
	_index = 0
	_stuck_timer = 0.0
	_last_check_pos = _owner.global_position
	if _path.is_empty():
		status = FAILED
		return false
	status = MOVING
	return true


func stop() -> void:
	status = IDLE
	_path.clear()


func is_moving() -> bool:
	return status == MOVING


func current_waypoint() -> Vector3:
	return _path[_index] if status == MOVING and _index < _path.size() else _owner.global_position


func get_path_points() -> PackedVector3Array:
	return _path.slice(_index) if status == MOVING else PackedVector3Array()


## Per-frame movement with scaled delta (smooth at any simulation speed).
func update(dt: float, performance: float) -> void:
	if dt <= 0.0:
		return
	var pos := _owner.global_position
	if status == MOVING:
		var step := speed * performance * dt
		while step > 0.0 and _index < _path.size():
			var wp := _path[_index]
			var to := Vector2(wp.x - pos.x, wp.z - pos.z)
			var d := to.length()
			if d <= step:
				pos.x = wp.x
				pos.z = wp.z
				step -= d
				_index += 1
			else:
				var dir := to / d
				pos.x += dir.x * step
				pos.z += dir.y * step
				facing_target = Vector3(wp.x, pos.y, wp.z)
				step = 0.0
		if _index >= _path.size():
			status = ARRIVED
	# Gentle crowd separation, never pushing into blocked cells.
	if separation != Vector3.ZERO:
		var pushed := pos + separation * dt * 1.6
		if _nav.is_walkable(pushed):
			pos = pushed
	pos.y = _terrain.height_at(pos.x, pos.z)
	_owner.global_position = pos


## Called on simulation ticks: detects lack of progress and repaths / fails.
func sim_check(dt: float) -> void:
	if status != MOVING:
		return
	_stuck_timer += dt
	if _stuck_timer < STUCK_CHECK_INTERVAL:
		return
	var moved := _owner.global_position.distance_to(_last_check_pos)
	_stuck_timer = 0.0
	_last_check_pos = _owner.global_position
	if moved >= STUCK_MIN_PROGRESS:
		return
	if _repaths < MAX_REPATHS:
		_repaths += 1
		_repath()
	else:
		status = FAILED
