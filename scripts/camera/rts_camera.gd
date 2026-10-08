class_name RtsCamera
extends Node3D
## Strategy camera: a pivot on the ground with an orbiting Camera3D.
## WASD / arrows pan, wheel zooms, middle mouse (or Q/E) rotates.
## Runs on real time so it works while the simulation is paused.

@export var pan_speed := 0.9  # fraction of zoom distance per second
@export var min_distance := 7.0
@export var max_distance := 95.0
@export var min_pitch_deg := 32.0
@export var max_pitch_deg := 64.0
@export var rotate_sensitivity := 0.006
@export var key_rotate_speed := 1.6
@export var zoom_step := 1.15
@export var smoothing := 10.0

var camera: Camera3D
var terrain: Terrain
var bounds_half := 60.0

var _target_pos := Vector3.ZERO
var _target_yaw := deg_to_rad(35.0)
var _yaw := deg_to_rad(35.0)
var _target_distance := 42.0
var _distance := 42.0
var _rotating := false
var _follow: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 600.0
	add_child(camera)
	camera.make_current()
	EventBus.camera_focus_requested.connect(focus_on)


func setup(t: Terrain, start: Vector3) -> void:
	terrain = t
	bounds_half = t.playable_half + 4.0
	focus_on(start, true)


func focus_on(pos: Vector3, instant: bool = false) -> void:
	_follow = null
	_target_pos = _clamp_to_bounds(Vector3(pos.x, 0, pos.z))
	if instant:
		global_position = _ground(_target_pos)
		_yaw = _target_yaw
		_distance = _target_distance
		_update_camera_transform()


func follow(node: Node3D) -> void:
	_follow = node


func is_following() -> bool:
	return _follow != null and is_instance_valid(_follow)


func zoom(steps: float) -> void:
	_target_distance = clampf(_target_distance * pow(zoom_step, steps), min_distance, max_distance)


func rotate_yaw(radians: float) -> void:
	_target_yaw += radians


func get_zoom_distance() -> float:
	return _distance


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom(-1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom(1.0)
			MOUSE_BUTTON_MIDDLE:
				# Only start rotating when the press is on the world, not on UI.
				if mb.pressed:
					_rotating = true


## Drag and release are tracked in _input so rotation keeps working when the
## cursor passes over UI panels mid-drag.
func _input(event: InputEvent) -> void:
	if not _rotating:
		return
	if event is InputEventMouseMotion:
		_target_yaw -= (event as InputEventMouseMotion).relative.x * rotate_sensitivity
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_rotating = false


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_action_pressed(&"cam_left"):
		move.x -= 1.0
	if Input.is_action_pressed(&"cam_right"):
		move.x += 1.0
	if Input.is_action_pressed(&"cam_forward"):
		move.y -= 1.0
	if Input.is_action_pressed(&"cam_back"):
		move.y += 1.0
	if Input.is_action_pressed(&"cam_rotate_left"):
		_target_yaw += key_rotate_speed * delta
	if Input.is_action_pressed(&"cam_rotate_right"):
		_target_yaw -= key_rotate_speed * delta

	if move != Vector2.ZERO:
		_follow = null
		move = move.normalized().rotated(-_yaw)
		var speed := pan_speed * maxf(_target_distance, 15.0)
		_target_pos += Vector3(move.x, 0, move.y) * speed * delta
	if is_following():
		_target_pos = Vector3(_follow.global_position.x, 0, _follow.global_position.z)
	elif _follow != null:
		_follow = null

	_target_pos = _clamp_to_bounds(_target_pos)

	var w := 1.0 - exp(-smoothing * delta)
	var ground := _ground(_target_pos)
	global_position = global_position.lerp(ground, w)
	_yaw = lerp_angle(_yaw, _target_yaw, w)
	_distance = lerpf(_distance, _target_distance, w)
	_update_camera_transform()


func _clamp_to_bounds(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -bounds_half, bounds_half), p.y, clampf(p.z, -bounds_half, bounds_half))


func _ground(p: Vector3) -> Vector3:
	var h := terrain.height_at(p.x, p.z) if terrain else 0.0
	return Vector3(p.x, maxf(h, 0.0), p.z)


func _update_camera_transform() -> void:
	var t := inverse_lerp(min_distance, max_distance, _distance)
	var pitch := deg_to_rad(lerpf(min_pitch_deg, max_pitch_deg, t))
	var offset := Vector3(0, sin(pitch), cos(pitch)) * _distance
	offset = offset.rotated(Vector3.UP, _yaw)
	var cam_pos := global_position + offset
	if terrain:
		# Never dip below the terrain (e.g. when looking over a hill).
		var min_y := terrain.height_at(cam_pos.x, cam_pos.z) + 1.5
		cam_pos.y = maxf(cam_pos.y, min_y)
	camera.global_position = cam_pos
	camera.look_at(global_position + Vector3(0, 0.8, 0), Vector3.UP)
