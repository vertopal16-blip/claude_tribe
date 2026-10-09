class_name SocietySystem
extends RefCounted
## Tribe-level society: the chronicle and the systems that shape the tribe as
## a whole - demographics, professions, discoveries, collective planning,
## politics, groups, culture and economy. Each runs on its own slow cadence.
## This class also offers villagers the goals and conversation topics that
## come from those systems, so the brain and conversation system stay generic.

var ctx: WorldContext
var rng := RandomNumberGenerator.new()
var history := HistoryLog.new()
var demographics: DemographicsSystem
var professions: ProfessionSystem
var tech: TechSystem
var proposals: ProposalSystem
var politics: PoliticsSystem
var groups: GroupSystem
var culture: CultureSystem
var economy: EconomySystem
## mediator id -> dispute being mediated
var pending_mediation: Dictionary = {}

var _phase := 0


func _init(context: WorldContext) -> void:
	ctx = context
	rng.seed = hash([ctx.config.social_seed if ctx.config.social_seed != 0 else ctx.world_seed, "society"])
	demographics = DemographicsSystem.new(self)
	professions = ProfessionSystem.new(self)
	tech = TechSystem.new(self)
	proposals = ProposalSystem.new(self)
	politics = PoliticsSystem.new(self)
	groups = GroupSystem.new(self)
	culture = CultureSystem.new(self)
	economy = EconomySystem.new(self)
	EventBus.social_event.connect(_on_social_event)


func tick(dt: float) -> void:
	# Spread the heavier systems over different ticks.
	_phase = (_phase + 1) % 4
	demographics.tick(dt)
	culture.tick(dt)
	proposals.tick(dt)
	match _phase:
		0: professions.tick(dt * 4.0)
		1: tech.tick(dt * 4.0)
		2: politics.tick(dt * 4.0)
		3: groups.tick(dt * 4.0)


func _on_social_event(_v: Node, kind: StringName, _record: Dictionary) -> void:
	culture.on_social_event(_v as Villager, kind, _record)
	match kind:
		&"helped": politics.add_prestige(_v as Villager, 0.6)
		&"fought": politics.add_prestige(_v as Villager, -2.0)
		&"mediated": politics.mediations += 1


func _first_harvest() -> bool:
	var n := 0
	for b in ctx.tribe.buildings:
		n += b.harvests
	return n <= 1


func on_villager_added(v: Villager) -> void:
	demographics.register_name(v.villager_name)
	demographics.record_parents(v.villager_id, v.parent_ids)
	culture.register(v)


func on_villager_died(v: Villager, cause: String) -> void:
	history.add(&"death", "%s died of %s at the age of %d." % [v.villager_name, cause, int(v.age_years)], [v.villager_id])
	culture.on_death(v)


func on_skill_mastered(v: Villager, skill: StringName) -> void:
	ctx.social.remember(v, &"skill_mastered", -1, -1, -1, String(skill))
	politics.add_prestige(v, 5.0)
	history.add(&"skill", "%s has mastered %s." % [v.villager_name, skill], [v.villager_id])


func on_building_completed(b: Building) -> void:
	proposals.on_building_completed(b)
	culture.on_building_completed(b)
	if b.def.id != &"hut":
		history.add(&"construction", "A %s now stands in the settlement." % b.def.display_name.to_lower(), b.contributor_ids)


func on_harvest(v: Villager, site: Building, food: int) -> void:
	culture.on_harvest(v, food, site.harvests == 1 and _first_harvest())
	if site.harvests == 1:
		history.add(&"economy", "%s brought in the first harvest from the new farm (%d food)." % [v.villager_name, food], [v.villager_id])


# --------------------------------------------------------------------------
# Goals offered to villagers
# --------------------------------------------------------------------------

func add_work_goals(v: Villager, scores: Dictionary) -> void:
	var tribe := ctx.tribe
	var food_demand := tribe.get_demand(ResourceType.FOOD)
	if find_workplace(v, &"farm") != null and (tech.knows(v, &"agriculture") or v.skills.get_level(&"farming") > 10.0):
		scores[&"farm"] = food_demand * 0.5 + 0.12
	if tech.knows(v, &"fishing") and v.is_adult():
		scores[&"fish"] = food_demand * 0.45 + 0.05
	if tech.knows(v, &"toolmaking") and find_workplace(v, &"workshop") != null:
		var have := tribe.stockpile.get_amount(ResourceType.TOOLS)
		var want := maxf(0.0, 1.0 - have / maxf(1.0, tribe.population() * 0.4))
		scores[&"craft"] = want * 0.55
	if tech.knows(v, &"herbalism") and find_patient(v) != null:
		scores[&"heal"] = 0.75
	var c := culture.active_ceremony()
	if not c.is_empty() and not c["attendees"].has(v.villager_id):
		scores[&"ceremony"] = 0.01  # tiny base; the culture's invitation (a suggestion) carries it
	if not v.is_adult():
		return
	# Personal ambitions: lead the tribe, win support for a project.
	if politics.wants_to_lead(v) and not politics.is_leader(v) and ctx.tribe.population() >= 8:
		scores[&"campaign"] = 0.12 + 0.2 * v.personality.get_trait(&"ambition") + 0.1 * v.emotions.get_value(&"jealousy")
	if not proposals.advocacy(v).is_empty():
		scores[&"persuade"] = 0.12 + 0.2 * (v.personality.get_trait(&"ambition") + v.personality.get_trait(&"sociability")) * 0.5


