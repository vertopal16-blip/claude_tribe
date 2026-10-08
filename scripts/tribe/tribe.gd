class_name Tribe
extends Node3D
## The one and only tribe: its villagers, shared stockpile, buildings and the
## collective "needs" (resource demand, housing) that guide villager choices.

signal population_changed(count: int)

const VILLAGER_SCENE := preload("res://scenes/villager.tscn")
const SEPARATION_RADIUS := 0.75
const PLANNER_INTERVAL := 5.0
const MAX_AUTO_SITES := 1
const MAX_SITES := 4

const NAMES: Array[String] = [
	"Aru", "Bela", "Kono", "Desh", "Imra", "Talo", "Neka", "Oren", "Sila", "Varu", "Mira", "Juno",
	"Kael", "Lysa", "Pako", "Runa", "Tavi", "Yara", "Zeph", "Ebo", "Hana", "Ilo", "Fenn", "Gaia"]
const TUNICS: Array[Color] = [
	Color(0.75, 0.32, 0.24), Color(0.27, 0.48, 0.70), Color(0.85, 0.66, 0.24), Color(0.40, 0.62, 0.36),
	Color(0.58, 0.36, 0.62), Color(0.86, 0.48, 0.25), Color(0.30, 0.62, 0.62), Color(0.72, 0.30, 0.45)]
const HAIRS: Array[Color] = [
	Color(0.23, 0.15, 0.09), Color(0.12, 0.09, 0.07), Color(0.45, 0.28, 0.13), Color(0.62, 0.45, 0.24)]

var ctx: WorldContext
var tribe_name := "The First Tribe"
var stockpile := Stockpile.new()
var villagers: Array[Villager] = []
var buildings: Array[Building] = []
var campfire: Building
var storage: Building
var center := Vector3.ZERO
var auto_build := true
var deaths := 0

var _next_villager_id := 1
var _planner_timer := 0.0
var _goal_counts: Dictionary = {}
var _decisions_left := 0

## Performance instrumentation (milliseconds), shown in the debug overlay.
var perf_last_tick_ms := 0.0
var perf_avg_tick_ms := 0.0
var perf_max_tick_ms := 0.0
var _construction_need: Dictionary = ResourceType.empty_amounts()


func setup(context: WorldContext) -> void:
	ctx = context
	auto_build = ctx.config.auto_build_huts
	var c := ctx.terrain.settlement_center
	center = ctx.terrain.snap_to_ground(Vector3(c.x, 0, c.y))
	campfire = _spawn_building(BuildingCatalog.get_def(&"campfire"), center, true)
	storage = _spawn_building(BuildingCatalog.get_def(&"stockpile"), center + Vector3(5.5, 0, 2.0), true)

	var hut_def := BuildingCatalog.get_def(&"hut")
	var placed := 0
	var angles := [PI * 1.25, PI * 1.75, PI * 0.75, PI * 0.25]
	for a in angles:
		if placed >= ctx.config.starting_huts:
			break
		var pos := center + Vector3(cos(a), 0, sin(a)) * 8.5
		if can_place(hut_def, pos) == "":
			_spawn_building(hut_def, pos, true)
			placed += 1

	stockpile.changed.connect(_on_stockpile_changed)
	stockpile.set_initial(ResourceType.FOOD, ctx.config.starting_food)
	stockpile.set_initial(ResourceType.WOOD, ctx.config.starting_wood)
	stockpile.set_initial(ResourceType.STONE, ctx.config.starting_stone)


func spawn_initial_villagers() -> void:
	for i in ctx.config.starting_villagers:
		var a := TAU * i / maxf(1.0, ctx.config.starting_villagers)
		var pos := center + Vector3(cos(a), 0, sin(a)) * 3.2
		var cell := ctx.nav.nearest_walkable_cell(ctx.nav.world_to_cell(pos), 6)
		if cell != NavGrid.INVALID_CELL:
			pos = ctx.nav.cell_to_world(cell)
		add_villager(pos, ctx.rng.randf_range(16.0, 42.0))


