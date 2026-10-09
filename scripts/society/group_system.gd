class_name GroupSystem
extends RefCounted
## Social groups that form on their own inside the one tribe.
##
##   circle   - friends who are friends with each other
##   family   - extended families (kin)
##   crew     - people sharing a profession; becomes a guild once the tribe is
##              big enough, the trade established and a master emerges
##   faction  - backers of a leader or challenger
##   keepers  - those devoted to the shrine and its ceremonies
##
## Groups keep their identity while their membership changes, and they matter:
## members grow closer, seek each other's company, back each other's
## proposals, guilds train apprentices and work better, and groups whose
## members resent each other drift into open rivalry.

const CHECK_INTERVAL := 60.0
const GUILD_MIN_MEMBERS := 4
const GUILD_MIN_POPULATION := 16

var society: SocietySystem
## id -> {"id", "kind", "name", "members": [ids], "founded", "leader": id, "focus"}
var groups: Dictionary = {}
var next_id := 1
## Vector2i(group a, group b) -> true when rivals.
var rivalries: Dictionary = {}
var _timer := 0.0
var _membership: Dictionary = {}  # villager id -> [group ids]


func _init(s: SocietySystem) -> void:
	society = s


func groups_of(villager_id: int) -> Array:
	var out := []
	for gid in _membership.get(villager_id, []):
		if groups.has(gid):
			out.append(groups[gid])
	return out


## +1 when two villagers share a group, -1 when their groups are rivals.
func alignment(a: int, b: int) -> float:
	var ga: Array = _membership.get(a, [])
	var gb: Array = _membership.get(b, [])
	for g in ga:
		if gb.has(g):
			return 1.0
	for g in ga:
		for h in gb:
			if rivalries.has(Vector2i(mini(g, h), maxi(g, h))):
				return -1.0
	return 0.0


## Guild members push for buildings that serve their trade.
func guild_interest(v: Villager, building_type: StringName) -> float:
	for g in groups_of(v.villager_id):
		if g["kind"] == "guild":
			if (g["focus"] == "Farmer" and building_type == &"farm") or (g["focus"] == "Toolmaker" and building_type == &"workshop") \
					or (g["focus"] == "Builder" and building_type == &"longhouse"):
				return 1.0
	return 0.0


## Guild members work a little better (shared methods, standards).
func guild_bonus(v: Villager) -> float:
	for g in groups_of(v.villager_id):
		if g["kind"] == "guild":
			return 1.1
	return 1.0


func tick(dt: float) -> void:
	_timer += dt
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	_recompute()
	_apply_effects()


func _recompute() -> void:
	var social := society.ctx.social
	var villagers := society.ctx.tribe.villagers
	var found := []  # [kind, members, focus, leader]
	# Friend circles and families: connected components over tagged bonds.
	for kind in ["circle", "family"]:
		var tag: StringName = &"friend" if kind == "circle" else &"kin"
		var seen := {}
		for v in villagers:
			if seen.has(v.villager_id):
				continue
			var comp := []
			var stack := [v.villager_id]
			while not stack.is_empty():
				var id: int = stack.pop_back()
				if seen.has(id) or not social.is_alive(id):
					continue
				seen[id] = true
				comp.append(id)
				for o in social.graph.with_tag(id, tag):
					if not seen.has(o):
						stack.append(o)
				if kind == "circle":
					for o in social.graph.with_tag(id, &"close_friend"):
						if not seen.has(o):
							stack.append(o)
			if comp.size() >= 3:
				found.append([kind, comp, "", _most_influential(comp)])
	# Professional crews / guilds
	var by_prof := {}
	for v in villagers:
		if v.profession != &"":
			if not by_prof.has(v.profession):
				by_prof[v.profession] = []
			by_prof[v.profession].append(v.villager_id)
	for prof in by_prof:
		var members: Array = by_prof[prof]
		if members.size() < 3:
			continue
		var master := _best_at(members, ProfessionSystem.skill_of(prof))
		var guild: bool = members.size() >= GUILD_MIN_MEMBERS and society.ctx.tribe.population() >= GUILD_MIN_POPULATION \
				and society.ctx.social.get_villager(master).skills.get_level(ProfessionSystem.skill_of(prof)) >= VillagerSkills.MASTERY
		found.append(["guild" if guild else "crew", members, String(prof), master])
	# Political factions
	var backers := {}
	for voter in society.politics.endorsements:
		var c: int = society.politics.endorsements[voter]
		if not backers.has(c):
			backers[c] = [c]
		backers[c].append(voter)
	for c in backers:
		if backers[c].size() >= 3 and social.is_alive(c):
			found.append(["faction", backers[c], "", c])
	# Keepers of the shrine
	var devout := []
	for v in villagers:
		var n := 0
		for r in v.memory.long + v.memory.short:
			if r.kind == &"ceremony":
				n += r.count
		if n >= 2:
			devout.append(v.villager_id)
	if devout.size() >= 3:
		found.append(["keepers", devout, "", _most_influential(devout)])
	_match_and_update(found)


func _most_influential(ids: Array) -> int:
	var best := -1
	var best_v := -INF
	for id in ids:
		var v := society.ctx.social.get_villager(id)
		if v != null and society.politics.influence(v) > best_v:
			best_v = society.politics.influence(v)
			best = id
	return best


func _best_at(ids: Array, skill: StringName) -> int:
	var best := -1
	var best_v := -1.0
	for id in ids:
		var v := society.ctx.social.get_villager(id)
		if v != null and v.skills.get_level(skill) > best_v:
			best_v = v.skills.get_level(skill)
			best = id
	return best


