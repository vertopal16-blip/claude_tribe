class_name MeshFactory
extends RefCounted
## Procedural low-poly meshes built from vertex-coloured, flat-shaded triangles.
##
## All meshes share ONE vertex-colour material so the renderer can batch them,
## and every mesh is cached by key so identical objects reuse the same ArrayMesh.

const C_TRUNK := Color(0.42, 0.28, 0.17)
const C_TRUNK_DARK := Color(0.33, 0.22, 0.14)
const C_PINE := Color(0.20, 0.42, 0.24)
const C_PINE_DARK := Color(0.15, 0.34, 0.20)
const C_LEAF := Color(0.36, 0.58, 0.25)
const C_LEAF_LIGHT := Color(0.47, 0.66, 0.29)
const C_ROCK := Color(0.55, 0.55, 0.56)
const C_ROCK_DARK := Color(0.44, 0.44, 0.47)
const C_BUSH := Color(0.25, 0.50, 0.22)
const C_BERRY := Color(0.80, 0.13, 0.20)
const C_SKIN := Color(0.85, 0.66, 0.50)
const C_HAIR := Color(0.23, 0.15, 0.09)
const C_LEGS := Color(0.36, 0.26, 0.18)
const C_STRAW := Color(0.80, 0.64, 0.35)
const C_STRAW_DARK := Color(0.66, 0.51, 0.27)
const C_WALL := Color(0.62, 0.45, 0.29)
const C_WOOD := Color(0.55, 0.37, 0.21)
const C_STONE_RING := Color(0.48, 0.47, 0.46)
const C_DIRT := Color(0.52, 0.42, 0.30)

static var _cache: Dictionary = {}
static var _vertex_material: StandardMaterial3D
static var _flame_material: StandardMaterial3D
static var _ring_materials: Dictionary = {}


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

static func vertex_material() -> StandardMaterial3D:
	if _vertex_material == null:
		_vertex_material = StandardMaterial3D.new()
		_vertex_material.vertex_color_use_as_albedo = true
		_vertex_material.vertex_color_is_srgb = true
		_vertex_material.roughness = 0.92
		_vertex_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _vertex_material


static func flame_material() -> StandardMaterial3D:
	if _flame_material == null:
		_flame_material = StandardMaterial3D.new()
		_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_material.vertex_color_use_as_albedo = true
		_flame_material.vertex_color_is_srgb = true
		_flame_material.emission_enabled = true
		_flame_material.emission = Color(1.0, 0.5, 0.15)
		_flame_material.emission_energy_multiplier = 2.0
	return _flame_material


static func ring_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _ring_materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = false
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ring_materials[key] = m
	return _ring_materials[key]


# --------------------------------------------------------------------------
# Low level helpers
# --------------------------------------------------------------------------

## Adds a triangle whose front face points away from `inside`.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, inside: Vector3) -> void:
	# Godot treats clockwise triangles as front-facing; for those, (c-a)x(b-a) is the outward normal.
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var center := (a + b + c) / 3.0
	if n.dot(center - inside) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(c)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _commit(st: SurfaceTool) -> ArrayMesh:
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, vertex_material())
	return mesh


static func _shade(col: Color, rng: RandomNumberGenerator, amount: float = 0.06) -> Color:
	var f := 1.0 + rng.randf_range(-amount, amount)
	return Color(col.r * f, col.g * f, col.b * f, col.a)


## Frustum / cylinder / cone between y0 and y1 (r1 = 0 gives a cone).
static func add_prism(st: SurfaceTool, center: Vector3, sides: int, r0: float, r1: float, y0: float, y1: float,
		col: Color, rng: RandomNumberGenerator = null, caps: bool = true, angle_offset: float = 0.0) -> void:
	var inside := center + Vector3(0, (y0 + y1) * 0.5, 0)
	for i in sides:
		var a0 := angle_offset + TAU * i / sides
		var a1 := angle_offset + TAU * (i + 1) / sides
		var b0 := center + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := center + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := center + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := center + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var c := col if rng == null else _shade(col, rng)
		if r1 > 0.0001:
			tri(st, b0, b1, t1, c, inside)
			tri(st, b0, t1, t0, c, inside)
		else:
			tri(st, b0, b1, t0, c, inside)
		if caps:
			tri(st, center + Vector3(0, y0, 0), b0, b1, col.darkened(0.15), inside + Vector3(0, 1, 0) * (y1 - y0))
			if r1 > 0.0001:
				tri(st, center + Vector3(0, y1, 0), t0, t1, col, inside - Vector3(0, 1, 0) * (y1 - y0))


