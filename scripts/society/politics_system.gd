class_name PoliticsSystem
extends RefCounted
## Status, influence and government.
##
## Prestige is earned (skills, successful projects, discoveries, help, age,
## family) and lost (failures, fights). Influence adds friends, family and
## persuasiveness. Government emerges and changes:
##   none       - small band, decisions by broad consensus
##   informal   - one person is widely looked up to; their word carries weight
##   chief      - chosen by endorsement once the tribe grows or in a crisis;
##                approves or vetoes projects, mediates disputes
##   hereditary - succession to an adult child, if the culture values lineage
##   council    - several respected members decide together (needs a meeting
##                place and a consensus-minded culture)
## Leaders can be challenged when their approval falls; transitions are real
## changes to who decides, not just text.

const CHECK_INTERVAL := 30.0

var society: SocietySystem
var government: StringName = &"none"
var leaders: Array[int] = []
var since_day := 1
## voter id -> candidate id
var endorsements: Dictionary = {}
## Unresolved disputes: [{"a", "b", "reason", "day"}]
var disputes: Array = []
var transitions := 0
var mediations := 0
var _timer := 0.0


func _init(s: SocietySystem) -> void:
	society = s


func title() -> String:
	match government:
		&"informal": return "respected elder" if leaders.size() > 0 and _villager(leaders[0]) != null and _villager(leaders[0]).life_stage() == &"elder" else "respected figure"
		&"chief": return "chief"
		&"hereditary": return "hereditary chief"
		&"council": return "council member"
	return ""


func government_label() -> String:
	match government:
		&"informal": return "Informal leadership (%s)" % _names(leaders)
		&"chief": return "Chief %s" % _names(leaders)
		&"hereditary": return "Hereditary chief %s" % _names(leaders)
		&"council": return "Council of %s" % _names(leaders)
	return "No leader - decisions by consensus"


func _names(ids: Array) -> String:
	return ", ".join(ids.map(func(i): return society.ctx.social.name_of(i)))


func _villager(id: int) -> Villager:
	return society.ctx.social.get_villager(id)


func primary_leader() -> int:
	return leaders[0] if not leaders.is_empty() else -1


func is_leader(v: Villager) -> bool:
	return leaders.has(v.villager_id)


# --------------------------------------------------------------------------
# Prestige and influence
# --------------------------------------------------------------------------

func add_prestige(v: Villager, amount: float) -> void:
	if v == null:
		return
	var before := v.prestige
	v.prestige = clampf(v.prestige + amount, 0.0, 100.0)
	# Competitive rivals don't like seeing someone rise.
	if amount >= 5.0:
		for rid in society.ctx.social.rivals_of(v.villager_id):
			var r := _villager(rid)
			if r != null and r.personality.get_trait(&"competitiveness") > 0.5:
				society.ctx.social.remember(r, &"rival_honored", v.villager_id)
	if before < 50.0 and v.prestige >= 50.0:
		society.history.add(&"leadership", "%s has become one of the most respected people in the tribe." % v.villager_name, [v.villager_id])


func influence(v: Villager) -> float:
	var social := society.ctx.social
	var inf := 5.0 + v.prestige + social.friends_of(v.villager_id).size() * 4.0 + social.kin_of(v.villager_id).size() * 3.0 \
			+ v.skills.get_level(&"persuasion") * 0.2
	if is_leader(v):
		inf += 15.0
	if v.life_stage() == &"elder":
		inf += 8.0 * society.culture.norm(&"tradition")
	return inf


## Average opinion adults hold of `v` (-1..1), from affinity, trust and respect.
func approval(v: Villager) -> float:
	var social := society.ctx.social
	var total := 0.0
	var n := 0
	for o in society.ctx.tribe.villagers:
		if o == v or not o.is_adult():
			continue
		var g := social.graph
		total += (g.affinity(o.villager_id, v.villager_id) + (g.trust(o.villager_id, v.villager_id) - 0.5) * 2.0
				+ g.respect(o.villager_id, v.villager_id)) / 3.0
		n += 1
	return 0.0 if n == 0 else total / n


