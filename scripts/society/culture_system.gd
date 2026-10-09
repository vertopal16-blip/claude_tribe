class_name CultureSystem
extends RefCounted
## The tribe's shared values and traditions.
##
## Norms (0..1) shift with what actually happens - help given or refused,
## fights, leaders chosen or overthrown, deaths and ceremonies, shared
## successes - and drift with the temperament of each new generation of
## adults. When a norm is strong and the experience is there, a tradition
## takes hold; traditions change behaviour, and fade when the norm does.
## Ceremonies are real gatherings people walk to and take part in.

const CHECK_INTERVAL := 30.0
const NORMS: Array[StringName] = [&"cooperation", &"hierarchy", &"spirituality", &"industry", &"consensus", &"tradition"]

## tradition -> [norm, threshold, required counter, needed, description]
const TRADITIONS := {
	&"sharing_custom": [&"cooperation", 0.6, "help", 4, "Food is shared with anyone in need"],
	&"strict_rationing": [&"cooperation", -0.4, "refusals", 4, "Every share of food is counted and guarded"],
	&"funeral_rites": [&"spirituality", 0.55, "deaths", 2, "The dead are honoured together"],
	&"harvest_feast": [&"cooperation", 0.5, "harvests", 3, "Good harvests are celebrated with a feast"],
	&"evening_fire": [&"consensus", 0.5, "conversations", 60, "Evenings are spent talking around the fire"],
	&"lineage": [&"hierarchy", 0.65, "chiefs", 1, "Leadership passes from parent to child"],
	&"peacekeeping": [&"cooperation", 0.55, "mediations", 2, "Quarrels are brought before the respected to settle"],
}

var society: SocietySystem
var norms: Dictionary = {}
var traditions: Dictionary = {}  # tradition -> day adopted
var counters: Dictionary = {}
## Active ceremonies: {"kind", "name", "pos", "until", "attendees": [ids]}
var ceremonies: Array = []
var _timer := 0.0


func _init(s: SocietySystem) -> void:
	society = s
	for n in NORMS:
		norms[n] = clampf(0.5 + s.rng.randf_range(-0.08, 0.08), 0.0, 1.0)


func norm(n: StringName) -> float:
	return float(norms.get(n, 0.5))


func has_tradition(t: StringName) -> bool:
	return traditions.has(t)


func shift(n: StringName, delta: float, _why: String = "") -> void:
	norms[n] = clampf(norm(n) + delta, 0.0, 1.0)


func count(key: String, amount: int = 1) -> void:
	counters[key] = int(counters.get(key, 0)) + amount


# Effects other systems ask about -------------------------------------------

func sharing_bonus() -> float:
	return (0.2 if has_tradition(&"sharing_custom") else 0.0) - (0.15 if has_tradition(&"strict_rationing") else 0.0)


func peace_norm() -> float:
	return norm(&"cooperation") + (0.3 if has_tradition(&"peacekeeping") else 0.0)


func evening_bonus() -> float:
	return 0.15 if has_tradition(&"evening_fire") else 0.0


## Under strict rationing nobody takes more than this from the store at once.
func ration_limit() -> int:
	return 2 if has_tradition(&"strict_rationing") else 99


# Events --------------------------------------------------------------------

func on_social_event(kind: StringName) -> void:
	match kind:
		&"helped":
			count("help")
			shift(&"cooperation", 0.006)
		&"refused":
			count("refusals")
			shift(&"cooperation", -0.008)
		&"fought":
			shift(&"cooperation", -0.01)
			shift(&"consensus", -0.006)
		&"reconciled", &"mediated":
			shift(&"consensus", 0.006)
		&"ceremony":
			shift(&"spirituality", 0.004)
		&"chatted":
			count("conversations")


func on_death(v: Villager) -> void:
	count("deaths")
	shift(&"spirituality", 0.03)
	if has_tradition(&"funeral_rites"):
		var place := _ceremony_place()
		start_ceremony(&"funeral", "funeral of %s" % v.villager_name, place, 45.0)


func on_harvest() -> void:
	count("harvests")
	if has_tradition(&"harvest_feast") and int(counters.get("harvests", 0)) % 4 == 0:
		var food := society.ctx.tribe.population()
		if society.ctx.tribe.stockpile.get_amount(ResourceType.FOOD) > food * 6:
			society.ctx.tribe.stockpile.take(ResourceType.FOOD, food)  # the feast itself
			start_ceremony(&"feast", "harvest feast", society.ctx.tribe.campfire.global_position, 40.0)


func _ceremony_place() -> Vector3:
	for b in society.ctx.tribe.buildings:
		if b.def.id == &"shrine" and b.is_complete:
			return b.global_position
	return society.ctx.tribe.campfire.global_position


# Ceremonies ----------------------------------------------------------------