## Single entry point for new tribe members (future: births, migrants).
func add_villager(pos: Vector3, age: float) -> Villager:
	var id := _next_villager_id
	_next_villager_id += 1
	var v: Villager = VILLAGER_SCENE.instantiate()
	v.setup(ctx, id, NAMES[(id - 1) % NAMES.size()], age, TUNICS[(id - 1) % TUNICS.size()],
			HAIRS[ctx.rng.randi() % HAIRS.size()])
	ctx.world_root.add_child(v)
	v.global_position = ctx.terrain.snap_to_ground(pos)
	v.died.connect(_on_villager_died)
	villagers.append(v)
	EventBus.villager_spawned.emit(v)
	_emit_population()
	return v


func population() -> int:
	return villagers.size()


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------

func sim_tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_decisions_left = ctx.config.max_decisions_per_tick
	ctx.resources.sim_tick(dt)
	_update_goal_counts()
	_update_construction_need()
	_update_separation()
	for v in villagers.duplicate():
		v.sim_tick(dt)
	_planner_timer -= dt
	if _planner_timer <= 0.0:
		_planner_timer = PLANNER_INTERVAL
		_plan_construction()
	perf_last_tick_ms = (Time.get_ticks_usec() - t0) / 1000.0
	perf_avg_tick_ms = lerpf(perf_avg_tick_ms, perf_last_tick_ms, 0.05)
	perf_max_tick_ms = maxf(perf_max_tick_ms, perf_last_tick_ms)


## Villager brains ask before making a new (pathfinding) decision this tick.
func try_consume_decision() -> bool:
	if _decisions_left <= 0:
		return false
	_decisions_left -= 1
	return true


func _update_goal_counts() -> void:
	_goal_counts.clear()
	for v in villagers:
		if v.current_task != null:
			var g := v.current_task.goal_id
			_goal_counts[g] = int(_goal_counts.get(g, 0)) + 1


func _update_construction_need() -> void:
	_construction_need = ResourceType.empty_amounts()
	for b in buildings:
		if b.is_construction_site():
			for k in b.def.costs:
				_construction_need[k] += b.remaining_to_deliver(k)


## How badly the tribe needs more of a resource, 0..1, already discounted by
## how many villagers are gathering it right now.
func get_demand(type: int) -> float:
	var pop := maxf(1.0, population())
	var stock := float(stockpile.get_amount(type))
	var target := 20.0
	match type:
		ResourceType.FOOD:
			target = pop * 10.0 + 30.0
		ResourceType.WOOD:
			target = 40.0 + _construction_need[ResourceType.WOOD]
		ResourceType.STONE:
			target = 24.0 + _construction_need[ResourceType.STONE]
	var demand := clampf(1.0 - stock / target, 0.0, 1.0)
	if type == ResourceType.FOOD and stock < pop * 3.0:
		demand = 1.0
	if type != ResourceType.FOOD and _construction_need[type] > stock:
		demand = maxf(demand, 0.75)
	demand = maxf(demand, 0.1)
	var goal: StringName = &"gather_food" if type == ResourceType.FOOD else (&"gather_wood" if type == ResourceType.WOOD else &"gather_stone")
	var workers := int(_goal_counts.get(goal, 0))
	return demand / (1.0 + workers * 0.35)


func _update_separation() -> void:
	var cell := 1.5
	var grid := {}
	for v in villagers:
		v.movement.separation = Vector3.ZERO
		if v.is_hidden():
			continue
		var key := Vector2i(int(floor(v.global_position.x / cell)), int(floor(v.global_position.z / cell)))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(v)
	for key: Vector2i in grid:
		for v: Villager in grid[key]:
			var push := Vector3.ZERO
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var other_list = grid.get(key + Vector2i(dx, dy))
					if other_list == null:
						continue
					for o: Villager in other_list:
						if o == v:
							continue
						var d := v.global_position - o.global_position
						d.y = 0.0
						var dist := d.length()
						if dist < SEPARATION_RADIUS:
							if dist < 0.01:
								d = Vector3(cos(v.villager_id), 0, sin(v.villager_id))
								dist = 0.01
							push += d / dist * (SEPARATION_RADIUS - dist)
			v.movement.separation = push


