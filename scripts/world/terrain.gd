class_name Terrain
extends Node3D
## Procedural low-poly terrain: heightfield -> flat-shaded vertex-coloured mesh,
## trimesh collision, lake water surface and a mountain ring as world boundary.
##
## height_at() samples the exact triangles that are rendered, so anything placed
## on the ground sits precisely on the visible surface.

const COLLISION_LAYER := 1

var config: GameConfig
var size: float
var half: float
var cell: float
var resolution: int
var water_level: float
var playable_half: float
var lake_center := Vector2.ZERO
var lake_radius := 14.0
var settlement_center := Vector2.ZERO

var _heights := PackedFloat32Array()
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _color_noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func generate(cfg: GameConfig, seed_value: int) -> void:
	config = cfg
	size = cfg.world_size
	half = size * 0.5
	cell = maxf(0.5, cfg.terrain_cell_size)
	resolution = int(round(size / cell))
	water_level = cfg.water_level
	playable_half = cfg.get_playable_half_extent()
	_rng.seed = seed_value

	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.011
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_detail.seed = seed_value + 11
	_detail.frequency = 0.06
	_color_noise.seed = seed_value + 23
	_color_noise.frequency = 0.035

	lake_radius = _rng.randf_range(cfg.lake_radius_min, cfg.lake_radius_max)
	var lake_angle := _rng.randf() * TAU
	# Far enough that the basin never eats the settlement plateau, close enough to stay inside the mountains.
	var min_dist := cfg.settlement_flat_radius + lake_radius * 1.45 + 2.0
	var max_dist := maxf(min_dist, playable_half - lake_radius * 1.35)
	var lake_dist := _rng.randf_range(min_dist, lerpf(min_dist, max_dist, 0.5))
	lake_center = Vector2(cos(lake_angle), sin(lake_angle)) * lake_dist

	_build_heights()
	_build_mesh()
	_build_water()


# --------------------------------------------------------------------------
# Height function
# --------------------------------------------------------------------------

func _raw_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var n := _noise.get_noise_2d(x, z)
	var h := config.settlement_height + 0.4 + n * config.hill_height * 1.6 + _detail.get_noise_2d(x, z) * 0.25
	# Keep dry land above the water line except inside the lake.
	if h < water_level + 0.9:
		h = water_level + 0.9 + (h - water_level - 0.9) * 0.15

	# Flat settlement plateau.
	var ds := p.distance_to(settlement_center)
	var flat_t := smoothstep(config.settlement_flat_radius, config.settlement_flat_radius * 2.0, ds)
	h = lerpf(config.settlement_height, h, flat_t)

	# Lake basin with a wobbly shoreline.
	var to_lake := p - lake_center
	var ang := atan2(to_lake.y, to_lake.x)
	var wobble := 1.0 + 0.18 * sin(ang * 3.0 + 1.3) + 0.08 * sin(ang * 7.0)
	var dl := to_lake.length() / (lake_radius * wobble)
	var basin := 1.0 - smoothstep(0.55, 1.25, dl)
	h = lerpf(h, water_level - 2.4, basin)

	# Mountain ring outside the playable square.
	var edge := maxf(absf(x), absf(z)) - playable_half
	if edge > -4.0:
		var e := clampf((edge + 4.0) / (config.boundary_width + 4.0), 0.0, 1.0)
		h += pow(e, 1.5) * config.mountain_height * (0.75 + 0.35 * (n + 0.5))
	return h


func _build_heights() -> void:
	var count := resolution + 1
	_heights.resize(count * count)
	for j in count:
		for i in count:
			var x := -half + i * cell
			var z := -half + j * cell
			_heights[j * count + i] = _raw_height(x, z)


func _h(i: int, j: int) -> float:
	var count := resolution + 1
	i = clampi(i, 0, resolution)
	j = clampi(j, 0, resolution)
	return _heights[j * count + i]


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

## Height of the rendered surface at world x/z.
func height_at(x: float, z: float) -> float:
	var gx := clampf((x + half) / cell, 0.0, resolution - 0.0001)
	var gz := clampf((z + half) / cell, 0.0, resolution - 0.0001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var ha := _h(i, j)
	var hb := _h(i + 1, j)
	var hc := _h(i, j + 1)
	var hd := _h(i + 1, j + 1)
	if fx >= fz:
		return ha + (hb - ha) * fx + (hd - hb) * fz
	return ha + (hc - ha) * fz + (hd - hc) * fx


func normal_at(x: float, z: float) -> Vector3:
	var e := cell * 0.5
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < water_level + 0.25


func is_in_playable_area(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= playable_half - margin and absf(z) <= playable_half - margin


func snap_to_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


# --------------------------------------------------------------------------
# Mesh, collision, water
# --------------------------------------------------------------------------

func _face_color(center: Vector3, normal: Vector3) -> Color:
	var cn := _color_noise.get_noise_2d(center.x, center.z)
	var jitter := _rng.randf_range(-0.025, 0.025)
	var h := center.y
	var col: Color
	if h < water_level - 0.6:
		col = Color(0.42, 0.40, 0.30)
	elif h < water_level + 0.55:
		col = Color(0.86, 0.78, 0.55)
	elif normal.y < 0.66 or h > config.settlement_height + config.hill_height * 2.4:
		var rock_t := clampf((h - 8.0) / 20.0, 0.0, 1.0)
		col = Color(0.50, 0.49, 0.47).lerp(Color(0.62, 0.61, 0.60), rock_t)
		if h > config.mountain_height * 0.8 and normal.y > 0.55:
			col = Color(0.93, 0.94, 0.96)
	else:
		var grass_a := Color(0.36, 0.56, 0.24)
		var grass_b := Color(0.46, 0.63, 0.27)
		col = grass_a.lerp(grass_b, clampf(cn * 1.5 + 0.5, 0.0, 1.0))
		# Slightly darker on slopes, slightly dry on hill tops.
		col = col.darkened((1.0 - normal.y) * 0.6)
		if h > config.settlement_height + config.hill_height * 1.2:
			col = col.lerp(Color(0.62, 0.64, 0.36), 0.35)
	return Color(col.r + jitter, col.g + jitter, col.b + jitter * 0.5)


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in resolution:
		for i in resolution:
			var x0 := -half + i * cell
			var z0 := -half + j * cell
			var a := Vector3(x0, _h(i, j), z0)
			var b := Vector3(x0 + cell, _h(i + 1, j), z0)
			var c := Vector3(x0, _h(i, j + 1), z0 + cell)
			var d := Vector3(x0 + cell, _h(i + 1, j + 1), z0 + cell)
			_add_face(st, a, b, d)
			_add_face(st, a, d, c)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


func _add_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	if n.y < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	var col := _face_color((a + b + c) / 3.0, n)
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	var extent := lake_radius * 3.2
	plane.size = Vector2(extent, extent)
	plane.subdivide_width = 24
	plane.subdivide_depth = 24
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	plane.material = mat
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(lake_center.x, water_level, lake_center.y)
	add_child(water)