## Do decisions of the current leadership carry weight with `v`?
func follows_decisions(v: Villager) -> bool:
	if leaders.is_empty():
		return true
	var g := society.ctx.social.graph
	var leader := leaders[0]
	return v.villager_id == leader or g.trust(v.villager_id, leader) >= 0.4 or v.personality.get_trait(&"loyalty") > 0.6


# --------------------------------------------------------------------------
# Decisions on proposals
# --------------------------------------------------------------------------

## Returns "approved", "vetoed", "rejected" or "pending".
func decide(p: Dictionary, support: float) -> String:
	var proposals := society.proposals
	match government:
		&"chief", &"hereditary":
			var chief := _villager(primary_leader())
			if chief == null:
				return "approved" if support > 0.4 else "pending"
			var stance := proposals.stance_of(p["id"], chief.villager_id)
			if stance == 0:
				# The chief forms an opinion when asked.
				var e: Array = proposals.evaluate(chief, p)
				stance = 1 if e[0] > 0.1 else (-1 if e[0] < -0.2 else 0)
				proposals.set_stance(p["id"], chief.villager_id, stance)
			if stance > 0 and support > -0.1:
				return "approved"
			if stance < 0 and support < 0.6:
				return "vetoed"
			# Overwhelming support carries a project even against the chief.
			return "approved" if support > 0.6 else "pending"
		&"council":
			var yes := 0
			var no := 0
			for id in leaders:
				var m := _villager(id)
				if m == null:
					continue
				var st := proposals.stance_of(p["id"], id)
				if st == 0:
					var e: Array = proposals.evaluate(m, p)
					st = 1 if e[0] > 0.05 else (-1 if e[0] < -0.15 else 0)
					proposals.set_stance(p["id"], id, st)
				if st > 0:
					yes += 1
				elif st < 0:
					no += 1
			if yes * 2 > leaders.size():
				return "approved"
			if no * 2 >= leaders.size():
				return "rejected"
			return "pending"
		&"informal":
			var figure := primary_leader()
			var bonus := 0.15 * proposals.stance_of(p["id"], figure)
			if support + bonus > 0.3:
				return "approved"
			return "rejected" if support + bonus < -0.3 else "pending"
	if support > 0.35:
		return "approved"
	return "rejected" if support < -0.3 else "pending"


func on_project_failed(p: Dictionary) -> void:
	# Failures under a leader's watch cost them standing.
	var l := _villager(primary_leader())
	if l != null and society.proposals.stance_of(p["id"], l.villager_id) > 0:
		add_prestige(l, -4.0)
		for v in society.ctx.tribe.villagers:
			if v != l:
				society.ctx.social.graph.adjust_field(v.villager_id, l.villager_id, "respect", -0.04)


# --------------------------------------------------------------------------
# Endorsements, elections and challenges
# --------------------------------------------------------------------------

## Would `v` want to lead?
func wants_to_lead(v: Villager) -> bool:
	if not v.is_adult():
		return false
	var p := v.personality
	return (p.get_trait(&"ambition") + p.get_trait(&"status_desire")) * 0.5 > 0.55 and v.prestige >= 15.0


func endorse(voter: int, candidate: int) -> void:
	if voter == candidate:
		return
	endorsements[voter] = candidate


## Count of living adults endorsing `candidate`.
func endorsers(candidate: int) -> int:
	var n := 0
	for voter in endorsements:
		if endorsements[voter] == candidate:
			var v := _villager(voter)
			if v != null and v.is_adult():
				n += 1
	return n


func _adults() -> int:
	var n := 0
	for v in society.ctx.tribe.villagers:
		if v.is_adult():
			n += 1
	return n


func tick(dt: float) -> void:
	_timer += dt
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	_prune()
	_prestige_drift()
	_update_government()
	_assign_mediation()