## Axis aligned box.
static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, basis: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				corners.append(center + basis * Vector3(h.x * x, h.y * y, h.z * z))
	# indices: x,y,z bits -> 0..7 (x major)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f in faces:
		var shade := col.darkened(0.12) if f == faces[0] or f == faces[1] else col
		tri(st, corners[f[0]], corners[f[1]], corners[f[2]], shade, center)
		tri(st, corners[f[0]], corners[f[2]], corners[f[3]], shade, center)


## Jittered icosphere (subdivision 0 or 1) - used for foliage, rocks, heads.
static func add_blob(st: SurfaceTool, center: Vector3, radius: Vector3, col: Color, rng: RandomNumberGenerator,
		jitter: float = 0.15, subdivide: bool = false, shade_amount: float = 0.07) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5],
		[2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	if subdivide:
		var mid_cache := {}
		var new_faces: Array = []
		for f in faces:
			var m := []
			for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
				var key := mini(e[0], e[1]) * 1000 + maxi(e[0], e[1])
				if not mid_cache.has(key):
					verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
					mid_cache[key] = verts.size() - 1
				m.append(mid_cache[key])
			new_faces.append([f[0], m[0], m[2]])
			new_faces.append([f[1], m[1], m[0]])
			new_faces.append([f[2], m[2], m[1]])
			new_faces.append([m[0], m[1], m[2]])
		faces = new_faces
	var pts: Array[Vector3] = []
	for v in verts:
		var j := 1.0 + rng.randf_range(-jitter, jitter)
		pts.append(center + Vector3(v.x * radius.x, v.y * radius.y, v.z * radius.z) * j)
	for f in faces:
		var c := _shade(col, rng, shade_amount)
		# Slightly lighter on top faces for a sun-baked look.
		var up := (pts[f[0]] + pts[f[1]] + pts[f[2]]) / 3.0 - center
		if up.y > 0.0:
			c = c.lightened(0.05)
		tri(st, pts[f[0]], pts[f[1]], pts[f[2]], c, center)


# --------------------------------------------------------------------------
# Nature
# --------------------------------------------------------------------------

static func pine_tree(variant: int) -> ArrayMesh:
	var key := "pine_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var st := _begin()
	var height := rng.randf_range(4.2, 5.6)
	add_prism(st, Vector3.ZERO, 6, 0.22, 0.14, 0.0, 1.4, C_TRUNK, rng)
	var layers := 3
	for i in layers:
		var f := float(i) / layers
		var y0 := 1.0 + f * (height - 1.6)
		var r := lerpf(1.5, 0.75, f) * rng.randf_range(0.9, 1.1)
		var col := C_PINE if i % 2 == 0 else C_PINE_DARK
		add_prism(st, Vector3.ZERO, 7, r, 0.0, y0, y0 + lerpf(2.1, 1.7, f), col, rng, true, rng.randf() * TAU)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func round_tree(variant: int) -> ArrayMesh:
	var key := "round_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + variant
	var st := _begin()
	var trunk_h := rng.randf_range(1.6, 2.1)
	add_prism(st, Vector3.ZERO, 6, 0.24, 0.16, 0.0, trunk_h + 0.4, C_TRUNK, rng)
	add_blob(st, Vector3(0, trunk_h + 1.1, 0), Vector3(1.5, 1.25, 1.5), C_LEAF, rng, 0.12, true)
	var blobs := rng.randi_range(1, 2)
	for i in blobs:
		var a := rng.randf() * TAU
		add_blob(st, Vector3(cos(a) * 0.8, trunk_h + 1.6 + rng.randf() * 0.4, sin(a) * 0.8),
				Vector3.ONE * rng.randf_range(0.7, 0.95), C_LEAF_LIGHT, rng, 0.15, false)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func stump() -> ArrayMesh:
	if _cache.has("stump"):
		return _cache["stump"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var st := _begin()
	add_prism(st, Vector3.ZERO, 6, 0.3, 0.24, 0.0, 0.45, C_TRUNK, rng)
	add_prism(st, Vector3(0, 0.45, 0), 6, 0.2, 0.0, 0.0, 0.02, Color(0.78, 0.62, 0.42), null, false)
	var mesh := _commit(st)
	_cache["stump"] = mesh
	return mesh


static func rock(variant: int) -> ArrayMesh:
	var key := "rock_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3000 + variant
	var st := _begin()
	add_blob(st, Vector3(0, 0.45, 0), Vector3(1.05, 0.75, 0.95), C_ROCK, rng, 0.22, false, 0.1)
	add_blob(st, Vector3(0.65, 0.3, 0.35), Vector3(0.55, 0.45, 0.5), C_ROCK_DARK, rng, 0.2, false, 0.1)
	add_blob(st, Vector3(-0.5, 0.25, -0.45), Vector3(0.5, 0.38, 0.45), C_ROCK, rng, 0.2, false, 0.1)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func bush(variant: int) -> ArrayMesh:
	var key := "bush_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4000 + variant
	var st := _begin()
	add_blob(st, Vector3(0, 0.5, 0), Vector3(0.85, 0.6, 0.85), C_BUSH, rng, 0.15, false)
	add_blob(st, Vector3(0.45, 0.42, 0.25), Vector3(0.55, 0.45, 0.55), C_BUSH.lightened(0.08), rng, 0.15, false)
	add_blob(st, Vector3(-0.4, 0.4, -0.25), Vector3(0.5, 0.42, 0.5), C_BUSH.darkened(0.06), rng, 0.15, false)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func berries(variant: int) -> ArrayMesh:
	var key := "berries_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5000 + variant
	var st := _begin()
	for i in 11:
		var a := rng.randf() * TAU
		var e := rng.randf_range(0.1, 1.2)
		var p := Vector3(cos(a) * cos(e) * 0.8, 0.5 + sin(e) * 0.55, sin(a) * cos(e) * 0.8)
		add_blob(st, p, Vector3.ONE * 0.11, C_BERRY, rng, 0.1, false)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func grass_tuft() -> ArrayMesh:
	if _cache.has("grass"):
		return _cache["grass"]
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6000
	for i in 4:
		var a := TAU * i / 4.0 + rng.randf() * 0.5
		var base := Vector3(cos(a) * 0.08, 0, sin(a) * 0.08)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.06
		var tip := base * 2.5 + Vector3(0, rng.randf_range(0.35, 0.55), 0)
		var c := Color(0.33, 0.54, 0.22).lightened(rng.randf() * 0.1)
		tri(st, base - side, base + side, tip, c, base - Vector3(cos(a), 0, sin(a)))
	var mesh := _commit(st)
	# Thin blades look wrong when back-face culled.
	var mat := vertex_material().duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	_cache["grass"] = mesh
	return mesh


static func flower() -> ArrayMesh:
	if _cache.has("flower"):
		return _cache["flower"]
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6100
	add_prism(st, Vector3.ZERO, 3, 0.02, 0.02, 0.0, 0.3, Color(0.3, 0.5, 0.2), null, false)
	add_blob(st, Vector3(0, 0.33, 0), Vector3(0.09, 0.05, 0.09), Color(1, 1, 1), rng, 0.0, false, 0.0)
	var mesh := _commit(st)
	_cache["flower"] = mesh
	return mesh


static func pebble() -> ArrayMesh:
	if _cache.has("pebble"):
		return _cache["pebble"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6200
	var st := _begin()
	add_blob(st, Vector3(0, 0.05, 0), Vector3(0.22, 0.12, 0.18), C_ROCK, rng, 0.25, false, 0.1)
	var mesh := _commit(st)
	_cache["pebble"] = mesh
	return mesh


# --------------------------------------------------------------------------
# Villagers & carried items
# --------------------------------------------------------------------------

static func villager_body(tunic: Color, hair: Color) -> ArrayMesh:
	var key := "villager_%s_%s" % [tunic.to_html(), hair.to_html()]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var st := _begin()
	# Legs
	add_box(st, Vector3(-0.11, 0.3, 0), Vector3(0.14, 0.6, 0.16), C_LEGS)
	add_box(st, Vector3(0.11, 0.3, 0), Vector3(0.14, 0.6, 0.16), C_LEGS)
	# Tunic / torso
	add_prism(st, Vector3.ZERO, 6, 0.3, 0.22, 0.5, 1.15, tunic, null, true, PI / 6.0)
	# Belt
	add_prism(st, Vector3.ZERO, 6, 0.305, 0.3, 0.6, 0.66, tunic.darkened(0.4), null, false, PI / 6.0)
	# Arms
	add_box(st, Vector3(-0.32, 0.86, 0), Vector3(0.11, 0.48, 0.13), tunic.darkened(0.1), Basis(Vector3.FORWARD, -0.15))
	add_box(st, Vector3(0.32, 0.86, 0), Vector3(0.11, 0.48, 0.13), tunic.darkened(0.1), Basis(Vector3.FORWARD, 0.15))
	# Head + hair
	add_blob(st, Vector3(0, 1.38, 0), Vector3(0.2, 0.22, 0.2), C_SKIN, rng, 0.04, true, 0.03)
	add_blob(st, Vector3(0, 1.47, 0.04), Vector3(0.215, 0.15, 0.2), hair, rng, 0.05, false, 0.04)
	# Nose hint so facing is readable (-Z is forward)
	add_box(st, Vector3(0, 1.37, -0.2), Vector3(0.06, 0.07, 0.06), C_SKIN.darkened(0.08))
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func carried_item(resource_type: int) -> ArrayMesh:
	var key := "carry_%d" % resource_type
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + resource_type
	var st := _begin()
	match resource_type:
		ResourceType.WOOD:
			for i in 3:
				var off := Vector3((i - 1) * 0.13, (i % 2) * 0.1, 0)
				add_box(st, off, Vector3(0.12, 0.12, 0.7), C_WOOD.lightened(i * 0.05))
		ResourceType.STONE:
			add_blob(st, Vector3.ZERO, Vector3(0.22, 0.17, 0.2), C_ROCK, rng, 0.2, false, 0.1)
			add_blob(st, Vector3(0.12, 0.12, 0.05), Vector3(0.13, 0.11, 0.12), C_ROCK_DARK, rng, 0.2, false, 0.1)
		_:
			add_prism(st, Vector3(0, -0.15, 0), 7, 0.2, 0.25, 0.0, 0.25, C_STRAW_DARK, rng)
			add_blob(st, Vector3(0, 0.12, 0), Vector3(0.2, 0.08, 0.2), C_BERRY, rng, 0.2, false)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


# --------------------------------------------------------------------------
# Settlement
# --------------------------------------------------------------------------

static func hut() -> ArrayMesh:
	if _cache.has("hut"):
		return _cache["hut"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8000
	var st := _begin()
	add_prism(st, Vector3.ZERO, 9, 1.75, 1.6, 0.0, 1.35, C_WALL, rng, false)
	# Wall bands
	add_prism(st, Vector3.ZERO, 9, 1.77, 1.74, 0.25, 0.35, C_WALL.darkened(0.25), null, false)
	add_prism(st, Vector3.ZERO, 9, 1.69, 1.66, 0.95, 1.05, C_WALL.darkened(0.25), null, false)
	# Roof (two layered cones)
	add_prism(st, Vector3.ZERO, 9, 2.35, 0.9, 1.2, 2.25, C_STRAW, rng, true)
	add_prism(st, Vector3.ZERO, 9, 1.0, 0.0, 2.2, 3.15, C_STRAW_DARK, rng, true)
	# Door (+Z side)
	add_box(st, Vector3(0, 0.55, 1.68), Vector3(0.75, 1.1, 0.12), Color(0.24, 0.16, 0.1))
	# Roof tip pole
	add_prism(st, Vector3.ZERO, 4, 0.06, 0.04, 3.0, 3.5, C_TRUNK_DARK, null, true)
	var mesh := _commit(st)
	_cache["hut"] = mesh
	return mesh


static func scaffold(radius: float) -> ArrayMesh:
	var key := "scaffold_%.2f" % radius
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector3(cos(a) * radius, 0, sin(a) * radius)
		add_prism(st, p, 4, 0.07, 0.06, 0.0, 2.4, C_WOOD, null, true)
	add_prism(st, Vector3.ZERO, 6, radius + 0.06, radius + 0.06, 1.2, 1.3, C_WOOD.darkened(0.15), null, false)
	add_prism(st, Vector3.ZERO, 6, radius + 0.06, radius + 0.06, 2.2, 2.3, C_WOOD.darkened(0.15), null, false)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func foundation(radius: float) -> ArrayMesh:
	var key := "foundation_%.2f" % radius
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8100
	var st := _begin()
	add_prism(st, Vector3.ZERO, 12, radius + 0.2, radius, -0.4, 0.08, C_DIRT, rng, true)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func campfire() -> ArrayMesh:
	if _cache.has("campfire"):
		return _cache["campfire"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8200
	var st := _begin()
	for i in 9:
		var a := TAU * i / 9.0
		add_blob(st, Vector3(cos(a) * 0.85, 0.12, sin(a) * 0.85), Vector3(0.24, 0.18, 0.22), C_STONE_RING, rng, 0.2, false, 0.1)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var basis := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.5)
		add_box(st, Vector3(cos(a) * 0.25, 0.25, sin(a) * 0.25), Vector3(0.14, 0.14, 0.9), C_TRUNK_DARK, basis)
	add_prism(st, Vector3.ZERO, 8, 0.6, 0.6, -0.1, 0.03, Color(0.2, 0.17, 0.15), null, true)
	var mesh := _commit(st)
	_cache["campfire"] = mesh
	return mesh


static func flame() -> ArrayMesh:
	if _cache.has("flame"):
		return _cache["flame"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8300
	var st := _begin()
	add_prism(st, Vector3.ZERO, 5, 0.35, 0.0, 0.0, 1.0, Color(1.0, 0.55, 0.12), null, true)
	add_prism(st, Vector3(0.05, 0, 0.02), 4, 0.2, 0.0, 0.0, 0.7, Color(1.0, 0.85, 0.3), null, true, 0.6)
	var mesh := st.commit()
	mesh.surface_set_material(0, flame_material())
	_cache["flame"] = mesh
	return mesh


static func stockpile_base() -> ArrayMesh:
	if _cache.has("stockpile_base"):
		return _cache["stockpile_base"]
	var st := _begin()
	# Wooden platform of planks
	for i in 6:
		add_box(st, Vector3(-1.25 + i * 0.5, 0.08, 0), Vector3(0.46, 0.14, 2.8), C_WOOD.lightened((i % 2) * 0.06))
	# Corner posts
	for x in [-1.4, 1.4]:
		for z in [-1.3, 1.3]:
			add_prism(st, Vector3(x, 0, z), 4, 0.08, 0.07, 0.0, 0.7, C_TRUNK_DARK, null, true)
	var mesh := _commit(st)
	_cache["stockpile_base"] = mesh
	return mesh


static func log_pile() -> ArrayMesh:
	if _cache.has("log_pile"):
		return _cache["log_pile"]
	var st := _begin()
	var rows := [3, 2, 1]
	for r in rows.size():
		for i in rows[r]:
			var x: float = (i - (rows[r] - 1) * 0.5) * 0.3
			add_prism(st, Vector3(x, 0.15 + r * 0.26, 0), 6, 0.14, 0.14, -0.55, 0.55, C_WOOD.lightened(0.04 * i), null, true)
	var mesh := _commit(st)
	# Logs are built along Y, rotate them to lie along Z.
	var rotated := _transform_mesh(mesh, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.15, 0)), "log_pile")
	return rotated


static func stone_pile() -> ArrayMesh:
	if _cache.has("stone_pile"):
		return _cache["stone_pile"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8400
	var st := _begin()
	for i in 6:
		var a := TAU * i / 6.0
		add_blob(st, Vector3(cos(a) * 0.3, 0.15, sin(a) * 0.3), Vector3(0.22, 0.17, 0.2), C_ROCK, rng, 0.2, false, 0.12)
	add_blob(st, Vector3(0, 0.38, 0), Vector3(0.25, 0.18, 0.22), C_ROCK_DARK, rng, 0.2, false, 0.12)
	var mesh := _commit(st)
	_cache["stone_pile"] = mesh
	return mesh


static func food_baskets() -> ArrayMesh:
	if _cache.has("food_baskets"):
		return _cache["food_baskets"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8500
	var st := _begin()
	for i in 3:
		var p := Vector3((i - 1) * 0.5, 0, (i % 2) * 0.3)
		add_prism(st, p, 7, 0.2, 0.26, 0.0, 0.32, C_STRAW_DARK, rng)
		add_blob(st, p + Vector3(0, 0.33, 0), Vector3(0.22, 0.08, 0.22), C_BERRY, rng, 0.25, false)
	var mesh := _commit(st)
	_cache["food_baskets"] = mesh
	return mesh


static func grave_marker() -> ArrayMesh:
	if _cache.has("grave"):
		return _cache["grave"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8600
	var st := _begin()
	add_blob(st, Vector3(0, 0.08, 0), Vector3(0.45, 0.12, 0.75), C_DIRT, rng, 0.1, false)
	add_box(st, Vector3(0, 0.45, -0.55), Vector3(0.4, 0.7, 0.14), C_ROCK)
	var mesh := _commit(st)
	_cache["grave"] = mesh
	return mesh


static func farm_field(radius: float) -> ArrayMesh:
	var key := "farm_%.2f" % radius
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var w := radius * 1.6
	add_box(st, Vector3(0, 0.04, 0), Vector3(w, 0.08, w), Color(0.42, 0.3, 0.19))
	for i in 5:
		var z := -w * 0.4 + i * w * 0.2
		add_box(st, Vector3(0, 0.1, z), Vector3(w * 0.9, 0.1, 0.25), Color(0.35, 0.24, 0.15))
	# Fence posts
	for x in [-w * 0.5, w * 0.5]:
		for z in [-w * 0.5, 0.0, w * 0.5]:
			add_prism(st, Vector3(x, 0, z), 4, 0.06, 0.05, 0.0, 0.7, C_WOOD, null, true)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


## Crop rows; scaled vertically by growth.
static func crops(radius: float) -> ArrayMesh:
	var key := "crops_%.2f" % radius
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100
	var st := _begin()
	var w := radius * 1.6
	for i in 5:
		var z := -w * 0.4 + i * w * 0.2
		for j in 7:
			var x := -w * 0.4 + j * w * 0.8 / 6.0
			add_prism(st, Vector3(x, 0.1, z), 4, 0.12, 0.0, 0.0, 0.8, Color(0.55, 0.7, 0.25).lerp(Color(0.85, 0.75, 0.3), rng.randf() * 0.5), rng, false)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func workshop() -> ArrayMesh:
	if _cache.has("workshop"):
		return _cache["workshop"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9200
	var st := _begin()
	for x in [-1.6, 1.6]:
		for z in [-1.2, 1.2]:
			add_prism(st, Vector3(x, 0, z), 4, 0.12, 0.1, 0.0, 2.0, C_TRUNK_DARK, null, true)
	add_box(st, Vector3(0, 2.15, 0), Vector3(3.8, 0.12, 3.0), C_STRAW_DARK, Basis(Vector3.RIGHT, 0.12))
	add_box(st, Vector3(-0.5, 0.45, 0), Vector3(1.4, 0.9, 0.8), C_WOOD)  # workbench
	add_blob(st, Vector3(0.9, 0.35, 0.3), Vector3(0.45, 0.35, 0.4), C_ROCK, rng, 0.15, false)  # anvil stone
	add_box(st, Vector3(1.3, 0.3, -0.8), Vector3(0.6, 0.6, 0.6), C_WOOD.darkened(0.2))
	var mesh := _commit(st)
	_cache["workshop"] = mesh
	return mesh


static func longhouse() -> ArrayMesh:
	if _cache.has("longhouse"):
		return _cache["longhouse"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9300
	var st := _begin()
	add_box(st, Vector3(0, 0.75, 0), Vector3(6.0, 1.5, 3.2), C_WALL)
	# Pitched roof made of two slanted boxes
	add_box(st, Vector3(0, 2.0, -0.85), Vector3(6.6, 0.18, 2.2), C_STRAW, Basis(Vector3.RIGHT, 0.6))
	add_box(st, Vector3(0, 2.0, 0.85), Vector3(6.6, 0.18, 2.2), C_STRAW, Basis(Vector3.RIGHT, -0.6))
	add_box(st, Vector3(0, 0.6, 1.62), Vector3(1.0, 1.2, 0.1), Color(0.24, 0.16, 0.1))
	for x in [-2.8, 2.8]:
		add_prism(st, Vector3(x, 0, 1.7), 4, 0.1, 0.08, 0.0, 2.6, C_TRUNK_DARK, null, true)
	var mesh := _commit(st)
	_cache["longhouse"] = mesh
	return mesh


static func shrine() -> ArrayMesh:
	if _cache.has("shrine"):
		return _cache["shrine"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9400
	var st := _begin()
	for i in 7:
		var a := TAU * i / 7.0
		add_box(st, Vector3(cos(a) * 1.6, 0.6, sin(a) * 1.6), Vector3(0.4, 1.2 + rng.randf() * 0.5, 0.3), C_ROCK.lightened(rng.randf() * 0.1),
				Basis(Vector3.UP, -a))
	add_prism(st, Vector3.ZERO, 6, 0.25, 0.18, 0.0, 2.6, C_TRUNK, rng, true)  # totem
	add_blob(st, Vector3(0, 2.7, 0), Vector3(0.35, 0.3, 0.35), Color(0.75, 0.3, 0.2), rng, 0.1, false)
	var mesh := _commit(st)
	_cache["shrine"] = mesh
	return mesh


## Flat ring used for selection / hover feedback.
static func ring(radius: float, width: float = 0.12, segments: int = 32) -> ArrayMesh:
	var key := "ring_%.2f_%.2f" % [radius, width]
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var i0 := Vector3(cos(a0), 0, sin(a0)) * (radius - width)
		var i1 := Vector3(cos(a1), 0, sin(a1)) * (radius - width)
		var o0 := Vector3(cos(a0), 0, sin(a0)) * radius
		var o1 := Vector3(cos(a1), 0, sin(a1)) * radius
		tri(st, i0, o0, o1, Color.WHITE, Vector3(0, -1, 0))
		tri(st, i0, o1, i1, Color.WHITE, Vector3(0, -1, 0))
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func _transform_mesh(mesh: ArrayMesh, xf: Transform3D, key: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	var arrays := st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = xf * verts[i]
		normals[i] = (xf.basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, vertex_material())
	_cache[key] = out
	return out


# --------------------------------------------------------------------------
# Culture: adornments, painted decoration, monuments
# --------------------------------------------------------------------------

## What a villager wears to show the customs and roles they hold: a sash,
## a headband, a belt stripe (transparent colours are left out).
static func adornment(sash: Color, band: Color, belt: Color) -> ArrayMesh:
	var key := "adorn_%s_%s_%s" % [sash.to_html(), band.to_html(), belt.to_html()]
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	if sash.a > 0.0:
		add_box(st, Vector3(0, 0.86, 0), Vector3(0.09, 0.74, 0.5), sash, Basis(Vector3.FORWARD, 0.62))
	if band.a > 0.0:
		add_prism(st, Vector3(0, 0, 0.02), 8, 0.222, 0.222, 1.41, 1.47, band, null, false)
	if belt.a > 0.0:
		add_prism(st, Vector3.ZERO, 6, 0.312, 0.31, 0.6, 0.67, belt, null, false, PI / 6.0)
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


## One small mark of the tribe's motif, centred at `c` on a wall facing `n`.
static func _motif_mark(st: SurfaceTool, motif: String, c: Vector3, n: Vector3, col: Color, rng: RandomNumberGenerator) -> void:
	var yaw := atan2(n.x, n.z)
	var b := Basis(Vector3.UP, yaw)
	match motif:
		"dots":
			for dy in [-0.12, 0.12]:
				add_box(st, c + Vector3(0, dy, 0), Vector3(0.1, 0.1, 0.05), col, b)
		"zigzags":
			add_box(st, c + b * Vector3(-0.08, 0, 0), Vector3(0.06, 0.32, 0.05), col, b * Basis(Vector3.FORWARD, 0.6))
			add_box(st, c + b * Vector3(0.08, 0, 0), Vector3(0.06, 0.32, 0.05), col, b * Basis(Vector3.FORWARD, -0.6))
		"chevrons":
			add_box(st, c + b * Vector3(-0.07, 0.04, 0), Vector3(0.06, 0.24, 0.05), col, b * Basis(Vector3.FORWARD, 0.9))
			add_box(st, c + b * Vector3(0.07, 0.04, 0), Vector3(0.06, 0.24, 0.05), col, b * Basis(Vector3.FORWARD, -0.9))
		"spirals", "rings":
			add_blob(st, c, Vector3(0.13, 0.13, 0.05), col, rng, 0.05, false, 0.0)
		"leaves":
			add_blob(st, c, Vector3(0.08, 0.2, 0.05), col, rng, 0.05, false, 0.0)
		"hatching":
			for dx in [-0.1, 0.0, 0.1]:
				add_box(st, c + b * Vector3(dx, 0, 0), Vector3(0.04, 0.3, 0.05), col, b)
		_:  # bands
			add_box(st, c, Vector3(0.36, 0.07, 0.05), col, b)


## Painted bands, motif marks, door posts and timber frames in the style of
## the era a building was made in.
static func building_decor(def_id: StringName, colors: Dictionary) -> ArrayMesh:
	var band: Color = colors.get("band", Color(0.7, 0.3, 0.2))
	var accent: Color = colors.get("accent", band)
	var motif: String = colors.get("motif", "")
	var posts: bool = colors.get("posts", false)
	var timber: bool = colors.get("timber", false)
	var key := "decor_%s_%s_%s_%s_%s_%s" % [def_id, band.to_html(), accent.to_html(), motif, posts, timber]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var st := _begin()
	match def_id:
		&"hut":
			add_prism(st, Vector3.ZERO, 9, 1.79, 1.77, 0.55, 0.72, band, null, false)
			for i in 9:
				var a := TAU * (i + 0.5) / 9.0
				var n := Vector3(cos(a), 0, sin(a))
				if absf(a - PI * 0.5) < 0.35:
					continue  # leave the door clear
				_motif_mark(st, motif, n * 1.74 + Vector3(0, 1.0, 0), n, accent, rng)
				if timber:
					var t := TAU * i / 9.0
					add_box(st, Vector3(cos(t) * 1.74, 0.67, sin(t) * 1.74), Vector3(0.12, 1.34, 0.12), C_TRUNK_DARK, Basis(Vector3.UP, -t))
			if posts:
				for x in [-0.5, 0.5]:
					add_prism(st, Vector3(x, 0, 1.78), 4, 0.08, 0.07, 0.0, 1.45, C_TRUNK_DARK, null, true)
					add_blob(st, Vector3(x, 1.55, 1.78), Vector3(0.12, 0.12, 0.12), accent, rng, 0.1, false)
		&"longhouse", &"workshop":
			var w := 6.0 if def_id == &"longhouse" else 3.4
			var d := 3.2 if def_id == &"longhouse" else 2.6
			add_box(st, Vector3(0, 0.75, d * 0.5 + 0.02), Vector3(w, 0.16, 0.04), band)
			add_box(st, Vector3(0, 0.75, -d * 0.5 - 0.02), Vector3(w, 0.16, 0.04), band)
			for i in 5:
				var x := -w * 0.4 + i * w * 0.2
				_motif_mark(st, motif, Vector3(x, 1.15, d * 0.5 + 0.03), Vector3.BACK, accent, rng)
		&"shrine":
			add_prism(st, Vector3.ZERO, 6, 0.27, 0.22, 1.2, 1.5, band, null, false)
			add_prism(st, Vector3.ZERO, 6, 0.22, 0.2, 1.9, 2.1, accent, null, false)
		&"totem":
			# Stacked carved segments in the tribe's colours, crowned with wings.
			var cols := [band, accent, band.darkened(0.2), accent.lightened(0.15)]
			for i in 4:
				var y0 := 0.6 + i * 0.75
				add_prism(st, Vector3.ZERO, 8, 0.36, 0.34, y0, y0 + 0.62, cols[i], rng, true)
				_motif_mark(st, motif, Vector3(0, y0 + 0.31, 0.36), Vector3.BACK, cols[(i + 1) % 4], rng)
			add_box(st, Vector3(0, 3.55, 0), Vector3(1.8, 0.16, 0.3), accent)
			add_blob(st, Vector3(0, 3.85, 0), Vector3(0.3, 0.28, 0.3), band, rng, 0.08, false)
		&"memorial_stone":
			add_box(st, Vector3(0, 1.3, 0), Vector3(0.84, 0.14, 0.42), band)
			_motif_mark(st, motif, Vector3(0, 1.75, 0.22), Vector3.BACK, accent, rng)
			_motif_mark(st, motif, Vector3(0, 0.85, 0.22), Vector3.BACK, accent, rng)
		&"gathering_circle":
			for i in 10:
				var a := TAU * i / 10.0
				add_box(st, Vector3(cos(a) * 4.0, 1.12, sin(a) * 4.0), Vector3(0.48, 0.14, 0.38), band if i % 2 == 0 else accent, Basis(Vector3.UP, -a))
	var mesh := _commit(st)
	_cache[key] = mesh
	return mesh


static func totem() -> ArrayMesh:
	if _cache.has("totem"):
		return _cache["totem"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9500
	var st := _begin()
	add_prism(st, Vector3.ZERO, 8, 0.32, 0.3, 0.0, 3.6, C_TRUNK, rng, true)
	add_blob(st, Vector3(0, 0.12, 0), Vector3(0.7, 0.18, 0.7), C_ROCK, rng, 0.15, false)
	var mesh := _commit(st)
	_cache["totem"] = mesh
	return mesh


static func memorial_stone() -> ArrayMesh:
	if _cache.has("memorial"):
		return _cache["memorial"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9600
	var st := _begin()
	add_box(st, Vector3(0, 1.1, 0), Vector3(0.8, 2.2, 0.4), C_ROCK.lightened(0.08))
	add_blob(st, Vector3(0, 0.1, 0), Vector3(0.9, 0.16, 0.6), C_ROCK_DARK, rng, 0.2, false)
	for i in 5:
		var a := TAU * i / 5.0
		add_blob(st, Vector3(cos(a) * 1.0, 0.12, sin(a) * 0.8), Vector3(0.18, 0.14, 0.18), C_ROCK, rng, 0.2, false)
	var mesh := _commit(st)
	_cache["memorial"] = mesh
	return mesh


static func gathering_circle() -> ArrayMesh:
	if _cache.has("gathering"):
		return _cache["gathering"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9700
	var st := _begin()
	for i in 10:
		var a := TAU * i / 10.0
		add_box(st, Vector3(cos(a) * 4.0, 0.55, sin(a) * 4.0), Vector3(0.45, 1.1 + rng.randf() * 0.3, 0.35), C_ROCK.lightened(rng.randf() * 0.1),
				Basis(Vector3.UP, -a))
	# Fire pit and log benches
	for i in 8:
		var a := TAU * i / 8.0
		add_blob(st, Vector3(cos(a) * 0.7, 0.1, sin(a) * 0.7), Vector3(0.16, 0.12, 0.16), C_STONE_RING, rng, 0.2, false)
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		add_box(st, Vector3(cos(a) * 2.4, 0.2, sin(a) * 2.4), Vector3(1.4, 0.3, 0.35), C_WOOD, Basis(Vector3.UP, -a + PI * 0.5))
	var mesh := _commit(st)
	_cache["gathering"] = mesh
	return mesh
