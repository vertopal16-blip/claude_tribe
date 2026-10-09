class_name LoreBook
extends RefCounted
## The tribe's collective memory: the events people tell each other about.
##
## Each story is anchored in something that really happened (with the names,
## day and numbers at the time). Only the people who lived through it know
## it at first; everyone else learns it by being told - and every retelling
## may simplify it: the dead lose their names and become "the founder" or
## "the old chief", numbers turn into "a great harvest", and eventually it
## becomes a tale of "the ancestors". How someone feels about a story
## depends on their own beliefs (a first chief is a proud memory to those who
## value hierarchy and a warning to those who value equality). A story nobody
## living remembers is lost.

const MAX_DISTORTION := 3

## kind -> [tone (-1 tragic .. 1 proud), title concepts, [level 0, level 1, level 2, level 3]]
## Placeholders: {a} {b} main actors, {n} a number, {x} extra detail, {day}.
const KINDS := {
	"first_harvest": [0.8, [&"first", &"harvest"], [
		"On day {day}, {a} brought in the first harvest from our fields: {n} food.",
		"{a} brought in our first harvest, enough to feed everyone.",
		"{a} taught the earth to feed the people, and there was plenty.",
		"In the first days the ancestors were given the fields, and hunger ended."]],
	"first_building": [0.7, [&"first", &"home"], [
		"On day {day}, the tribe finished its first {x}, the plan of {a}.",
		"{a} led the tribe in raising the first {x}.",
		"{a} and the people raised a great {x} in a single day.",
		"The ancestors raised the first {x} with their bare hands."]],
	"first_leader": [0.4, [&"first", &"chief"], [
		"On day {day}, {a} was chosen as the tribe's first {x}.",
		"{a} became the first to lead the tribe.",
		"{a} was the first chief, and the people followed.",
		"In the old days the first chief was given to the people."]],
	"leader_fell": [-0.3, [&"chief", &"death"], [
		"On day {day}, {a} lost the trust of the tribe and {b} took their place.",
		"{a} was cast down by {b}.",
		"The people rose against {a}.",
		"Long ago a chief grew proud and the people cast them down."]],
	"famine": [-0.6, [&"hunger", &"memory"], [
		"Around day {day}, the stores ran empty and {n} went hungry. {x}",
		"Food ran out and many went hungry. {x}",
		"There was a great hunger, and the people nearly perished. {x}",
		"In the hungry years the ancestors survived only because {x2}."]],
	"discovery": [0.7, [&"new", &"light"], [
		"On day {day}, {a} discovered {x}.",
		"{a} found out how to {x2}.",
		"{a} the wise was the first to know {x}.",
		"The ancestors were taught {x} by the spirits."]],
	"passing": [-0.5, [&"old", &"heart"], [
		"On day {day}, {a} died at the age of {n}. {x}",
		"{a}, one of the founders, died. {x}",
		"{a} left us, and the tribe mourned for a long time.",
		"The first people passed into the earth and watch over us."]],
	"custom_founded": [0.5, [&"rite", &"first"], [
		"On day {day}, the custom of the {x} began, after {x2}.",
		"The {x} began in the days of {a}.",
		"{a} gave us the {x}.",
		"The {x} has been kept since the beginning of the people."]],
	"reconciliation": [0.6, [&"peace", &"heart"], [
		"On day {day}, {a} and {b} made peace after their quarrel.",
		"{a} and {b} were enemies, then made peace.",
		"Two enemies made peace, and the tribe was whole again.",
		"The ancestors learned that quarrels must end in peace."]],
	"first_birth": [0.9, [&"first", &"child"], [
		"On day {day}, {a} was born, the first child of the valley.",
		"{a} was the first child born in the valley.",
		"The first child of the valley was born, and everyone rejoiced.",
		"The people's first child was a gift of the land."]],
}

## kind -> short title by distortion level (0-1 exact, 2-3 mythic).
const TITLES := {
	"first_harvest": ["the first harvest of {a}", "the first harvest"],
	"first_building": ["the raising of the first {x}", "the raising of the first {x}"],
	"first_leader": ["the first chief, {a}", "the first chief"],
	"leader_fell": ["the fall of {a}", "the fall of the proud chief"],
	"famine": ["the hungry days", "the great hunger"],
	"discovery": ["{a}'s discovery of {x}", "the gift of {x}"],
	"passing": ["the passing of {a}", "the passing of the first people"],
	"custom_founded": ["the beginning of the {x}", "the beginning of the {x}"],
	"reconciliation": ["the peace between {a} and {b}", "the great peace"],
	"first_birth": ["the birth of {a}", "the first child"],
}

## id -> entry (see add)
var entries: Dictionary = {}
var next_id := 1
var forgotten := 0


func add(kind: String, actors: Array, actor_names: Array, values: Dictionary, importance: float,
		knowers: Array, details: Dictionary = {}) -> Dictionary:
	var e := {"id": next_id, "kind": kind, "day": SimClock.get_day(), "actors": actors.duplicate(),
		"names": actor_names.duplicate(), "values": values.duplicate(), "importance": importance,
		"details": details.duplicate(), "knowers": {}, "retold": 0, "word": "", "lost": false}
	entries[next_id] = e
	next_id += 1
	for v in knowers:
		e["knowers"][v.villager_id] = [0, 0.0]
	return e


