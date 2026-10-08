class_name WorldInteraction
extends Node3D
## Mouse interaction with the 3D world: hover, selection and building placement.
## Uses physics raycasts against terrain, villagers, resources and buildings.

signal placement_mode_changed(active: bool, def: BuildingDef)

const RAY_MASK := 1 | 2 | 4 | 8
const RAY_LENGTH := 1000.0
## Screen distance (px) within which a villager is preferred over other objects.
const VILLAGER_PICK_PIXELS := 22.0
const COLOR_SELECT := Color(1.0, 0.92, 0.45, 0.95)
const COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.45)

var ctx: WorldContext
var rts_camera: RtsCamera
var selected: Node3D
var hovered: Node3D
var placing_def: BuildingDef

var _select_ring: MeshInstance3D
var _hover_ring: MeshInstance3D
var _ghost: Node3D
var _ghost_model: MeshInstance3D
var _ghost_ring: MeshInstance3D
var _ghost_ok_mat: StandardMaterial3D
var _ghost_bad_mat: StandardMaterial3D
var _ghost_valid := false
var ghost_reason := ""
var _ghost_pos := Vector3.INF


func setup(context: WorldContext, cam: RtsCamera) -> void:
	ctx = context
	rts_camera = cam


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_select_ring = _make_ring(COLOR_SELECT)
	_hover_ring = _make_ring(COLOR_HOVER)
	_ghost_ok_mat = _ghost_material(Color(0.4, 1.0, 0.5, 0.45))
	_ghost_bad_mat = _ghost_material(Color(1.0, 0.3, 0.25, 0.45))
	_ghost = Node3D.new()
	_ghost.visible = false
	add_child(_ghost)
	_ghost_model = MeshInstance3D.new()
	_ghost_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(_ghost_model)
	_ghost_ring = MeshInstance3D.new()
	_ghost.add_child(_ghost_ring)
	EventBus.villager_died.connect(_on_entity_gone)
	EventBus.building_removed.connect(_on_entity_gone)


func _make_ring(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.ring(1.0, 0.14)
	mi.material_override = MeshFactory.ring_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _ghost_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if placing_def != null:
				_try_place()
			else:
				select(_pick(mb.position).get("target"))
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if placing_def != null:
				cancel_placement()
			else:
				select(null)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"cancel"):
		if placing_def != null:
			cancel_placement()
		else:
			select(null)


## Returns {"target": Node3D or null, "position": Vector3, "hit": bool}.
func _pick(screen_pos: Vector2, mask: int = RAY_MASK) -> Dictionary:
	var cam := rts_camera.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"target": null, "position": Vector3.INF, "hit": false}
	var col: Object = hit["collider"]
	var target: Node3D = null
	if col is Villager or col is ResourceNode or col is Building:
		target = col
	# Villagers are small and often behind trees or huts: if one is drawn close
	# to the cursor, it wins over whatever the ray hit.
	if mask & Villager.COLLISION_LAYER and not (target is Villager):
		var v := _villager_near_cursor(screen_pos)
		if v != null:
			target = v
	return {"target": target, "position": hit["position"], "hit": true}


func _villager_near_cursor(screen_pos: Vector2) -> Villager:
	var cam := rts_camera.camera
	var best: Villager = null
	var best_d := VILLAGER_PICK_PIXELS
	for v in ctx.tribe.villagers:
		if v.is_hidden():
			continue
		var p := v.global_position + Vector3(0, 0.8, 0)
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = v
	return best


func select(target: Node3D) -> void:
	if target is Villager and (target as Villager).is_dead:
		target = null
	if selected == target:
		return
	selected = target
	EventBus.selection_changed.emit(target)


func _on_entity_gone(entity: Node, _extra = null) -> void:
	if entity == selected:
		select(null)
	if entity == hovered:
		hovered = null


# --------------------------------------------------------------------------
# Building placement
# --------------------------------------------------------------------------

func begin_placement(def: BuildingDef) -> void:
	placing_def = def
	_ghost_model.mesh = MeshFactory.hut()
	_ghost_ring.mesh = MeshFactory.ring(def.footprint_radius + 0.3, 0.18)
	_ghost.visible = false
	placement_mode_changed.emit(true, def)


func cancel_placement() -> void:
	if placing_def == null:
		return
	placing_def = null
	_ghost.visible = false
	placement_mode_changed.emit(false, null)


func is_placing() -> bool:
	return placing_def != null


func _try_place() -> void:
	if _ghost_pos == Vector3.INF:
		return
	if not _ghost_valid:
		EventBus.notify("Can't build here: %s" % ghost_reason, &"warning")
		return
	var b := ctx.tribe.place_building(placing_def, _ghost_pos, true)
	if b != null and not Input.is_key_pressed(KEY_SHIFT):
		# Hold Shift to place several in a row.
		cancel_placement()


# --------------------------------------------------------------------------
# Per-frame feedback
# --------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if ctx == null:
		return
	var mouse := get_viewport().get_mouse_position()
	if placing_def != null:
		hovered = null
		var hit := _pick(mouse, 1)
		if hit["hit"]:
			_ghost_pos = hit["position"]
			ghost_reason = ctx.tribe.can_place(placing_def, _ghost_pos)
			_ghost_valid = ghost_reason == ""
			_ghost.visible = true
			_ghost.global_position = _ghost_pos
			var mat := _ghost_ok_mat if _ghost_valid else _ghost_bad_mat
			_ghost_model.material_override = mat
			_ghost_ring.material_override = mat
		else:
			_ghost_pos = Vector3.INF
			_ghost.visible = false
	else:
		hovered = _pick(mouse).get("target")
	if selected != null and not is_instance_valid(selected):
		select(null)
	_update_ring(_select_ring, selected, 1.0)
	_update_ring(_hover_ring, hovered if hovered != selected else null, 0.9)


func _update_ring(ring: MeshInstance3D, target: Node3D, scale_mult: float) -> void:
	if target == null or not is_instance_valid(target):
		ring.visible = false
		return
	var r := 0.7
	if target is ResourceNode:
		r = (target as ResourceNode).interact_radius * target.scale.x * 0.85
	elif target is Building:
		r = (target as Building).def.footprint_radius + 0.4
	ring.visible = true
	ring.global_position = target.global_position + Vector3(0, 0.12, 0)
	ring.scale = Vector3.ONE * r * scale_mult
