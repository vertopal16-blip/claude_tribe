class_name SettlementPlanner
extends RefCounted
## Decides when the tribe needs new buildings and where they go.
##
## Homes are built FOR someone: the homeless villager with the strongest claim
## (couples first, then the ambitious). The site is scored from that person's
## point of view - near family and friends, away from rivals, near the
## resources they work with, and close to or far from the centre depending on
## how independent they are - so each settlement's shape emerges from its
## people and differs between playthroughs.

const INTERVAL := 5.0
const MAX_AUTO_SITES := 1
const RING_START := 9.0
const RING_STEP := 2.5
## Candidates per ring are spaced about this many metres apart.
const CANDIDATE_SPACING := 4.5

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


## Every household (a single villager or a couple) wants a home of its own.
func _plan_housing() -> void:
	var auto_sites := 0
	for s in tribe.construction_sites():
		if not s.placed_by_player:
			auto_sites += 1
	if auto_sites >= MAX_AUTO_SITES:
		return
	var hut := BuildingCatalog.get_def(&"hut")
	var requester := pick_homeless()
	if requester == null:
		return
	var spot := find_build_spot(hut, requester)
	if spot == Vector3.INF:
		return
	var site := tribe.place_building(hut, spot, false)
	if site != null and requester != null:
		site.owner_ids.append(requester.villager_id)
		var partner := tribe.ctx.social.get_villager(tribe.ctx.social.partner_of(requester.villager_id))
		if partner != null and not _has_home(partner):
			site.owner_ids.append(partner.villager_id)
		elif partner != null:
			# Partner already has a home: this one becomes theirs too.
			for b in tribe.buildings:
				if b.owner_ids.has(partner.villager_id):
					site.owner_ids.append(partner.villager_id)
					break
		EventBus.notify("The tribe starts a hut for %s." % _owner_names(site), &"build")


## True if `v` owns a home (built or under construction). Lodging in someone
## else's hut doesn't count.
func _has_home(v: Villager) -> bool:
	for b in tribe.buildings:
		if b.owner_ids.has(v.villager_id):
			return true
	return false


func _owner_names(site: Building) -> String:
	var names: PackedStringArray = []
	for id in site.owner_ids:
		names.append(tribe.ctx.social.name_of(id))
	return " and ".join(names)


## The homeless villager with the strongest claim to the next home.
func pick_homeless() -> Villager:
	var best: Villager = null
	var best_score := -INF
	for v in tribe.villagers:
		# Children live with their parents; only adults set up a household.
		if v.is_dead or not v.is_adult() or _has_home(v):
			continue
		var partner := tribe.ctx.social.get_villager(tribe.ctx.social.partner_of(v.villager_id))
		if partner != null and _has_home(partner):
			continue  # moves in with their partner
		var score := v.personality.get_trait(&"ambition")
		if tribe.ctx.social.partner_of(v.villager_id) >= 0:
			score += 1.0
		if score > best_score:
			best_score = score
			best = v
	return best


## Best valid spot for `def` (from `requester`'s point of view if given),
## or Vector3.INF if none fits.
func find_build_spot(def: BuildingDef, requester: Villager = null) -> Vector3:
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
			var score := score_site(def, p, requester)
			if score > best_score:
				best_score = score
				best = p
		# Without a requester keep the camp compact: first ring with a valid spot.
		if requester == null and best != Vector3.INF:
			return best
		r += RING_STEP
	return best


## Desirability of a valid spot (higher is better).
func score_site(_def: BuildingDef, pos: Vector3, requester: Villager = null) -> float:
	var ctx := tribe.ctx
	var flatness := ctx.terrain.normal_at(pos.x, pos.z).y
	var distance := Vector2(pos.x - tribe.center.x, pos.z - tribe.center.z).length()
	if requester == null:
		return flatness * 10.0 - distance * 0.1
	var social := ctx.social
	var rid := requester.villager_id
	var score := flatness * 4.0
	# Communal villagers stay central, independent ones move to the edge.
	score += lerpf(-0.1, 0.06, requester.personality.get_trait(&"independence")) * distance
	# Live near people you like, away from people you don't (by their homes).
	for b in tribe.buildings:
		if b.owner_ids.is_empty():
			continue
		var d := pos.distance_to(b.global_position)
		if d > 40.0:
			continue
		var falloff := 5.0 * exp(-d / 12.0)
		for oid in b.owner_ids:
			if oid != rid:
				score += social.closeness(rid, oid) * falloff
	# Near the resources this villager works with (as far as they know).
	var goal := requester.brain.last_work_goal
	if VillagerBrain.GATHER_GOALS.has(goal):
		var type: int = VillagerBrain.GATHER_GOALS[goal]
		var known := 0
		for f in requester.knowledge.store.facts.values():
			if int(f["type"]) == type and (f["pos"] as Vector3).distance_to(pos) < 15.0:
				known += 1
		score += minf(known, 6) * 0.25
	return score