func _prune() -> void:
	for id in leaders.duplicate():
		if _villager(id) == null:
			leaders.erase(id)
			_on_leader_lost(id)
	for voter in endorsements.keys():
		var v := _villager(voter)
		var c := _villager(endorsements[voter])
		# An endorsement lapses when the voter dies or sours on the candidate.
		if v == null or c == null or society.ctx.social.graph.affinity(voter, endorsements[voter]) < -0.2:
			endorsements.erase(voter)


func _prestige_drift() -> void:
	for v in society.ctx.tribe.villagers:
		var target := 10.0 + (8.0 if v.life_stage() == &"elder" else 0.0) + society.demographics.children_of(v.villager_id).size() * 2.0
		for k in VillagerSkills.LIST:
			if v.skills.get_level(k) >= VillagerSkills.MASTERY:
				target += 4.0
		v.prestige = lerpf(v.prestige, maxf(v.prestige, target), 0.05) if v.prestige < target else lerpf(v.prestige, target, 0.01)


func _on_leader_lost(id: int) -> void:
	var name := society.ctx.social.name_of(id)
	if government in [&"chief", &"hereditary"]:
		# Lineage tradition: an adult child takes over.
		if society.culture.has_tradition(&"lineage"):
			for cid in society.demographics.children_of(id):
				var c := _villager(cid)
				if c != null and c.is_adult():
					_set_government(&"hereditary", [cid], "%s succeeded their parent %s as chief." % [c.villager_name, name])
					return
		_set_government(&"none", [], "With %s gone, the tribe has no chief." % name)
	elif government == &"informal":
		_set_government(&"none", [], "%s, whom many looked up to, is gone. The tribe feels uncertain." % name)


func _update_government() -> void:
	var tribe := society.ctx.tribe
	var pop := tribe.population()
	var adults := _adults()
	var ranked: Array = tribe.villagers.filter(func(v): return v.is_adult())
	ranked.sort_custom(func(a, b): return influence(a) > influence(b))
	if ranked.is_empty():
		return
	# Council: needs a meeting place, enough people and a consensus-minded culture.
	if government != &"council" and pop >= 16 and _has(&"longhouse") and society.culture.norm(&"consensus") >= 0.55:
		var members: Array[int] = []
		for v in ranked.slice(0, mini(5, maxi(3, adults / 4))):
			members.append(v.villager_id)
		_set_government(&"council", members, "The tribe formed a council of %s to decide together." % _names(members))
		return
	if government == &"council":
		_refresh_council(ranked)
		return
	# Elections and challenges
	var candidates: Array[Villager] = []
	for v in ranked:
		if wants_to_lead(v):
			candidates.append(v)
	var crisis := tribe.stockpile.get_amount(ResourceType.FOOD) < pop * 3
	if government in [&"none", &"informal"] and (pop >= 12 or crisis):
		for c in candidates:
			if endorsers(c.villager_id) * 2 > adults:
				_set_government(&"chief", [c.villager_id], "%s was chosen as chief by the tribe." % c.villager_name)
				society.culture.shift(&"hierarchy", 0.05, "the tribe chose a chief")
				return
	if government in [&"chief", &"hereditary"]:
		var chief := _villager(primary_leader())
		if chief == null:
			return
		var appr := approval(chief)
		for c in candidates:
			if c == chief:
				continue
			# A challenger with more backing than the chief takes over.
			if (appr < 0.0 or crisis) and endorsers(c.villager_id) > endorsers(chief.villager_id) and endorsers(c.villager_id) * 3 > adults:
				society.ctx.social.remember(chief, &"lost_leadership", -1, -1, -1, "chief")
				_set_government(&"chief", [c.villager_id], "%s challenged %s and became chief." % [c.villager_name, chief.villager_name])
				society.culture.shift(&"hierarchy", -0.04, "a chief was overthrown")
				return
		return
	# Informal leadership: one person clearly stands out.
	if ranked.size() >= 2:
		var top: Villager = ranked[0]
		if influence(top) >= influence(ranked[1]) * 1.35 and top.prestige >= 25.0:
			if government != &"informal" or primary_leader() != top.villager_id:
				_set_government(&"informal", [top.villager_id], "%s has become the person everyone turns to." % top.villager_name)
		elif government == &"informal" and influence(top) < influence(ranked[1]) * 1.1:
			_set_government(&"none", [], "No one stands above the rest any more.")


