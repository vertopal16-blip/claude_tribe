class_name Building
extends StaticBody3D
## A structure in the settlement. Starts as a construction site (when it has
## costs) and becomes functional once materials are delivered and work is done.

signal completed(building: Building)

const COLLISION_LAYER := 8  # bit 4 -> "buildings"

var def: BuildingDef
## Stable id from WorldContext.allocate_entity_id().
var entity_id: int = 0
var is_complete := false
var delivered: Dictionary = ResourceType.empty_amounts()
var in_transit: Dictionary = ResourceType.empty_amounts()
var work_done := 0.0
var builders := 0
var placed_by_player := false
var sleepers: Array[Node] = []
## Villagers this home was built for (they get first claim on its beds).
var owner_ids: Array[int] = []
## Villagers who delivered materials or worked on construction.
var contributor_ids: Array[int] = []
## Community project this building came from (-1 if none), see ProposalSystem.
var project_id := -1
## Farm crop growth 0..1 and harvests so far.
var crop_growth := 0.0
var harvests := 0
## Who is working here right now (farm / workshop), to avoid crowding.
var workers := 0
## Architectural era of the tribe's culture this building was decorated in (-1 = plain).
var style_era := -1
var _decor: MeshInstance3D
var _crops: MeshInstance3D

var _model: MeshInstance3D
var _scaffold: MeshInstance3D
var _foundation: MeshInstance3D
var _flame: MeshInstance3D
var _light: OmniLight3D
var _piles: Dictionary = {}
var _flicker_time := 0.0


func setup(building_def: BuildingDef, start_complete: bool) -> void:
	def = building_def
	is_complete = start_complete
	if start_complete:
		for k in def.costs:
			delivered[k] = int(def.costs[k])
		work_done = def.build_work


func _ready() -> void:
	collision_layer = COLLISION_LAYER
	collision_mask = 0
	name = "%s_%d" % [String(def.id).capitalize(), entity_id]
	var shape := CylinderShape3D.new()
	shape.radius = def.footprint_radius
	shape.height = 3.0 if def.housing > 0 else 1.2
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = shape.height * 0.5
	add_child(cs)
	_build_visuals()
	_refresh_visuals()
	set_process(def.is_campfire)


func _build_visuals() -> void:
	if def.is_campfire:
		_model = _add_mesh(MeshFactory.campfire())
		_flame = _add_mesh(MeshFactory.flame())
		_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.62, 0.3)
		_light.omni_range = 11.0
		_light.light_energy = 1.2
		_light.shadow_enabled = false
		_light.position.y = 1.2
		add_child(_light)
	elif def.is_storage:
		_model = _add_mesh(MeshFactory.stockpile_base())
		_piles[ResourceType.WOOD] = _add_mesh(MeshFactory.log_pile(), Vector3(-0.8, 0.15, -0.2))
		_piles[ResourceType.STONE] = _add_mesh(MeshFactory.stone_pile(), Vector3(0.75, 0.15, -0.5))
		_piles[ResourceType.FOOD] = _add_mesh(MeshFactory.food_baskets(), Vector3(0.5, 0.15, 0.7))
	else:
		_foundation = _add_mesh(MeshFactory.foundation(def.footprint_radius * 0.85))
		_model = _add_mesh(model_mesh(def))
		_scaffold = _add_mesh(MeshFactory.scaffold(def.footprint_radius * 0.92))
		if def.id == &"farm":
			_crops = _add_mesh(MeshFactory.crops(def.footprint_radius))


static func model_mesh(d: BuildingDef) -> Mesh:
	match d.id:
		&"farm": return MeshFactory.farm_field(d.footprint_radius)
		&"workshop": return MeshFactory.workshop()
		&"longhouse": return MeshFactory.longhouse()
		&"shrine": return MeshFactory.shrine()
		&"totem": return MeshFactory.totem()
		&"memorial_stone": return MeshFactory.memorial_stone()
		&"gathering_circle": return MeshFactory.gathering_circle()
	return MeshFactory.hut()


## Paint / carve this building in the style of a cultural era.
func apply_culture_style(era: int, colors: Dictionary) -> void:
	style_era = era
	if _decor == null:
		_decor = MeshInstance3D.new()
		add_child(_decor)
	_decor.mesh = MeshFactory.building_decor(def.id, colors)
	_decor.visible = is_complete