# --------------------------------------------------------------------------
# Stockpile
# --------------------------------------------------------------------------

func deposit_inventory(v: Villager) -> void:
	var cargo := v.inventory.take_all()
	if int(cargo["amount"]) <= 0:
		return
	stockpile.add(cargo["type"], cargo["amount"])
	EventBus.villager_event.emit(v, &"delivered", cargo)


func _on_stockpile_changed(amounts: Dictionary) -> void:
	if storage:
		storage.update_storage_visual(amounts)
	EventBus.stockpile_changed.emit(amounts)


# --------------------------------------------------------------------------
# Housing & rest
# --------------------------------------------------------------------------

func housing_capacity() -> int:
	var cap := 0
	for b in buildings:
		if b.is_complete:
			cap += b.def.housing
	return cap


func planned_housing() -> int:
	var cap := 0
	for b in buildings:
		cap += b.def.housing
	return cap


func claim_bed(v: Villager) -> Building:
	if v.home != null and is_instance_valid(v.home) and v.home.is_complete and v.home.claim_bed(v):
		return v.home
	var best: Building = null
	var best_d := INF
	for b in buildings:
		if b.is_complete and b.def.housing > 0 and b.free_beds() > 0:
			var d := b.global_position.distance_to(v.global_position)
			if d < best_d:
				best_d = d
				best = b
	if best != null:
		if v.home != null and is_instance_valid(v.home):
			v.home.release_bed(v)
		best.claim_bed(v)
		v.home = best
	return best


func find_campfire_rest_spot(v: Villager) -> Vector3:
	var a := TAU * fposmod(v.villager_id * 0.618, 1.0)
	var r := 2.6 + float(v.villager_id % 3) * 0.9
	return campfire.global_position + Vector3(cos(a) * r, 0, sin(a) * r)


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func construction_sites() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.is_construction_site():
			out.append(b)
	return out


func has_build_job_for(v: Villager) -> bool:
	return not find_build_job(v).is_empty()


## Returns {"site": Building, "material": type or NONE for "go work"}; {} if none.
func find_build_job(v: Villager) -> Dictionary:
	var best := {}
	var best_d := INF
	for site in construction_sites():
		var d := site.global_position.distance_to(v.global_position)
		if d >= best_d:
			continue
		if site.materials_complete():
			if site.builders < site.def.max_builders:
				best = {"site": site, "material": ResourceType.NONE}
				best_d = d
			continue
		if not v.inventory.is_empty():
			continue
		for k in ResourceType.ALL:
			if site.unassigned_need(k) > 0 and stockpile.get_amount(k) > 0:
				best = {"site": site, "material": k}
				best_d = d
				break
	return best


