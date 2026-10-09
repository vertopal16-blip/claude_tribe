class_name SettlementPlanner
extends RefCounted
## Decides when the tribe needs new buildings and where they go.
##
## Kept separate from Tribe so placement logic can grow independently. Today:
## the tribe builds huts when beds run short, at the best-scoring valid spot
## around the camp. Later, per-villager preferences (family, friends, rivals,
## independence, work places) feed into score_site() so the shape of each
## settlement emerges from its people.

const INTERVAL := 5.0
const MAX_AUTO_SITES := 1
const RING_START := 9.0
const RING_STEP := 2.5
## Candidates per ring are spaced about this many metres apart.
const CANDIDATE_SPACING := 4.0

var tribe: Tribe
var _timer := 0.0


func _init(t: Tribe) -> void:
	tribe = t


func tick(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = INTERVAL
	if tribe.auto_build:
		_plan_housing()


func _plan_housing() -> void:
	if tribe.planned_housing() >= tribe.population():
		return
	var auto_sites := 0
	for s in tribe.construction_sites():
		if not s.placed_by_player:
			auto_sites += 1
	if auto_sites >= MAX_AUTO_SITES:
		return
	var hut := BuildingCatalog.get_def(&"hut")
	var spot := find_build_spot(hut)
	if spot != Vector3.INF:
		tribe.place_building(hut, spot, false)


## Best valid spot for `def`, or Vector3.INF if none fits.
func find_build_spot(def: BuildingDef) -> Vector3:
	var ctx := tribe.ctx
	var best := Vector3.INF
	var best_score := -INF
	var r := RING_START
	while r <= ctx.config.settlement_build_radius:
		var steps := int(TAU * r / CANDIDATE_SPACING)
		var offset := ctx.rng.randf() * TAU
		for i in steps:
			var a := offset + TAU * i / steps
			var p := tribe.center + Vector3(cos(a), 0, sin(a)) * r
			if tribe.can_place(def, p) != "":
				continue
			var score := score_site(def, p)
			if score > best_score:
				best_score = score
				best = p
		# Rings are searched inside-out; stop at the first ring with a valid spot
		# so the camp stays compact (and the search stays cheap).
		if best != Vector3.INF:
			return best
		r += RING_STEP
	return best


## Desirability of a valid spot (higher is better). Currently prefers flat,
## close ground; this is where social and personal preferences plug in.
func score_site(_def: BuildingDef, pos: Vector3) -> float:
	var ctx := tribe.ctx
	var flatness := ctx.terrain.normal_at(pos.x, pos.z).y
	var distance := Vector2(pos.x - tribe.center.x, pos.z - tribe.center.z).length()
	return flatness * 10.0 - distance * 0.1
