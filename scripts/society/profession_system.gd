class_name ProfessionSystem
extends RefCounted
## Occupations emerge from what people actually do: someone who spends most
## of their recent work on one skill and has become competent at it takes up
## the matching profession. A profession makes them prefer that work (see
## ProfessionModifier) and gives them an identity others can group around.
## The first person in a profession creates it in the tribe's history.

const CHECK_INTERVAL := 60.0
const MIN_LEVEL := 28.0
const MIN_SHARE := 0.3
## How long someone must neglect their trade before losing the title.
const LAPSE_SHARE := 0.12
## People keep a trade at least this many days before changing or dropping it.
const MIN_TENURE_DAYS := 4

const TITLES := {
	&"foraging": &"Forager", &"woodcutting": &"Woodcutter", &"stonework": &"Stoneworker",
	&"building": &"Builder", &"farming": &"Farmer", &"fishing": &"Fisher",
	&"toolmaking": &"Toolmaker", &"healing": &"Healer",
}

var society: SocietySystem
var known_professions: Dictionary = {}  # title -> day first appeared
var since: Dictionary = {}  # villager id -> day they took up their trade
var _timer := 0.0


func _init(s: SocietySystem) -> void:
	society = s


static func skill_of(title: StringName) -> StringName:
	for k in TITLES:
		if TITLES[k] == title:
			return k
	return &""


func tick(dt: float) -> void:
	_timer += dt
	if _timer < CHECK_INTERVAL:
		return
	_timer -= CHECK_INTERVAL
	var day_length := society.ctx.config.day_length_seconds
	for v in society.ctx.tribe.villagers:
		v.skills.decay(day_length, CHECK_INTERVAL)
		_evaluate(v)


func _evaluate(v: Villager) -> void:
	if not v.is_adult() and v.life_stage() != &"youth":
		return
	var current := skill_of(v.profession)
	if current != &"" and SimClock.get_day() - int(since.get(v.villager_id, -100)) < MIN_TENURE_DAYS:
		return
	if current != &"" and _has_recent_work(v) and v.skills.recent_share(current) < LAPSE_SHARE:
		society.history.add(&"profession", "%s gave up being a %s." % [v.villager_name, String(v.profession).to_lower()],
				[v.villager_id])
		v.profession = &""
		current = &""
	var best: StringName = &""
	var best_score := 0.0
	for k in TITLES:
		var lvl := v.skills.get_level(k)
		var share := v.skills.recent_share(k)
		if lvl >= MIN_LEVEL and share >= MIN_SHARE and lvl * share > best_score:
			best_score = lvl * share
			best = k
	if best == &"" or best == current:
		return
	# Changing trade needs a clear reason: the new craft must be the better one.
	if current != &"" and v.skills.get_level(best) <= v.skills.get_level(current):
		return
	var title: StringName = TITLES[best]
	v.profession = title
	since[v.villager_id] = SimClock.get_day()
	society.ctx.social.remember(v, &"new_profession", -1, -1, -1, String(title).to_lower())
	if not known_professions.has(title):
		known_professions[title] = SimClock.get_day()
		society.history.add(&"profession", "A new profession appears: %s became the tribe's first %s." % [
				v.villager_name, String(title).to_lower()], [v.villager_id])
		EventBus.notify("New profession: %s (%s)" % [title, v.villager_name], &"build")
	else:
		society.history.add(&"profession", "%s became a %s." % [v.villager_name, String(title).to_lower()], [v.villager_id])


func _has_recent_work(v: Villager) -> bool:
	var total := 0.0
	for x in v.skills.recent.values():
		total += x
	return total > 60.0


func members(title: StringName) -> Array[Villager]:
	var out: Array[Villager] = []
	for v in society.ctx.tribe.villagers:
		if v.profession == title:
			out.append(v)
	return out


func to_dict() -> Dictionary:
	var kp := {}
	for t in known_professions:
		kp[String(t)] = known_professions[t]
	var sn := {}
	for id in since:
		sn[str(id)] = since[id]
	return {"known": kp, "since": sn}


func load_dict(d: Dictionary) -> void:
	known_professions.clear()
	for t in d["known"]:
		known_professions[StringName(t)] = int(d["known"][t])
	since.clear()
	for id in d.get("since", {}):
		since[int(id)] = int(d["since"][id])