func _refresh_council(ranked: Array) -> void:
	# Members who lost standing are replaced by the most influential others.
	var size := leaders.size()
	var wanted: Array[int] = []
	for v in ranked.slice(0, size):
		wanted.append(v.villager_id)
	for id in leaders.duplicate():
		if not wanted.has(id) and ranked.size() > size:
			var out_v := _villager(id)
			if out_v != null and influence(out_v) < influence(_villager(wanted[size - 1])) * 0.8:
				leaders.erase(id)
				for w in wanted:
					if not leaders.has(w):
						leaders.append(w)
						society.history.add(&"leadership", "%s replaced %s on the council." % [society.ctx.social.name_of(w), out_v.villager_name], [w, id])
						society.ctx.social.remember(out_v, &"lost_leadership", -1, -1, -1, "council member")
						break


func _has(def_id: StringName) -> bool:
	for b in society.ctx.tribe.buildings:
		if b.def.id == def_id and b.is_complete:
			return true
	return false


func _set_government(kind: StringName, who: Array[int], text: String) -> void:
	var old := leaders.duplicate()
	government = kind
	leaders = who
	since_day = SimClock.get_day()
	transitions += 1
	society.history.add(&"leadership", text, who + old)
	EventBus.notify(text, &"social")
	for id in who:
		var v := _villager(id)
		if v != null and not old.has(id):
			society.ctx.social.remember(v, &"became_leader", -1, -1, -1, title())
			add_prestige(v, 10.0)


# --------------------------------------------------------------------------
# Disputes and mediation
# --------------------------------------------------------------------------

func record_dispute(a: int, b: int, reason: String) -> void:
	disputes.append({"a": a, "b": b, "reason": reason, "day": SimClock.get_day()})
	if disputes.size() > 12:
		disputes.pop_front()


## A leader (or respected figure) steps in to settle a recent dispute.
func _assign_mediation() -> void:
	if disputes.is_empty():
		return
	var mediator := _villager(primary_leader())
	if mediator == null:
		# Without a leader, the most respected empathetic adult may step in.
		var best_v := 0.0
		for v in society.ctx.tribe.villagers:
			var score := v.prestige * v.personality.get_trait(&"empathy")
			if v.is_adult() and score > best_v and score > 12.0:
				best_v = score
				mediator = v
	if mediator == null or mediator.current_task is TalkToTask or mediator.current_task is ConverseTask:
		return
	var d: Dictionary = disputes[0]
	if mediator.villager_id == d["a"] or mediator.villager_id == d["b"]:
		disputes.pop_front()
		return
	var party := _villager(d["a"])
	if party == null or _villager(d["b"]) == null or SimClock.get_day() - int(d["day"]) > 3:
		disputes.pop_front()
		return
	# End the current task first so its cleanup can't undo the new one.
	mediator.set_task(null)
	var task := TalkToTask.new(mediator, &"mediate", party, &"mediate")
	if task.start():
		mediator.set_task(task)
		society.pending_mediation[mediator.villager_id] = d
		disputes.pop_front()


func to_dict() -> Dictionary:
	var en := {}
	for v in endorsements:
		en[str(v)] = endorsements[v]
	return {"government": String(government), "leaders": leaders.duplicate(), "since": since_day, "endorse": en,
		"disputes": disputes.duplicate(true), "transitions": transitions, "mediations": mediations}


func load_dict(d: Dictionary) -> void:
	government = StringName(d["government"])
	leaders.clear()
	for id in d["leaders"]:
		leaders.append(int(id))
	since_day = int(d["since"])
	endorsements.clear()
	for v in d["endorse"]:
		endorsements[int(v)] = int(d["endorse"][v])
	disputes = Array(d["disputes"]).duplicate(true)
	transitions = int(d["transitions"])
	mediations = int(d["mediations"])