func tone(e: Dictionary) -> float:
	return float(KINDS[e["kind"]][0])


## How `cv` (CulturalValues) feels about the event: its tone, coloured by
## whether the event stands for things they believe in.
func valence_for(e: Dictionary, cv: CulturalValues) -> float:
	return clampf(tone(e) * 0.4 + cv.alignment(e["values"]) * 1.2, -1.0, 1.0)


func knows(e: Dictionary, villager_id: int) -> bool:
	return e["knowers"].has(villager_id)


func distortion_of(e: Dictionary, villager_id: int) -> int:
	return int(e["knowers"].get(villager_id, [0, 0.0])[0])


func learn(e: Dictionary, villager_id: int, distortion: int, valence: float) -> void:
	e["knowers"][villager_id] = [clampi(distortion, 0, MAX_DISTORTION), valence]


func known_by(villager_id: int) -> Array:
	var out := []
	for e in entries.values():
		if not e["lost"] and e["knowers"].has(villager_id):
			out.append(e)
	return out


func living(include_lost: bool = false) -> Array:
	var out := []
	for e in entries.values():
		if include_lost or not e["lost"]:
			out.append(e)
	return out


## The story as `villager_id` would tell it.
func text_for(e: Dictionary, villager_id: int, social: SocialSystem) -> String:
	return render(e, distortion_of(e, villager_id), social)


func render(e: Dictionary, level: int, social: SocialSystem) -> String:
	var tpl: String = KINDS[e["kind"]][2][clampi(level, 0, MAX_DISTORTION)]
	var names: Array = e["names"]
	var actors: Array = e["actors"]
	var d: Dictionary = e["details"]
	var vals := {"day": str(e["day"]), "n": str(d.get("n", "")), "x": str(d.get("x", "")), "x2": str(d.get("x2", d.get("x", "")))}
	for i in 2:
		var key := "a" if i == 0 else "b"
		if i >= names.size():
			vals[key] = "someone"
			continue
		vals[key] = _actor_label(names[i], actors[i] if i < actors.size() else -1, level, social, d)
	var out := tpl.format(vals)
	return out.substr(0, 1).to_upper() + out.substr(1)


## Names fade from stories about the dead: first an epithet, then "the ancestors".
func _actor_label(name: String, id: int, level: int, social: SocialSystem, d: Dictionary) -> String:
	if level == 0 or (id >= 0 and social != null and social.is_alive(id)):
		return name
	var epithet: String = d.get("epithet", "")
	if level == 1:
		return name if epithet == "" else "%s %s" % [name, epithet]
	if level == 2:
		return "the " + epithet.trim_prefix("the ").capitalize() if epithet != "" else name
	return "the ancestors"


func title(e: Dictionary, level: int, social: SocialSystem) -> String:
	var tpl: String = TITLES[e["kind"]][0 if level < 2 else 1]
	var names: Array = e["names"]
	var actors: Array = e["actors"]
	var d: Dictionary = e["details"]
	var vals := {"x": str(d.get("x", ""))}
	for i in 2:
		var key := "a" if i == 0 else "b"
		vals[key] = _actor_label(names[i], actors[i] if i < actors.size() else -1, level, social, d) if i < names.size() else "someone"
	return tpl.format(vals)


func living_knowers(e: Dictionary, social: SocialSystem) -> int:
	var n := 0
	for id in e["knowers"]:
		if social.is_alive(id):
			n += 1
	return n


## Average feeling about an event among a set of villagers (who know it).
func group_valence(e: Dictionary, ids: Array) -> Array:
	var total := 0.0
	var n := 0
	for id in ids:
		if e["knowers"].has(id):
			total += float(e["knowers"][id][1])
			n += 1
	return [0.0 if n == 0 else total / n, n]


func to_dict() -> Dictionary:
	var es := {}
	for id in entries:
		var e: Dictionary = entries[id].duplicate(true)
		var kn := {}
		for k in e["knowers"]:
			kn[str(k)] = e["knowers"][k]
		e["knowers"] = kn
		var vals := {}
		for k in e["values"]:
			vals[String(k)] = e["values"][k]
		e["values"] = vals
		es[str(id)] = e
	return {"entries": es, "next": next_id, "forgotten": forgotten}


func load_dict(d: Dictionary) -> void:
	entries.clear()
	for id in d["entries"]:
		var e: Dictionary = Dictionary(d["entries"][id]).duplicate(true)
		var kn := {}
		for k in e["knowers"]:
			kn[int(k)] = [int(e["knowers"][k][0]), float(e["knowers"][k][1])]
		e["knowers"] = kn
		var vals := {}
		for k in e["values"]:
			vals[StringName(k)] = float(e["values"][k])
		e["values"] = vals
		entries[int(id)] = e
	next_id = int(d["next"])
	forgotten = int(d["forgotten"])