func start_ceremony(kind: StringName, name: String, pos: Vector3, seconds: float) -> void:
	var c := {"kind": String(kind), "name": name, "pos": pos, "until": SimClock.sim_time + seconds, "attendees": []}
	ceremonies.append(c)
	society.history.add(&"culture", "The tribe gathers for the %s." % name, [])
	for v in society.ctx.tribe.villagers:
		if v.work_capacity() >= 0.0:
			v.brain.suggest(&"ceremony", 0.55 + 0.3 * norm(&"spirituality"), seconds, "Attending the %s" % name)


func is_active(c: Dictionary) -> bool:
	return ceremonies.has(c) and SimClock.sim_time < float(c["until"])


func active_ceremony() -> Dictionary:
	for c in ceremonies:
		if SimClock.sim_time < float(c["until"]):
			return c
	return {}


func attend(c: Dictionary, v: Villager) -> void:
	if not c["attendees"].has(v.villager_id):
		c["attendees"].append(v.villager_id)


func _close_ceremonies() -> void:
	var social := society.ctx.social
	for c in ceremonies.duplicate():
		if SimClock.sim_time < float(c["until"]):
			continue
		ceremonies.erase(c)
		var who: Array = c["attendees"]
		for id in who:
			var v := social.get_villager(id)
			if v == null:
				continue
			social.remember(v, &"feast" if c["kind"] == "feast" else &"ceremony", -1, -1, -1, c["name"])
			for other in who:
				if other != id:
					social.graph.adjust_opinion(id, other, 0.03, 0.01)
		if who.size() >= 3:
			society.history.add(&"culture", "%d people took part in the %s." % [who.size(), c["name"]], who)


# Drift and traditions ------------------------------------------------------

func tick(dt: float) -> void:
	_close_ceremonies()
	_timer += dt
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	_generational_drift()
	_update_traditions()


## Values slowly follow the temperament of today's adults: a new generation
## with different personalities gradually reshapes the culture.
func _generational_drift() -> void:
	var sums := {}
	var n := 0
	for v in society.ctx.tribe.villagers:
		if not v.is_adult():
			continue
		n += 1
		var p := v.personality
		sums[&"cooperation"] = sums.get(&"cooperation", 0.0) + (p.get_trait(&"generosity") + p.get_trait(&"empathy")) * 0.5
		sums[&"hierarchy"] = sums.get(&"hierarchy", 0.0) + (p.get_trait(&"status_desire") + p.get_trait(&"loyalty")) * 0.5
		sums[&"industry"] = sums.get(&"industry", 0.0) + p.get_trait(&"industriousness")
		sums[&"consensus"] = sums.get(&"consensus", 0.0) + (p.get_trait(&"patience") + p.get_trait(&"sociability")) * 0.5
		sums[&"tradition"] = sums.get(&"tradition", 0.0) + (1.0 - p.get_trait(&"curiosity") * 0.5 - p.get_trait(&"creativity") * 0.5)
	if n == 0:
		return
	for k in sums:
		norms[k] = lerpf(norm(k), sums[k] / n, 0.01)
	if has_tradition(&"lineage") == false and society.politics.government in [&"chief", &"hereditary"]:
		counters["chiefs"] = 1


func _update_traditions() -> void:
	for t in TRADITIONS:
		var rule: Array = TRADITIONS[t]
		var value := norm(rule[0])
		var threshold: float = rule[1]
		var strong := value >= threshold if threshold > 0.0 else value <= -threshold
		var lapsed := value < threshold - 0.15 if threshold > 0.0 else value > -threshold + 0.15
		if not has_tradition(t) and strong and int(counters.get(rule[2], 0)) >= int(rule[3]):
			traditions[t] = SimClock.get_day()
			society.history.add(&"culture", "A new tradition takes hold: %s." % String(rule[4]).to_lower(), [])
			EventBus.notify("New tradition: %s" % rule[4], &"social")
		elif has_tradition(t) and lapsed:
			traditions.erase(t)
			society.history.add(&"culture", "The old custom fades: %s no longer." % String(rule[4]).to_lower(), [])


func describe() -> String:
	var parts: PackedStringArray = []
	for n in NORMS:
		parts.append("%s %d%%" % [String(n).capitalize(), int(norm(n) * 100.0)])
	return "  ·  ".join(parts)


func tradition_names() -> PackedStringArray:
	var out: PackedStringArray = []
	for t in traditions:
		out.append(TRADITIONS[t][4])
	return out


func to_dict() -> Dictionary:
	var n := {}
	for k in norms:
		n[String(k)] = norms[k]
	var tr := {}
	for t in traditions:
		tr[String(t)] = traditions[t]
	return {"norms": n, "traditions": tr, "counters": counters.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d["norms"]:
		norms[StringName(k)] = float(d["norms"][k])
	traditions.clear()
	for t in d["traditions"]:
		traditions[StringName(t)] = int(d["traditions"][t])
	counters = Dictionary(d["counters"]).duplicate()
