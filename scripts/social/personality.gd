class_name Personality
extends RefCounted
## Ten traits in [0, 1] (0.5 = average). Generated from a seed, then drift
## slowly with experience, never more than MAX_DRIFT away from the trait the
## villager was born with.

const TRAITS: Array[StringName] = [
	&"sociability", &"ambition", &"aggressiveness", &"generosity", &"curiosity",
	&"courage", &"trust", &"independence", &"industriousness", &"empathy"]

const MAX_DRIFT := 0.2

## trait -> [word when high, word when low]
const WORDS := {
	&"sociability": ["Outgoing", "Reserved"],
	&"ambition": ["Ambitious", "Unambitious"],
	&"aggressiveness": ["Hot-headed", "Gentle"],
	&"generosity": ["Generous", "Selfish"],
	&"curiosity": ["Curious", "Incurious"],
	&"courage": ["Brave", "Timid"],
	&"trust": ["Trusting", "Suspicious"],
	&"independence": ["Independent", "Communal"],
	&"industriousness": ["Hard-working", "Lazy"],
	&"empathy": ["Caring", "Cold"],
}

var base: Dictionary = {}
var values: Dictionary = {}


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
	for t in [&"sociability", &"aggressiveness", &"curiosity", &"industriousness", &"empathy"]:
		diff += absf(get_trait(t) - other.get_trait(t))
	return clampf(1.0 - diff / 5.0 * 2.2, 0.0, 1.0)


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