## Keeps group identities stable: a new grouping that overlaps an old one
## (same kind, half the members) is the same group with new members.
func _match_and_update(found: Array) -> void:
	var social := society.ctx.social
	var kept := {}
	for f in found:
		var kind: String = f[0]
		var members: Array = f[1]
		var match_id := -1
		for gid in groups:
			var g: Dictionary = groups[gid]
			var same_kind: bool = g["kind"] == kind or (g["kind"] in ["crew", "guild"] and kind in ["crew", "guild"] and g["focus"] == f[2])
			if not same_kind or kept.has(gid):
				continue
			var overlap := 0
			for m in members:
				if g["members"].has(m):
					overlap += 1
			if overlap * 2 >= mini(members.size(), g["members"].size()):
				match_id = gid
				break
		if match_id < 0:
			match_id = next_id
			next_id += 1
			var g := {"id": match_id, "kind": kind, "members": [], "founded": SimClock.get_day(), "leader": f[3], "focus": f[2]}
			g["name"] = _name_for(kind, f[2], f[3])
			groups[match_id] = g
			society.history.add(&"group", "A new %s formed: %s." % [_kind_label(kind), g["name"]], members)
		var group: Dictionary = groups[match_id]
		if group["kind"] == "crew" and kind == "guild":
			group["kind"] = "guild"
			group["name"] = _name_for("guild", f[2], f[3])
			society.history.add(&"group", "The %ss organised themselves into the %s, led by master %s." % [
					String(f[2]).to_lower(), group["name"], social.name_of(f[3])], members)
		for m in members:
			if not group["members"].has(m):
				var v := social.get_villager(m)
				if v != null:
					social.remember(v, &"joined_group", -1, -1, -1, group["name"])
		group["members"] = members.duplicate()
		group["leader"] = f[3]
		kept[match_id] = true
	for gid in groups.keys():
		if not kept.has(gid):
			society.history.add(&"group", "%s drifted apart." % groups[gid]["name"], groups[gid]["members"])
			groups.erase(gid)
	_membership.clear()
	for gid in groups:
		for m in groups[gid]["members"]:
			if not _membership.has(m):
				_membership[m] = []
			_membership[m].append(gid)


func _name_for(kind: String, focus: String, leader: int) -> String:
	var who := society.ctx.social.name_of(leader)
	match kind:
		"circle": return "%s's circle" % who
		"family": return "the family of %s" % who
		"crew": return "the %ss" % focus.to_lower()
		"guild": return "the %ss' Guild" % focus
		"faction": return "%s's faction" % who
		"keepers": return "the Keepers of the Shrine"
	return "a group"


static func _kind_label(kind: String) -> String:
	return {"circle": "circle of friends", "family": "extended family", "crew": "work crew", "guild": "guild",
		"faction": "political faction", "keepers": "ceremonial group"}.get(kind, "group")


func _apply_effects() -> void:
	var social := society.ctx.social
	var g := social.graph
	for gid in groups:
		var grp: Dictionary = groups[gid]
		var members: Array = grp["members"]
		if members.size() > 12:
			continue
		# Spending time as a group brings people closer.
		for a in members:
			for b in members:
				if a != b:
					g.adjust_opinion(a, b, 0.01, 0.004)
		# Guild masters train the members (apprenticeship).
		if grp["kind"] == "guild":
			var master := social.get_villager(grp["leader"])
			var skill := ProfessionSystem.skill_of(StringName(grp["focus"]))
			if master != null and skill != &"":
				for m in members:
					var v := social.get_villager(m)
					if v != null and v != master:
						v.skills.learn_from(skill, master.skills.get_level(skill), 0.015, v.personality)
	_update_rivalries()


func _update_rivalries() -> void:
	var g := society.ctx.social.graph
	var ids := groups.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = groups[ids[i]]
			var b: Dictionary = groups[ids[j]]
			var total := 0.0
			var n := 0
			for x in a["members"]:
				for y in b["members"]:
					if x != y and not b["members"].has(x):
						total += g.resentment(x, y) + maxf(0.0, -g.affinity(x, y)) * 0.5
						n += 1
			if n == 0:
				continue
			var key := Vector2i(mini(ids[i], ids[j]), maxi(ids[i], ids[j]))
			var hostile := total / n > 0.22
			if hostile and not rivalries.has(key):
				rivalries[key] = true
				society.history.add(&"group", "A rift has opened between %s and %s." % [a["name"], b["name"]], a["members"] + b["members"])
			elif not hostile and rivalries.has(key) and total / n < 0.1:
				rivalries.erase(key)
				society.history.add(&"group", "%s and %s have made their peace." % [a["name"], b["name"]], [])


func to_dict() -> Dictionary:
	var gs := {}
	for gid in groups:
		gs[str(gid)] = groups[gid]
	var rv := []
	for k: Vector2i in rivalries:
		rv.append([k.x, k.y])
	return {"groups": gs, "next": next_id, "rivalries": rv}


func load_dict(d: Dictionary) -> void:
	groups.clear()
	for gid in d["groups"]:
		groups[int(gid)] = d["groups"][gid]
	next_id = int(d["next"])
	rivalries.clear()
	for r in d["rivalries"]:
		rivalries[Vector2i(int(r[0]), int(r[1]))] = true
	_membership.clear()
	for gid in groups:
		for m in groups[gid]["members"]:
			if not _membership.has(int(m)):
				_membership[int(m)] = []
			_membership[int(m)].append(gid)
