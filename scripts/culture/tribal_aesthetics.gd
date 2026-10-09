class_name TribalAesthetics
extends RefCounted
## How the tribe's culture becomes visible.
##
## Pigments are discovered from what the tribe actually works with (red ochre
## from stonework, charcoal from its fires, berry dyes from foraging, green
## from herbs, blue clay from the lake shore, yellow from the fields), in the
## order its history provides them. A motif emerges from the values the tribe
## holds most strongly when it first starts decorating. Art develops in
## stages that need real prerequisites:
##   1  body paint and sashes      - an established ceremonial custom + a pigment
##   2  painted homes and objects  - craft values or toolmaking, 10+ people
##   3  carving and monuments      - carpentry or a master woodcutter/stoneworker, 12+ people
## Buildings keep the style of the era they were built in, so the settlement's
## architecture records its history. New eras come from new techniques and are
## adopted - or rejected - by the tribe's builders.

const PIGMENTS := {
	"ochre": [Color(0.72, 0.28, 0.16), "red ochre ground from the stones the tribe quarries"],
	"charcoal": [Color(0.13, 0.12, 0.12), "charcoal from the fires the tribe gathers around"],
	"berry": [Color(0.52, 0.16, 0.42), "purple dye pressed from the berries the foragers gather"],
	"leaf": [Color(0.24, 0.52, 0.22), "green dye from the herbs the healers know"],
	"clay": [Color(0.27, 0.45, 0.7), "blue clay from the lake shore the fishers walk"],
	"chalk": [Color(0.93, 0.91, 0.84), "white chalk from the sacred stones"],
	"saffron": [Color(0.9, 0.7, 0.15), "yellow from the flowers at the edge of the fields"],
}

## motif -> values it expresses
const MOTIFS := {
	"spirals": [&"spirituality", &"nature"], "zigzags": [&"courage", &"strength"],
	"bands": [&"cooperation", &"equality", &"family"], "dots": [&"knowledge", &"curiosity"],
	"chevrons": [&"hierarchy", &"achievement"], "leaves": [&"nature", &"hospitality"],
	"hatching": [&"craftsmanship", &"independence"], "rings": [&"tradition", &"elders", &"loyalty"],
}

const ERA_TECHS := {
	&"carpentry": "timber-framed walls", &"toolmaking": "carved door posts", &"agriculture": "thatch from the fields",
}

## [{"name", "day", "reason"}]
var palette: Array = []
var motif := ""
var motif_reason := ""
var art_level := 0
var art_days: Dictionary = {}  # level -> day reached
## Architecture eras: [{"day", "name", "reason", "roof", "band", "posts", "motif"}]
var eras: Array = []
## Innovations proposed but not (yet) adopted: tech -> day rejected
var rejected_styles: Dictionary = {}


func has_pigment(n: String) -> bool:
	for p in palette:
		if p["name"] == n:
			return true
	return false


func color(i: int) -> Color:
	if palette.is_empty():
		return Color(0.8, 0.75, 0.6)
	return PIGMENTS[palette[i % palette.size()]["name"]][0]


func color_name(i: int) -> String:
	return "undyed" if palette.is_empty() else String(palette[i % palette.size()]["name"])


func add_pigment(n: String) -> bool:
	if has_pigment(n):
		return false
	palette.append({"name": n, "day": SimClock.get_day(), "reason": PIGMENTS[n][1]})
	return true


## Pick the motif that best expresses the tribe's values right now.
func choose_motif(tribe_values: Dictionary) -> String:
	var best := ""
	var best_v := -INF
	for m in MOTIFS:
		var s := 0.0
		for k in MOTIFS[m]:
			s += float(tribe_values.get(k, 0.0))
		s /= MOTIFS[m].size()
		if s > best_v:
			best_v = s
			best = m
	return best


func current_era() -> Dictionary:
	return eras.back() if not eras.is_empty() else {}


func era_index() -> int:
	return eras.size() - 1


## The look of buildings built now (empty = plain, before any decoration).
func style() -> Dictionary:
	if art_level < 2 or eras.is_empty():
		return {}
	return current_era()


func new_era(name: String, reason: String, posts: bool) -> Dictionary:
	var prev := current_era()
	var e := {"day": SimClock.get_day(), "name": name, "reason": reason,
		"band": palette[0]["name"] if not palette.is_empty() else "",
		"accent": palette[mini(1, palette.size() - 1)]["name"] if not palette.is_empty() else "",
		"posts": posts or bool(prev.get("posts", false)), "motif": motif,
		"timber": name.contains("timber") or bool(prev.get("timber", false))}
	eras.append(e)
	return e


func to_dict() -> Dictionary:
	return {"palette": palette.duplicate(true), "motif": motif, "motif_reason": motif_reason, "art": art_level,
		"art_days": art_days.duplicate(), "eras": eras.duplicate(true), "rejected": rejected_styles.duplicate()}


func load_dict(d: Dictionary) -> void:
	palette = Array(d["palette"]).duplicate(true)
	motif = d["motif"]
	motif_reason = d["motif_reason"]
	art_level = int(d["art"])
	art_days.clear()
	for k in d["art_days"]:
		art_days[int(k)] = int(d["art_days"][k])
	eras = Array(d["eras"]).duplicate(true)
	rejected_styles.clear()
	for k in d["rejected"]:
		rejected_styles[StringName(k)] = int(d["rejected"][k])
