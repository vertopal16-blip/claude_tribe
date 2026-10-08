class_name WorldGenerator
extends RefCounted
## Populates the terrain: harvestable trees / rocks / berry bushes (individual
## nodes) and purely decorative grass, flowers, pebbles and mountain forests
## (MultiMeshInstance3D, one draw call each).

var ctx: WorldContext
var rng: RandomNumberGenerator
var _forest_noise := FastNoiseLite.new()
var _resource_root: Node3D
var _counts := {"trees": 0, "rocks": 0, "bushes": 0}


func populate(context: WorldContext) -> Dictionary:
	ctx = context
	rng = ctx.rng
	_forest_noise.seed = rng.randi()
	_forest_noise.frequency = 0.028

	_resource_root = Node3D.new()
	_resource_root.name = "Resources"
	ctx.world_root.add_child(_resource_root)

	var cfg := ctx.config
	# 1. Guarantee a well supplied starting area.
	_scatter(cfg.start_area_bushes, _place_bush, cfg.start_area_inner_radius, cfg.start_area_outer_radius * 0.8, false)
	_scatter(cfg.start_area_trees, _place_tree, cfg.start_area_inner_radius, cfg.start_area_outer_radius, false)
	_scatter(cfg.start_area_rocks, _place_rock, cfg.start_area_inner_radius + 3.0, cfg.start_area_outer_radius, false)
	# 2. The rest of the valley.
	_scatter(maxi(0, cfg.tree_count - _counts.trees), _place_tree, cfg.start_area_inner_radius, INF, true)
	_scatter(maxi(0, cfg.rock_count - _counts.rocks), _place_rock, cfg.start_area_inner_radius, INF, false)
	_scatter(maxi(0, cfg.bush_count - _counts.bushes), _place_bush, cfg.start_area_inner_radius, INF, false)

	_build_decorations()
	ctx.nav.ensure_regions()
	ctx.resources.refresh_regions()
	return _counts.duplicate()


# --------------------------------------------------------------------------
# Resource nodes
# --------------------------------------------------------------------------

func _scatter(count: int, placer: Callable, min_r: float, max_r: float, use_forest_noise: bool) -> void:
	var placed := 0
	var attempts := 0
	var half := ctx.terrain.playable_half - 2.0
	while placed < count and attempts < count * 60:
		attempts += 1
		var p: Vector2
		if max_r == INF:
			p = Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		else:
			var a := rng.randf() * TAU
			# sqrt for uniform area distribution in the ring
			var r := sqrt(rng.randf_range(min_r * min_r, max_r * max_r))
			p = ctx.terrain.settlement_center + Vector2(cos(a), sin(a)) * r
		if p.distance_to(ctx.terrain.settlement_center) < min_r:
			continue
		if use_forest_noise:
			# Trees clump into forests with scattered loners in between.
			var f := _forest_noise.get_noise_2d(p.x, p.y)
			if rng.randf() > clampf((f + 0.15) * 2.2, 0.06, 1.0):
				continue
		if placer.call(Vector3(p.x, 0, p.y)):
			placed += 1


func _ground_ok(pos: Vector3, clearance: float) -> bool:
	var t := ctx.terrain
	if not t.is_in_playable_area(pos.x, pos.z, 2.0):
		return false
	if t.height_at(pos.x, pos.z) < t.water_level + 0.6:
		return false
	if t.normal_at(pos.x, pos.z).y < 0.8:
		return false
	# Free ring around the node keeps a walkable gap between all obstacles.
	return ctx.nav.is_area_free(pos, clearance)


func _place_tree(pos: Vector3) -> bool:
	if not _ground_ok(pos, 1.7):
		return false
	var node := ResourceNode.new()
	var pine := rng.randf() < 0.55
	node.setup_tree(ctx.config.tree_wood, ctx.config.tree_regrow_time, rng.randi_range(0, 3), pine, rng.randf_range(0.85, 1.2))
	_add_node(node, pos)
	_counts.trees += 1
	return true


func _place_rock(pos: Vector3) -> bool:
	var s := rng.randf_range(0.8, 1.3)
	if not _ground_ok(pos, 0.9 * s + 1.6):
		return false
	var node := ResourceNode.new()
	node.setup_rock(ctx.config.rock_stone, rng.randi_range(0, 3), s)
	_add_node(node, pos)
	_counts.rocks += 1
	return true


func _place_bush(pos: Vector3) -> bool:
	if not _ground_ok(pos, 1.6):
		return false
	var node := ResourceNode.new()
	node.setup_bush(ctx.config.bush_food, ctx.config.bush_regrow_interval, rng.randi_range(0, 3), rng.randf_range(0.9, 1.15))
	_add_node(node, pos)
	_counts.bushes += 1
	return true