## Empty string when the building can be placed, otherwise a reason.
func can_place(def: BuildingDef, pos: Vector3) -> String:
	var t := ctx.terrain
	var r := def.footprint_radius
	if not t.is_in_playable_area(pos.x, pos.z, r + 1.0):
		return "Outside the valley"
	if campfire != null and Vector2(pos.x - center.x, pos.z - center.z).length() > ctx.config.settlement_build_radius:
		return "Too far from the campfire"
	for b in buildings:
		var min_d := b.def.footprint_radius + r + 1.4
		if Vector2(pos.x - b.global_position.x, pos.z - b.global_position.z).length() < min_d:
			return "Too close to the %s" % b.def.display_name.to_lower()
	if not ctx.nav.is_area_free(pos, r + 0.9):
		return "Blocked by trees, rocks or water"
	var lo := INF
	var hi := -INF
	for i in 9:
		var p := pos if i == 8 else pos + Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0)) * r
		var h := t.height_at(p.x, p.z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	if hi - lo > 1.1:
		return "Ground too uneven"
	return ""


func place_building(def: BuildingDef, pos: Vector3, by_player: bool) -> Building:
	if construction_sites().size() >= MAX_SITES:
		EventBus.notify("Too many construction sites at once", &"warning")
		return null
	var reason := can_place(def, pos)
	if reason != "":
		if by_player:
			EventBus.notify("Can't build here: %s" % reason, &"warning")
		return null
	var b := _spawn_building(def, pos, false)
	b.placed_by_player = by_player
	EventBus.notify("%s construction site placed (%s)" % [def.display_name, def.cost_string()], &"build")
	return b


func cancel_construction(b: Building) -> void:
	if b == null or not is_instance_valid(b) or b.is_complete:
		return
	var refund := b.delivered_materials()
	for k in refund:
		stockpile.add(k, int(refund[k]))
	_remove_building(b)
	EventBus.notify("%s construction cancelled, materials returned" % b.def.display_name, &"build")


func _spawn_building(def: BuildingDef, pos: Vector3, complete: bool) -> Building:
	var b := Building.new()
	b.setup(def, complete)
	ctx.world_root.add_child(b)
	# Sit on the lowest point of the footprint so nothing floats.
	var y := ctx.terrain.height_at(pos.x, pos.z)
	for i in 8:
		var p := pos + Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0)) * def.footprint_radius * 0.8
		y = minf(y, ctx.terrain.height_at(p.x, p.z))
	b.global_position = Vector3(pos.x, y, pos.z)
	b.rotation.y = atan2(center.x - pos.x, center.z - pos.z) if pos.distance_to(center) > 0.5 else 0.0
	ctx.nav.add_obstacle(b.global_position, def.footprint_radius)
	buildings.append(b)
	b.completed.connect(_on_building_completed)
	EventBus.building_placed.emit(b)
	return b


func _remove_building(b: Building) -> void:
	buildings.erase(b)
	ctx.nav.remove_obstacle(b.global_position, b.def.footprint_radius)
	EventBus.building_removed.emit(b)
	b.queue_free()


func _on_building_completed(b: Building) -> void:
	EventBus.building_completed.emit(b)
	EventBus.notify("A new %s has been completed!" % b.def.display_name.to_lower(), &"build")


func _plan_construction() -> void:
	if not auto_build:
		return
	var hut := BuildingCatalog.get_def(&"hut")
	if planned_housing() >= population():
		return
	var auto_sites := 0
	for s in construction_sites():
		if not s.placed_by_player:
			auto_sites += 1
	if auto_sites >= MAX_AUTO_SITES:
		return
	var spot := find_build_spot(hut)
	if spot != Vector3.INF:
		place_building(hut, spot, false)


func find_build_spot(def: BuildingDef) -> Vector3:
	var r := 9.0
	while r <= ctx.config.settlement_build_radius:
		var steps := int(TAU * r / 4.0)
		var offset := ctx.rng.randf() * TAU
		for i in steps:
			var a := offset + TAU * i / steps
			var p := center + Vector3(cos(a), 0, sin(a)) * r
			if can_place(def, p) == "":
				return p
		r += 2.5
	return Vector3.INF


# --------------------------------------------------------------------------
# Death
# --------------------------------------------------------------------------

func _on_villager_died(v: Villager, cause: String) -> void:
	villagers.erase(v)
	deaths += 1
	var grave := MeshInstance3D.new()
	grave.mesh = MeshFactory.grave_marker()
	ctx.world_root.add_child(grave)
	grave.global_position = ctx.terrain.snap_to_ground(v.global_position)
	grave.rotation.y = ctx.rng.randf() * TAU
	EventBus.villager_died.emit(v, cause)
	EventBus.notify("%s has died of %s." % [v.villager_name, cause], &"death")
	_emit_population()
	v.queue_free()


func _emit_population() -> void:
	population_changed.emit(villagers.size())
	EventBus.population_changed.emit(villagers.size())
