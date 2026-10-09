class_name Tribe
extends Node3D
## The one and only tribe: its villagers, shared stockpile, buildings and the
## collective "needs" (resource demand, housing) that guide villager choices.

signal population_changed(count: int)

const VILLAGER_SCENE := preload("res://scenes/villager.tscn")
const SEPARATION_RADIUS := 0.75
## Cell size of the coarse villager index used for social proximity queries.
const NEAR_CELL := 10.0
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
var planner: SettlementPlanner

var _next_villager_id := 1
var _starting_huts: Array[Building] = []
var _goal_counts: Dictionary = {}
var _near_grid: Dictionary = {}  # Vector2i -> Array[Villager], rebuilt every tick
var _decisions_left := 0

## Performance instrumentation (milliseconds), shown in the debug overlay.
var perf_last_tick_ms := 0.0
var perf_avg_tick_ms := 0.0
var perf_max_tick_ms := 0.0
var perf_total_ms := 0.0
var perf_ticks := 0
## Accumulated milliseconds per tick section (whole run).
var perf_sections: Dictionary = {}
var _construction_need: Dictionary = ResourceType.empty_amounts()


func setup(context: WorldContext) -> void:
	ctx = context
	auto_build = ctx.config.auto_build_huts
	planner = SettlementPlanner.new(self)
	ctx.social = SocialSystem.new(ctx)
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
			_starting_huts.append(_spawn_building(hut_def, pos, true))
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
	ctx.social.setup_founders(villagers)
	# Founding couples each start with a hut of their own.
	var couples := ctx.social.founding_couples()
	for i in mini(couples.size(), _starting_huts.size()):
		var hut := _starting_huts[i]
		for id in couples[i]:
			hut.owner_ids.append(id)
			assign_home(ctx.social.get_villager(id), hut)


## Single entry point for new tribe members (future: births, migrants).
func add_villager(pos: Vector3, age: float) -> Villager:
	var id := _next_villager_id
	_next_villager_id += 1
	var v: Villager = VILLAGER_SCENE.instantiate()
	v.setup(ctx, id, NAMES[(id - 1) % NAMES.size()], age, TUNICS[(id - 1) % TUNICS.size()],
			HAIRS[ctx.rng.randi() % HAIRS.size()])
	ctx.world_root.add_child(v)
	v.place_at(ctx.terrain.snap_to_ground(pos))
	v.died.connect(_on_villager_died)
	villagers.append(v)
	ctx.social.register_villager(v)
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
	var ta := Time.get_ticks_usec()
	_perf_add(&"resources", ta - t0)
	_update_goal_counts()
	_update_construction_need()
	var tb := Time.get_ticks_usec()
	_perf_add(&"counts", tb - ta)
	_update_separation()
	var t1 := Time.get_ticks_usec()
	_perf_add(&"spatial", t1 - tb)
	for v in villagers.duplicate():
		v.sim_tick(dt)
	var t2 := Time.get_ticks_usec()
	_perf_add(&"villagers", t2 - t1)
	ctx.social.tick(dt)
	var t3 := Time.get_ticks_usec()
	_perf_add(&"social", t3 - t2)
	planner.tick(dt)
	_perf_add(&"planner", Time.get_ticks_usec() - t3)
	perf_last_tick_ms = (Time.get_ticks_usec() - t0) / 1000.0
	perf_avg_tick_ms = lerpf(perf_avg_tick_ms, perf_last_tick_ms, 0.05)
	perf_max_tick_ms = maxf(perf_max_tick_ms, perf_last_tick_ms)
	perf_total_ms += perf_last_tick_ms
	perf_ticks += 1


func _perf_add(section: StringName, usec: int) -> void:
	perf_sections[section] = float(perf_sections.get(section, 0.0)) + usec / 1000.0


## True mean over the whole run (the overlay's avg is a moving average).
func perf_mean_tick_ms() -> float:
	return perf_total_ms / maxf(1.0, perf_ticks)


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


## Living villagers within `radius` of `pos` (positions as of this tick).
func villagers_near(pos: Vector3, radius: float) -> Array[Villager]:
	var out: Array[Villager] = []
	var r2 := radius * radius
	var lo := Vector2i(int(floor((pos.x - radius) / NEAR_CELL)), int(floor((pos.z - radius) / NEAR_CELL)))
	var hi := Vector2i(int(floor((pos.x + radius) / NEAR_CELL)), int(floor((pos.z + radius) / NEAR_CELL)))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var cell = _near_grid.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for v: Villager in cell:
				if is_instance_valid(v) and not v.is_dead:
					var d := v.global_position - pos
					if d.x * d.x + d.z * d.z <= r2:
						out.append(v)
	return out


func _update_separation() -> void:
	# Cells as large as the push radius: neighbours are always in the 3x3 block.
	var cell := SEPARATION_RADIUS
	var grid := {}
	_near_grid.clear()
	for v in villagers:
		var nk := Vector2i(int(floor(v.global_position.x / NEAR_CELL)), int(floor(v.global_position.z / NEAR_CELL)))
		if not _near_grid.has(nk):
			_near_grid[nk] = [] as Array[Villager]
		_near_grid[nk].append(v)
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
	v.record_event(&"delivered", {"resource_type": cargo["type"], "amount": cargo["amount"]})


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
	# A hut built for this villager: they get a bed even if a lodger must move out.
	for b in buildings:
		if b.is_complete and b.owner_ids.has(v.villager_id) and _make_room(b, v):
			assign_home(v, b)
			return b
	# Move in with a partner who has room.
	var partner := ctx.social.get_villager(ctx.social.partner_of(v.villager_id))
	if partner != null and partner.home != null and is_instance_valid(partner.home) \
			and partner.home.is_complete and partner.home.free_beds() > 0:
		assign_home(v, partner.home)
		return partner.home
	var best: Building = null
	var best_d := INF
	for b in buildings:
		if b.is_complete and b.def.housing > 0 and b.free_beds() > _owners_without_bed(b):
			var d := b.global_position.distance_to(v.global_position)
			if d < best_d:
				best_d = d
				best = b
	if best != null:
		assign_home(v, best)
	return best


func assign_home(v: Villager, b: Building) -> void:
	if v == null or b == null:
		return
	if v.home != null and is_instance_valid(v.home) and v.home != b:
		v.home.release_bed(v)
	if b.is_complete and not b.claim_bed(v):
		return
	v.home = b


func _make_room(b: Building, v: Villager) -> bool:
	if b.claim_bed(v):
		return true
	for s in b.sleepers.duplicate():
		if s is Villager and not b.owner_ids.has(s.villager_id):
			b.release_bed(s)
			if s.home == b:
				s.home = null
			return b.claim_bed(v)
	return false


## Beds in `b` that must stay free for owners who haven't claimed them yet.
func _owners_without_bed(b: Building) -> int:
	var n := 0
	for id in b.owner_ids:
		var o := ctx.social.get_villager(id)
		if o != null and not b.sleepers.has(o):
			n += 1
	return n


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
	b.entity_id = ctx.allocate_entity_id()
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
	ctx.social.on_building_completed(b)
	EventBus.building_completed.emit(b)
	EventBus.notify("A new %s has been completed!" % b.def.display_name.to_lower(), &"build")


## Kept for callers that only need a spot; planning lives in SettlementPlanner.
func find_build_spot(def: BuildingDef) -> Vector3:
	return planner.find_build_spot(def)


# --------------------------------------------------------------------------
# Death
# --------------------------------------------------------------------------

func _on_villager_died(v: Villager, cause: String) -> void:
	villagers.erase(v)
	deaths += 1
	ctx.social.on_villager_died(v)
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
