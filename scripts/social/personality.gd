class_name Personality
extends RefCounted
## A villager's temperament: 19 traits in [0, 1] (0.5 = average).
## Generated from a seed (or inherited from parents with variation), then
## drifting slowly with experience, never more than MAX_DRIFT away from the
## trait the villager was born with.

const TRAITS: Array[StringName] = [
	&"sociability", &"ambition", &"empathy", &"aggressiveness", &"curiosity",
	&"courage", &"honesty", &"generosity", &"jealousy", &"patience",
	&"independence", &"loyalty", &"competitiveness", &"risk_tolerance", &"creativity",
	&"industriousness", &"trust", &"status_desire", &"social_need"]

const MAX_DRIFT := 0.2

## trait -> [word when high, word when low]
const WORDS := {
	&"sociability": ["Outgoing", "Reserved"],
	&"ambition": ["Ambitious", "Unambitious"],
	&"empathy": ["Caring", "Cold"],
	&"aggressiveness": ["Hot-headed", "Gentle"],
	&"curiosity": ["Curious", "Incurious"],
	&"courage": ["Brave", "Timid"],
	&"honesty": ["Honest", "Deceitful"],
	&"generosity": ["Generous", "Selfish"],
	&"jealousy": ["Jealous", "Secure"],
	&"patience": ["Patient", "Impulsive"],
	&"independence": ["Independent", "Communal"],
	&"loyalty": ["Loyal", "Fickle"],
	&"competitiveness": ["Competitive", "Easygoing"],
	&"risk_tolerance": ["Daring", "Cautious"],
	&"creativity": ["Inventive", "Conventional"],
	&"industriousness": ["Hard-working", "Lazy"],
	&"trust": ["Trusting", "Suspicious"],
	&"status_desire": ["Proud", "Humble"],
	&"social_need": ["Needs company", "Self-sufficient"],
}

var base: Dictionary = {}
var values: Dictionary = {}


## A child's temperament: mostly a blend of the parents, partly its own.
static func inherit(a: Personality, b: Personality, rng: RandomNumberGenerator) -> Personality:
	var p := Personality.new()
	for t in TRAITS:
		var blend: float = (a.base[t] + b.base[t]) * 0.5
		var v := clampf(lerpf(blend, rng.randfn(0.5, 0.2), 0.45), 0.03, 0.97)
		p.base[t] = v
		p.values[t] = v
	return p


static func generate(rng: RandomNumberGenerator) -> Personality:
	var p := Personality.new()
	for t in TRAITS:
		var v := clampf(rng.randfn(0.5, 0.2), 0.03, 0.97)
		p.base[t] = v
		p.values[t] = v
	return p


func get_trait(t: StringName) -> float:
	return float(values.get(t, 0.5))


## Experience nudges a trait; bounded around the inborn value.
func drift(t: StringName, delta: float) -> void:
	if not values.has(t):
		return
	var b: float = base[t]
	values[t] = clampf(values[t] + delta, maxf(0.0, b - MAX_DRIFT), minf(1.0, b + MAX_DRIFT))


## Most distinctive traits as words, strongest first.
func descriptors(max_count: int = 3) -> PackedStringArray:
	var ranked := TRAITS.duplicate()
	ranked.sort_custom(func(a, b): return absf(get_trait(a) - 0.5) > absf(get_trait(b) - 0.5))
	var out: PackedStringArray = []
	for t in ranked:
		var v := get_trait(t)
		if absf(v - 0.5) < 0.15 or out.size() >= max_count:
			break
		out.append(WORDS[t][0] if v > 0.5 else WORDS[t][1])
	if out.is_empty():
		out.append("Even-tempered")
	return out


## How well two temperaments get along, 0 (clash) .. 1 (kindred spirits).
## Based on the traits that matter most in everyday company.
func compatibility(other: Personality) -> float:
	var diff := 0.0
	var keys := [&"sociability", &"aggressiveness", &"curiosity", &"industriousness", &"empathy", &"patience", &"honesty"]
	for t in keys:
		diff += absf(get_trait(t) - other.get_trait(t))
	return clampf(1.0 - diff / keys.size() * 2.2, 0.0, 1.0)


func to_dict() -> Dictionary:
	var b := {}
	var v := {}
	for t in TRAITS:
		b[String(t)] = base[t]
		v[String(t)] = values[t]
	return {"base": b, "values": v}


static func from_dict(d: Dictionary) -> Personality:
	var p := Personality.new()
	for t in TRAITS:
		p.base[t] = float(d["base"].get(String(t), 0.5))
		p.values[t] = float(d["values"].get(String(t), 0.5))
	return p