func _add_mesh(mesh: Mesh, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = offset
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	# Campfire flicker; brighter at night. Runs on scaled time so it freezes on pause.
	var sd := SimClock.scaled_delta(delta)
	if sd <= 0.0:
		return
	_flicker_time += sd * 9.0
	var night := 1.0 - SimClock.get_daylight()
	var flicker := 0.85 + 0.15 * sin(_flicker_time) * sin(_flicker_time * 0.37 + 1.0)
	_light.light_energy = lerpf(0.6, 2.6, night) * flicker
	_flame.scale = Vector3(1.0, flicker * 1.1, 1.0)


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func is_construction_site() -> bool:
	return not is_complete


func remaining_to_deliver(type: int) -> int:
	return maxi(0, int(def.costs.get(type, 0)) - int(delivered.get(type, 0)))


## Material still needed after counting what villagers are already carrying here.
func unassigned_need(type: int) -> int:
	return maxi(0, remaining_to_deliver(type) - int(in_transit.get(type, 0)))


func materials_complete() -> bool:
	for k in def.costs:
		if remaining_to_deliver(k) > 0:
			return false
	return true


func reserve_delivery(type: int, n: int) -> void:
	in_transit[type] = int(in_transit.get(type, 0)) + n


func cancel_delivery(type: int, n: int) -> void:
	in_transit[type] = maxi(0, int(in_transit.get(type, 0)) - n)


## Accepts up to `n` units of a reserved delivery. Returns how many were used.
func complete_delivery(type: int, n: int, by_id: int = -1) -> int:
	_add_contributor(by_id)
	cancel_delivery(type, n)
	var used := mini(n, remaining_to_deliver(type))
	delivered[type] = int(delivered.get(type, 0)) + used
	_refresh_visuals()
	return used


func material_progress() -> float:
	var total := def.total_cost()
	if total <= 0:
		return 1.0
	var have := 0
	for k in def.costs:
		have += mini(int(delivered.get(k, 0)), int(def.costs[k]))
	return float(have) / total


func work_progress() -> float:
	return 1.0 if def.build_work <= 0.0 else clampf(work_done / def.build_work, 0.0, 1.0)


## Adds construction work. Returns true when this call finished the building.
func add_work(amount: float, by_id: int = -1) -> bool:
	if is_complete or not materials_complete():
		return false
	_add_contributor(by_id)
	work_done += amount
	_refresh_visuals()
	if work_done >= def.build_work:
		is_complete = true
		_refresh_visuals()
		completed.emit(self)
		return true
	return false


func _add_contributor(id: int) -> void:
	if id >= 0 and not contributor_ids.has(id):
		contributor_ids.append(id)


## Materials delivered so far (used to refund a cancelled site).
func delivered_materials() -> Dictionary:
	return delivered.duplicate()


# --------------------------------------------------------------------------
# Housing
# --------------------------------------------------------------------------

func free_beds() -> int:
	if not is_complete:
		return 0
	_prune_sleepers()
	return def.housing - sleepers.size()


func claim_bed(v: Node) -> bool:
	if sleepers.has(v):
		return true
	if free_beds() <= 0:
		return false
	sleepers.append(v)
	return true


func release_bed(v: Node) -> void:
	sleepers.erase(v)


func _prune_sleepers() -> void:
	for i in range(sleepers.size() - 1, -1, -1):
		if not is_instance_valid(sleepers[i]):
			sleepers.remove_at(i)


# --------------------------------------------------------------------------
# Visuals
# --------------------------------------------------------------------------

func _refresh_visuals() -> void:
	if def == null or _model == null:
		return
	if def.is_storage or def.is_campfire:
		return
	if _crops:
		_crops.visible = is_complete and crop_growth > 0.02
		_crops.scale = Vector3(1.0, maxf(0.05, crop_growth), 1.0)
	if _decor:
		_decor.visible = is_complete
	if is_complete:
		_model.scale = Vector3.ONE
		_model.visible = true
		_scaffold.visible = false
	else:
		_scaffold.visible = true
		var w := work_progress()
		_model.visible = w > 0.0
		_model.scale = Vector3(1.0, maxf(0.05, w), 1.0)


## Farming: tending makes the crop grow; returns true when it is ripe.
func tend(amount: float) -> bool:
	crop_growth = minf(1.0, crop_growth + amount)
	_refresh_visuals()
	return crop_growth >= 1.0


func harvest_crop() -> void:
	crop_growth = 0.0
	harvests += 1
	_refresh_visuals()


func update_storage_visual(amounts: Dictionary) -> void:
	for k in _piles:
		var mi: MeshInstance3D = _piles[k]
		var a := int(amounts.get(k, 0))
		mi.visible = a > 0
		mi.scale = Vector3.ONE * clampf(0.55 + a / 60.0, 0.55, 1.6)


func describe_status() -> String:
	if is_complete:
		if def.housing > 0:
			_prune_sleepers()
			return "Shelter: %d / %d sleeping" % [sleepers.size(), def.housing]
		if def.id == &"farm":
			return "Crop %d%% grown  ·  %d harvests" % [int(crop_growth * 100.0), harvests]
		return "Operational"
	if not materials_complete():
		var parts: PackedStringArray = []
		for k in ResourceType.ALL:
			if def.costs.has(k):
				parts.append("%s %d/%d" % [ResourceType.display_name(k), delivered.get(k, 0), def.costs[k]])
		return "Awaiting materials: " + ", ".join(parts)
	return "Under construction: %d%%" % int(work_progress() * 100.0)