func _add_node(node: ResourceNode, pos: Vector3) -> void:
	_resource_root.add_child(node)
	node.global_position = ctx.terrain.snap_to_ground(pos) - Vector3(0, 0.05, 0)
	node.rotation.y = rng.randf() * TAU
	ctx.nav.add_obstacle(node.global_position, node.obstacle_radius)
	ctx.resources.register(node)


# --------------------------------------------------------------------------
# Decoration (MultiMesh)
# --------------------------------------------------------------------------

func _build_decorations() -> void:
	var cfg := ctx.config
	var t := ctx.terrain
	var half := t.playable_half
	var deco := Node3D.new()
	deco.name = "Decoration"
	ctx.world_root.add_child(deco)

	# Grass tufts on gentle, dry, unoccupied ground.
	var grass: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var tries := 0
	while grass.size() < cfg.grass_instances and tries < cfg.grass_instances * 4:
		tries += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if not _deco_ok(x, z, 0.82):
			continue
		var s := rng.randf_range(0.55, 1.1)
		grass.append(_xf(x, z, s))
		grass_colors.append(Color(1, 1, 1).darkened(rng.randf() * 0.18))
	deco.add_child(_multimesh("Grass", MeshFactory.grass_tuft(), grass, grass_colors, false))

	var flowers: Array[Transform3D] = []
	var flower_colors: Array[Color] = []
	var palette := [Color(1.0, 0.95, 0.5), Color(0.95, 0.55, 0.75), Color(0.75, 0.7, 1.0), Color(1, 1, 1)]
	tries = 0
	while flowers.size() < cfg.flower_instances and tries < cfg.flower_instances * 6:
		tries += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if not _deco_ok(x, z, 0.88):
			continue
		flowers.append(_xf(x, z, rng.randf_range(0.8, 1.3)))
		flower_colors.append(palette[rng.randi() % palette.size()])
	deco.add_child(_multimesh("Flowers", MeshFactory.flower(), flowers, flower_colors, false))

	var pebbles: Array[Transform3D] = []
	tries = 0
	while pebbles.size() < cfg.pebble_instances and tries < cfg.pebble_instances * 6:
		tries += 1
		var x := rng.randf_range(-half - 6.0, half + 6.0)
		var z := rng.randf_range(-half - 6.0, half + 6.0)
		if t.height_at(x, z) < t.water_level - 1.0 or ctx.nav.is_occupied(Vector3(x, 0, z)):
			continue
		pebbles.append(_xf(x, z, rng.randf_range(0.6, 1.8)))
	deco.add_child(_multimesh("Pebbles", MeshFactory.pebble(), pebbles, [], false))

	# Forests on the boundary mountains (not harvestable, outside the valley).
	var pines: Array[Transform3D] = []
	tries = 0
	while pines.size() < cfg.mountain_tree_instances and tries < cfg.mountain_tree_instances * 10:
		tries += 1
		var x := rng.randf_range(-t.half + 2.0, t.half - 2.0)
		var z := rng.randf_range(-t.half + 2.0, t.half - 2.0)
		if t.is_in_playable_area(x, z, -1.0):
			continue
		if t.normal_at(x, z).y < 0.62 or t.height_at(x, z) > cfg.mountain_height * 0.75:
			continue
		pines.append(_xf(x, z, rng.randf_range(0.9, 1.5)))
	var half_count := pines.size() / 2
	deco.add_child(_multimesh("MountainPinesA", MeshFactory.pine_tree(0), pines.slice(0, half_count), [], true))
	deco.add_child(_multimesh("MountainPinesB", MeshFactory.pine_tree(2), pines.slice(half_count), [], true))


func _deco_ok(x: float, z: float, min_normal_y: float) -> bool:
	var t := ctx.terrain
	if t.height_at(x, z) < t.water_level + 0.7:
		return false
	if t.normal_at(x, z).y < min_normal_y:
		return false
	var p := Vector3(x, 0, z)
	if ctx.nav.is_occupied(p):
		return false
	# Keep the camp plaza tidy.
	return Vector2(x, z).distance_to(t.settlement_center) > 4.5


func _xf(x: float, z: float, s: float) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
	return Transform3D(basis, ctx.terrain.snap_to_ground(Vector3(x, 0, z)) - Vector3(0, 0.03, 0))


func _multimesh(node_name: String, mesh: Mesh, xforms: Array, colors: Array, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
