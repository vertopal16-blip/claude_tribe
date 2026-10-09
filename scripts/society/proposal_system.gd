class_name ProposalSystem
extends RefCounted
## Collective planning.
##
## 1. Villagers notice problems from their own point of view (shortage of
##    food, no tools, nowhere to meet, unhonoured dead...).
## 2. Someone who knows how to address one (and has the drive) proposes a
##    project: a building or a tribe-wide effort.
## 3. The idea spreads through conversations; each listener supports or
##    opposes it for their own reasons (their concerns, profession, opinion
##    of the proposer, cost, rivalry, group loyalties).
## 4. The tribe's government decides (consensus, chief or council).
## 5. Approved buildings are placed and built by the villagers; projects can
##    stall and fail. Outcomes are remembered and change reputations.

const CHECK_INTERVAL := 15.0
const PROPOSE_INTERVAL := 40.0
const BUILD_DEADLINE_DAYS := 7
const PENDING_DAYS := 4

## Effort proposals (no building): goal favoured by everyone for a day.
const EFFORTS := {&"food_drive": [&"gather_food", "a food drive"]}

var society: SocietySystem
## id -> proposal dict (see _new_proposal)
var proposals: Dictionary = {}
var next_id := 1
var completed := 0
var failed := 0
var _timer := 0.0
var _propose_timer := 0.0


func _init(s: SocietySystem) -> void:
	society = s


func label_of(p: Dictionary) -> String:
	if p["kind"] == "effort":
		return EFFORTS[StringName(p["type"])][1]
	return BuildingCatalog.get_def(StringName(p["type"])).display_name.to_lower()


# --------------------------------------------------------------------------
# Concerns and new proposals
# --------------------------------------------------------------------------

## What worries `v` about the tribe: [[type, kind, urgency, reason], ...]
func concerns(v: Villager) -> Array:
	var out := []
	var tribe := society.ctx.tribe
	var pop := tribe.population()
	var food := float(tribe.stockpile.get_amount(ResourceType.FOOD))
	var tech := society.tech
	var food_need := clampf(1.0 - food / (pop * 7.0), 0.0, 1.0)
	if v.emotions.get_value(&"fear") > 0.3:
		food_need = minf(1.0, food_need + 0.2)
	if food_need > 0.25:
		if tech.knows(v, &"agriculture") and _count(&"farm") < maxi(1, pop / 7):
			out.append([&"farm", "building", food_need, "We need a steady source of food."])
		else:
			out.append([&"food_drive", "effort", food_need, "Everyone should gather food until the stores fill up."])
	elif tech.knows(v, &"agriculture") and _count(&"farm") < maxi(1, pop / 8):
		out.append([&"farm", "building", 0.35, "Fields would feed our growing families."])
	if tech.knows(v, &"toolmaking") and _count(&"workshop") == 0 and pop >= 6:
		out.append([&"workshop", "building", 0.4 + v.personality.get_trait(&"industriousness") * 0.3, "With proper tools we'd work twice as well."])
	if tech.knows(v, &"carpentry") and _count(&"longhouse") == 0 and pop >= BuildingCatalog.get_def(&"longhouse").min_population:
		out.append([&"longhouse", "building", 0.3 + v.personality.get_trait(&"sociability") * 0.4, "We need a place to meet and decide together."])
	var dead := society.history.count(&"death")
	if _count(&"shrine") == 0 and dead >= 2:
		out.append([&"shrine", "building", 0.2 + v.emotions.get_value(&"grief") * 0.6 + society.culture.norm(&"spirituality") * 0.4,
				"Our dead deserve a place to be honoured."])
	# What the tribe's culture asks for: gathering places, totems, memorials.
	society.culture.add_concerns(v, out)
	return out


func _count(def_id: StringName) -> int:
	var n := 0
	for b in society.ctx.tribe.buildings:
		if b.def.id == def_id:
			n += 1
	for p in proposals.values():
		if p["type"] == String(def_id) and p["state"] in ["open", "approved"]:
			n += 1
	return n