## Goals this system creates tasks for (they may still find nothing to do).
const GOALS := [&"farm", &"fish", &"craft", &"heal", &"ceremony", &"campaign", &"persuade"]


func create_task(v: Villager, goal: StringName) -> VillagerTask:
	match goal:
		&"farm": return FarmTask.new(v, goal)
		&"fish": return FishTask.new(v, goal)
		&"craft": return CraftTask.new(v, goal)
		&"heal": return HealTask.new(v, goal)
		&"ceremony":
			var c := culture.active_ceremony()
			return null if c.is_empty() else CeremonyTask.new(v, goal, c)
		&"campaign":
			var target := _persuadable(v, func(o): return politics.endorsements.get(o.villager_id, -1) != v.villager_id)
			return null if target == null else TalkToTask.new(v, goal, target, &"endorse")
		&"persuade":
			var p := proposals.advocacy(v)
			var target := _persuadable(v, func(o): return proposals.stance_of(p.get("id", -1), o.villager_id) == 0)
			return null if target == null else TalkToTask.new(v, goal, target, &"discuss_proposal")
	return null


## Someone nearby worth talking round (approachable, not hostile).
func _persuadable(v: Villager, wanted: Callable) -> Villager:
	var best: Villager = null
	var best_v := -0.3
	for o in ctx.tribe.villagers_near(v.global_position, 40.0):
		if o == v or not o.is_adult() or not SocializeTask.approachable(o) or not wanted.call(o):
			continue
		var score := ctx.social.graph.affinity(v.villager_id, o.villager_id) + politics.influence(o) * 0.005
		if score > best_v:
			best_v = score
			best = o
	return best


func find_workplace(v: Villager, def_id: StringName) -> Building:
	var best: Building = null
	var best_d := INF
	for b in ctx.tribe.buildings:
		if b.def.id != def_id or not b.is_complete or b.workers >= 2:
			continue
		var d := b.global_position.distance_to(v.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func fishing_spot(v: Villager) -> Vector3:
	var t := ctx.terrain
	var region := v.get_region()
	var best := Vector3.INF
	var best_d := INF
	for i in 16:
		var a := TAU * i / 16.0
		var p2 := t.lake_center + Vector2(cos(a), sin(a)) * t.lake_radius * 1.2
		var cell := ctx.nav.nearest_walkable_cell(ctx.nav.world_to_cell(Vector3(p2.x, 0, p2.y)), 5)
		if cell == NavGrid.INVALID_CELL or ctx.nav.region_of_cell(cell) != region:
			continue
		var p := ctx.nav.cell_to_world(cell)
		var d := p.distance_to(v.global_position) + rng.randf() * 6.0
		if d < best_d:
			best_d = d
			best = p
	return best


func find_patient(v: Villager) -> Villager:
	for o in ctx.tribe.villagers_near(v.global_position, 40.0):
		if o != v and o.needs.health < 60.0 and not o.is_hidden():
			return o
	return null


# --------------------------------------------------------------------------
# Conversation topics from the society layer
# --------------------------------------------------------------------------

func add_topics(s: Villager, l: Villager, w: Dictionary, data: Dictionary) -> void:
	if not s.is_adult():
		return
	var t := tech.teachable(s, l)
	if t != &"":
		data["tech"] = t
		w[&"share_discovery"] = 0.6 + l.personality.get_trait(&"curiosity") * 0.6 + s.personality.get_trait(&"generosity") * 0.3
	var p := proposals.advocacy(s)
	if not p.is_empty() and l.is_adult() and proposals.stance_of(p["id"], l.villager_id) == 0:
		data["proposal"] = p["id"]
		w[&"discuss_proposal"] = 1.0 + s.personality.get_trait(&"ambition")
	var food := ctx.tribe.stockpile.get_amount(ResourceType.FOOD)
	if l.is_adult() and food < ctx.tribe.population() * 5:
		w[&"problem_food"] = 1.2
	var candidate: int = politics.endorsements.get(s.villager_id, s.villager_id if politics.wants_to_lead(s) else -1)
	if candidate >= 0 and l.is_adult() and politics.endorsements.get(l.villager_id, -1) != candidate and candidate != l.villager_id:
		data["candidate"] = candidate
		w[&"endorse"] = 0.4 + (0.8 if candidate == s.villager_id else 0.2)
	if not economy.is_communal() and s.tool_durability <= 0.0 and int(economy.private_tools.get(l.villager_id, 0)) > 0:
		w[&"trade"] = 1.5
	culture.add_topics(s, l, w, data)
	if pending_mediation.has(s.villager_id):
		w[&"mediate"] = 50.0


func to_dict() -> Dictionary:
	return {"history": history.to_dict(), "demographics": demographics.to_dict(), "professions": professions.to_dict(),
		"tech": tech.to_dict(), "proposals": proposals.to_dict(), "politics": politics.to_dict(),
		"groups": groups.to_dict(), "culture": culture.to_dict(), "economy": economy.to_dict()}


func load_dict(d: Dictionary) -> void:
	history.load_dict(d["history"])
	demographics.load_dict(d["demographics"])
	professions.load_dict(d["professions"])
	tech.load_dict(d["tech"])
	proposals.load_dict(d["proposals"])
	politics.load_dict(d["politics"])
	groups.load_dict(d["groups"])
	culture.load_dict(d["culture"])
	economy.load_dict(d["economy"])
