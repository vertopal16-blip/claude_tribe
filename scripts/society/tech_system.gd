class_name TechSystem
extends RefCounted
## Discoveries and know-how.
##
## Techniques are discovered by individuals through experience: someone
## skilled in a related activity, creative and curious enough, may hit upon
## something new while working - more readily when the tribe needs it.
## Knowledge lives in people: it spreads through conversation and teaching,
## and is lost if everyone who knows it dies.

const CHECK_INTERVAL := 30.0

## tech -> {label, skill, level, trait, base daily chance}
const TECHS := {
	&"agriculture": {"label": "planting crops", "skill": &"foraging", "level": 25.0, "trait": &"creativity", "base": 0.35},
	&"fishing": {"label": "fishing", "skill": &"foraging", "level": 12.0, "trait": &"curiosity", "base": 0.5},
	&"toolmaking": {"label": "shaping tools", "skill": &"stonework", "level": 25.0, "trait": &"creativity", "base": 0.35},
	&"herbalism": {"label": "healing with herbs", "skill": &"foraging", "level": 35.0, "trait": &"empathy", "base": 0.25},
	&"carpentry": {"label": "joining timber", "skill": &"woodcutting", "level": 35.0, "trait": &"creativity", "base": 0.3},
}

var society: SocietySystem
## villager id -> {tech: true}
var known: Dictionary = {}
## tech -> {"by": id, "day": day} for the first discovery
var discovered: Dictionary = {}
var lost: Dictionary = {}
var _timer := 0.0


func _init(s: SocietySystem) -> void:
	society = s


func knows(v: Villager, tech: StringName) -> bool:
	return v != null and known.get(v.villager_id, {}).has(tech)


## Does any living villager know it?
func tribe_knows(tech: StringName) -> bool:
	for v in society.ctx.tribe.villagers:
		if knows(v, tech):
			return true
	return false


func knowers(tech: StringName) -> Array[Villager]:
	var out: Array[Villager] = []
	for v in society.ctx.tribe.villagers:
		if knows(v, tech):
			out.append(v)
	return out


func learn(v: Villager, tech: StringName, teacher: Villager = null) -> void:
	if v == null or knows(v, tech):
		return
	if not known.has(v.villager_id):
		known[v.villager_id] = {}
	known[v.villager_id][tech] = true
	if teacher != null:
		society.ctx.social.remember(v, &"learned_discovery", teacher.villager_id, -1, -1, TECHS[tech]["label"])
		if lost.has(tech):
			lost.erase(tech)


func tick(dt: float) -> void:
	_timer += dt
	if _timer < CHECK_INTERVAL:
		return
	_timer -= CHECK_INTERVAL
	var day_fraction := CHECK_INTERVAL / society.ctx.config.day_length_seconds
	var food_short := society.ctx.tribe.stockpile.get_amount(ResourceType.FOOD) < society.ctx.tribe.population() * 6
	for v in society.ctx.tribe.villagers:
		if v.work_capacity() <= 0.0:
			continue
		for tech in TECHS:
			if knows(v, tech):
				continue
			var t: Dictionary = TECHS[tech]
			var lvl := v.skills.get_level(t["skill"])
			if lvl < t["level"]:
				continue
			if tech == &"fishing" and not _near_water(v):
				continue
			var p: float = t["base"] * (lvl / 50.0) * lerpf(0.3, 1.7, v.personality.get_trait(t["trait"])) \
					* lerpf(0.6, 1.4, v.personality.get_trait(&"curiosity"))
			if food_short and tech in [&"agriculture", &"fishing"]:
				p *= 2.0  # necessity is the mother of invention
			if society.rng.randf() < DemographicsSystem._chance(p, day_fraction):
				_discover(v, tech)
	_check_lost()


func _near_water(v: Villager) -> bool:
	var t := society.ctx.terrain
	return Vector2(v.global_position.x, v.global_position.z).distance_to(t.lake_center) < t.lake_radius * 1.7


func _discover(v: Villager, tech: StringName) -> void:
	learn(v, tech)
	var label: String = TECHS[tech]["label"]
	society.ctx.social.remember(v, &"discovered", -1, -1, -1, label)
	society.politics.add_prestige(v, 8.0)
	if not discovered.has(tech) or lost.has(tech):
		var again := lost.has(tech)
		lost.erase(tech)
		discovered[tech] = {"by": v.villager_id, "day": SimClock.get_day()}
		society.history.add(&"discovery", "%s %sdiscovered %s!" % [v.villager_name, "re" if again else "", label], [v.villager_id])
		society.culture.on_discovery(v, tech, label)
		EventBus.notify("%s discovered %s!" % [v.villager_name, label], &"build")
	else:
		society.history.add(&"discovery", "%s worked out %s independently." % [v.villager_name, label], [v.villager_id])


func _check_lost() -> void:
	for tech in discovered:
		if lost.has(tech) or tribe_knows(tech):
			continue
		lost[tech] = SimClock.get_day()
		society.history.add(&"discovery", "The knowledge of %s died with its last keeper." % TECHS[tech]["label"], [])


## Something `s` knows that `l` doesn't (worth explaining), or &"".
func teachable(s: Villager, l: Villager) -> StringName:
	for tech in known.get(s.villager_id, {}):
		if not knows(l, tech):
			return tech
	return &""


func to_dict() -> Dictionary:
	var k := {}
	for id in known:
		k[str(id)] = known[id].keys().map(func(x): return String(x))
	var d := {}
	for t in discovered:
		d[String(t)] = discovered[t]
	var l := {}
	for t in lost:
		l[String(t)] = lost[t]
	return {"known": k, "discovered": d, "lost": l}


func load_dict(data: Dictionary) -> void:
	known.clear()
	for id in data["known"]:
		var techs := {}
		for t in data["known"][id]:
			techs[StringName(t)] = true
		known[int(id)] = techs
	discovered.clear()
	for t in data["discovered"]:
		discovered[StringName(t)] = data["discovered"][t]
	lost.clear()
	for t in data["lost"]:
		lost[StringName(t)] = data["lost"][t]