func open_proposal_for(type: StringName) -> Dictionary:
	for p in proposals.values():
		if p["type"] == String(type) and p["state"] in ["open", "approved"]:
			return p
	return {}


func _maybe_propose() -> void:
	for v in society.ctx.tribe.villagers:
		if not v.is_adult():
			continue
		var drive := (v.personality.get_trait(&"ambition") + v.personality.get_trait(&"creativity")
				+ v.personality.get_trait(&"status_desire")) / 3.0
		for c in concerns(v):
			if not open_proposal_for(c[0]).is_empty():
				continue
			if society.rng.randf() < drive * c[2] * 0.25:
				_new_proposal(v, c[0], c[1], c[3], c[4] if c.size() > 4 else -1)
				return  # one new idea at a time


func _new_proposal(v: Villager, type: StringName, kind: String, reason: String, subject: int = -1) -> Dictionary:
	var p := {"id": next_id, "type": String(type), "kind": kind, "proposer": v.villager_id, "reason": reason,
		"day": SimClock.get_day(), "state": "open", "stances": {str(v.villager_id): 1}, "site": -1, "deadline": 0,
		"subject": subject}
	if subject >= 0:
		society.culture.on_monument_planned(type, subject)
	proposals[next_id] = p
	next_id += 1
	society.ctx.social.remember(v, &"proposed_project", -1, -1, -1, label_of(p))
	society.history.add(&"proposal", "%s proposed %s: \"%s\"" % [v.villager_name,
			("building a " + label_of(p)) if kind == "building" else label_of(p), reason], [v.villager_id])
	return p


# --------------------------------------------------------------------------
# Opinions
# --------------------------------------------------------------------------

## How much `v` favours proposal `p` (-1 .. 1) and why (for dialogue).
func evaluate(v: Villager, p: Dictionary) -> Array:
	var social := society.ctx.social
	var type := StringName(p["type"])
	var score := 0.0
	var why := ""
	for c in concerns(v):
		if c[0] == type:
			score += c[2]
			why = c[3]
	# Professional interest
	var prof := String(v.profession)
	if type == &"farm" and prof in ["Farmer", "Forager"]:
		score += 0.3
	if type == &"workshop" and prof in ["Toolmaker", "Stoneworker", "Woodcutter", "Builder"]:
		score += 0.3
	if type == &"food_drive" and prof in ["Woodcutter", "Stoneworker", "Builder"]:
		score -= 0.25  # they'd have to drop their own work
	# The proposer: friends back friends, rivals oppose rivals.
	var pid: int = p["proposer"]
	if pid != v.villager_id:
		score += social.graph.affinity(v.villager_id, pid) * 0.4 + social.graph.respect(v.villager_id, pid) * 0.3
		if social.graph.has_tag(v.villager_id, pid, &"rival") or social.graph.has_tag(v.villager_id, pid, &"enemy"):
			score -= 0.5
		# Competitive people dislike seeing someone else gain from a success.
		score -= v.personality.get_trait(&"competitiveness") * 0.15
		score += society.groups.alignment(v.villager_id, pid) * 0.25
	# Cost versus what we have; cautious people worry more.
	if p["kind"] == "building":
		var def := BuildingCatalog.get_def(type)
		var short := 0.0
		for k in def.costs:
			short += maxf(0.0, def.costs[k] - society.ctx.tribe.stockpile.get_amount(k))
		if short > 0.0:
			score -= minf(0.5, short / 60.0) * lerpf(1.4, 0.5, v.personality.get_trait(&"risk_tolerance"))
	score += society.groups.guild_interest(v, type) * 0.4
	# Beliefs: what the building stands for, and how the untried is seen.
	var first: bool = p["kind"] == "building" and _built(type) == 0
	var attitude := society.culture.project_attitude(v, type, first)
	score += attitude * 0.5
	if why == "" and absf(attitude) > 0.2:
		why = "It is what we believe in." if attitude > 0.0 else "It goes against how we live."
	return [clampf(score, -1.0, 1.0), why]


func _built(def_id: StringName) -> int:
	var n := 0
	for b in society.ctx.tribe.buildings:
		if b.def.id == def_id and b.is_complete:
			n += 1
	return n


func set_stance(id: int, voter: int, stance: int) -> void:
	if proposals.has(id):
		proposals[id]["stances"][str(voter)] = stance


func stance_of(id: int, voter: int) -> int:
	return int(proposals.get(id, {}).get("stances", {}).get(str(voter), 0))


## Weighted support (-1..1) using each voter's influence.
func support(p: Dictionary) -> float:
	var total := 0.0
	var net := 0.0
	for v in society.ctx.tribe.villagers:
		if not v.is_adult():
			continue
		var w := society.politics.influence(v)
		total += w
		net += w * int(p["stances"].get(str(v.villager_id), 0))
	return 0.0 if total <= 0.0 else net / total


# --------------------------------------------------------------------------
# Lifecycle
# --------------------------------------------------------------------------

func tick(dt: float) -> void:
	_propose_timer += dt
	if _propose_timer >= PROPOSE_INTERVAL:
		_propose_timer = 0.0
		_maybe_propose()
	_timer += dt
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	for p in proposals.values():
		match p["state"]:
			"open": _decide(p)
			"approved": _follow_up(p)


func _decide(p: Dictionary) -> void:
	var verdict := society.politics.decide(p, support(p))
	if verdict == "approved":
		_approve(p)
	elif verdict == "vetoed" or verdict == "rejected" or SimClock.get_day() - int(p["day"]) > PENDING_DAYS:
		p["state"] = verdict if verdict in ["vetoed", "rejected"] else "forgotten"
		var proposer := society.ctx.social.get_villager(p["proposer"])
		if proposer != null:
			if verdict == "vetoed":
				var leader := society.politics.primary_leader()
				society.ctx.social.remember(proposer, &"vetoed", leader, -1, -1, label_of(p))
			else:
				society.ctx.social.remember(proposer, &"project_failed", -1, -1, -1, label_of(p))
		society.history.add(&"proposal", "The proposal for %s was %s." % [label_of(p),
				{"vetoed": "vetoed by the leadership", "rejected": "rejected by the tribe"}.get(verdict, "forgotten")],
				[p["proposer"]])


func _approve(p: Dictionary) -> void:
	p["state"] = "approved"
	p["deadline"] = SimClock.get_day() + BUILD_DEADLINE_DAYS
	var proposer := society.ctx.social.get_villager(p["proposer"])
	if p["kind"] == "effort":
		var goal: StringName = EFFORTS[StringName(p["type"])][0]
		for v in society.ctx.tribe.villagers:
			# People who don't trust the leadership's call ignore it.
			if v.work_capacity() > 0.0 and society.politics.follows_decisions(v):
				v.brain.suggest(goal, 0.35, society.ctx.config.day_length_seconds, "The tribe agreed on %s" % label_of(p))
		p["state"] = "done"
		completed += 1
		society.history.add(&"proposal", "The tribe agreed to %s." % label_of(p), [p["proposer"]])
		if proposer != null:
			society.politics.add_prestige(proposer, 3.0)
		return
	var def := BuildingCatalog.get_def(StringName(p["type"]))
	var spot := society.ctx.tribe.planner.find_build_spot(def, proposer)
	var site: Building = null
	if spot != Vector3.INF:
		site = society.ctx.tribe.place_building(def, spot, false)
	if site == null:
		p["state"] = "failed"
		failed += 1
		society.history.add(&"proposal", "The %s was approved, but no place could be found for it." % label_of(p), [p["proposer"]])
		return
	site.project_id = p["id"]
	p["site"] = site.entity_id
	society.history.add(&"construction", "The tribe approved %s's plan: work begins on a %s." % [
			society.ctx.social.name_of(p["proposer"]), label_of(p)], [p["proposer"]])
	# Supporters pitch in.
	for v in society.ctx.tribe.villagers:
		if stance_of(p["id"], v.villager_id) > 0 and v.is_adult():
			v.brain.suggest(&"build", 0.2, society.ctx.config.day_length_seconds * 2.0, "Supporting the %s" % label_of(p))


func _follow_up(p: Dictionary) -> void:
	var site: Building = null
	for b in society.ctx.tribe.buildings:
		if b.entity_id == p["site"]:
			site = b
	if site == null:
		_fail(p, "the site was abandoned")
	elif SimClock.get_day() > int(p["deadline"]) and not site.is_complete:
		society.ctx.tribe.cancel_construction(site)
		_fail(p, "it was never finished")


## Called when a project building is completed.
func on_building_completed(b: Building) -> void:
	if b.project_id < 0 or not proposals.has(b.project_id):
		return
	var p: Dictionary = proposals[b.project_id]
	p["state"] = "completed"
	completed += 1
	var social := society.ctx.social
	var proposer := social.get_villager(p["proposer"])
	if proposer != null:
		social.remember(proposer, &"project_completed", -1, -1, b.entity_id, label_of(p))
		society.politics.add_prestige(proposer, 10.0)
	# Supporters trust the organiser more; opponents are proven wrong.
	for v in society.ctx.tribe.villagers:
		var st := stance_of(p["id"], v.villager_id)
		if v.villager_id == p["proposer"]:
			continue
		if st > 0:
			social.graph.adjust_field(v.villager_id, p["proposer"], "trust", 0.08)
			social.graph.adjust_field(v.villager_id, p["proposer"], "respect", 0.1)
		elif st < 0:
			social.graph.adjust_field(v.villager_id, p["proposer"], "respect", 0.05)
			v.emotions.feel(&"shame", 0.1, "Opposed the %s, which turned out well" % label_of(p), v.personality)
	society.culture.shift(&"industry", 0.02, "a shared project succeeded")
	society.history.add(&"construction", "The %s championed by %s is finished." % [label_of(p), social.name_of(p["proposer"])],
			[p["proposer"]])


func _fail(p: Dictionary, why: String) -> void:
	p["state"] = "failed"
	failed += 1
	var social := society.ctx.social
	var proposer := social.get_villager(p["proposer"])
	if proposer != null:
		social.remember(proposer, &"project_failed", -1, -1, -1, label_of(p))
		society.politics.add_prestige(proposer, -6.0)
	for v in society.ctx.tribe.villagers:
		if stance_of(p["id"], v.villager_id) < 0:
			v.emotions.feel(&"pride", 0.15, "Was right about the %s" % label_of(p), v.personality)
		elif stance_of(p["id"], v.villager_id) > 0:
			v.emotions.feel(&"frustration", 0.25, "The %s failed" % label_of(p), v.personality)
	society.politics.on_project_failed(p)
	society.history.add(&"construction", "The plan for a %s failed: %s." % [label_of(p), why], [p["proposer"]])


## The open proposal `v` cares most about promoting (supporters persuade others).
func advocacy(v: Villager) -> Dictionary:
	for p in proposals.values():
		if p["state"] == "open" and stance_of(p["id"], v.villager_id) > 0:
			return p
	return {}


func open_count() -> int:
	var n := 0
	for p in proposals.values():
		if p["state"] in ["open", "approved"]:
			n += 1
	return n


func to_dict() -> Dictionary:
	var ps := {}
	for id in proposals:
		ps[str(id)] = proposals[id]
	return {"proposals": ps, "next": next_id, "completed": completed, "failed": failed}


func load_dict(d: Dictionary) -> void:
	proposals.clear()
	for id in d["proposals"]:
		proposals[int(id)] = d["proposals"][id]
	next_id = int(d["next"])
	completed = int(d["completed"])
	failed = int(d["failed"])
