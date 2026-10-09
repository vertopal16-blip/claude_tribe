class_name CulturalValues
extends RefCounted
## What one person believes matters (-1 .. 1 per value).
##
## Values are not personality: two equally generous people can hold opposite
## beliefs about how food should be shared. Newborns start with none. Values
## are formed by experience (interpreted through temperament and existing
## beliefs), by the people who raise and teach someone, and by the customs
## they take part in. The tribe's culture is the influence-weighted sum of
## its members' values, so it only exists once people come to share beliefs.

const VALUES: Array[StringName] = [
	&"cooperation", &"independence", &"elders", &"courage", &"generosity", &"loyalty", &"family",
	&"achievement", &"equality", &"hierarchy", &"hospitality", &"tradition", &"curiosity",
	&"spirituality", &"nature", &"strength", &"craftsmanship", &"knowledge"]

const LABELS := {
	&"cooperation": "Cooperation", &"independence": "Independence", &"elders": "Respect for elders",
	&"courage": "Courage", &"generosity": "Generosity", &"loyalty": "Loyalty", &"family": "Family",
	&"achievement": "Achievement", &"equality": "Equality", &"hierarchy": "Hierarchy",
	&"hospitality": "Hospitality", &"tradition": "Tradition", &"curiosity": "Curiosity",
	&"spirituality": "Spirituality", &"nature": "Respect for nature", &"strength": "Strength",
	&"craftsmanship": "Craftsmanship", &"knowledge": "Knowledge",
}

## Beliefs that pull against each other: holding one more firmly weakens the other a little.
const TENSIONS := {
	&"cooperation": &"independence", &"independence": &"cooperation",
	&"equality": &"hierarchy", &"hierarchy": &"equality",
	&"tradition": &"curiosity", &"curiosity": &"tradition",
}

var values: Dictionary = {}


func _init() -> void:
	for k in VALUES:
		values[k] = 0.0


func get_value(k: StringName) -> float:
	return float(values.get(k, 0.0))


## Belief changes are slower the more firmly something is already held.
func shift(k: StringName, delta: float) -> void:
	if not values.has(k) or delta == 0.0:
		return
	var cur: float = values[k]
	var resist := 1.0 - absf(cur) * 0.7 if signf(delta) == signf(cur) else 1.0
	values[k] = clampf(cur + delta * resist, -1.0, 1.0)
	if TENSIONS.has(k) and delta > 0.0:
		var o: StringName = TENSIONS[k]
		values[o] = clampf(float(values[o]) - delta * 0.3, -1.0, 1.0)


## Move part of the way towards someone else's beliefs (being raised or taught).
func learn_toward(model: Dictionary, rate: float) -> void:
	for k in VALUES:
		values[k] = clampf(float(values[k]) + (float(model.get(k, 0.0)) - float(values[k])) * rate, -1.0, 1.0)


## How well a set of weighted values fits these beliefs (-1 .. 1).
func alignment(weights: Dictionary) -> float:
	var total := 0.0
	var wsum := 0.0
	for k in weights:
		total += get_value(k) * float(weights[k])
		wsum += absf(float(weights[k]))
	return 0.0 if wsum <= 0.0 else total / wsum


## 0..1: how alike two people's beliefs are (only values someone holds count).
func similarity(o: CulturalValues) -> float:
	var diff := 0.0
	var weight := 0.0
	for k in VALUES:
		var a := get_value(k)
		var b := o.get_value(k)
		var w := maxf(absf(a), absf(b))
		diff += absf(a - b) * w
		weight += w
	return 0.5 if weight < 0.05 else 1.0 - clampf(diff / (2.0 * weight), 0.0, 1.0)


## How much someone believes in anything at all (0..1).
func conviction() -> float:
	var s := 0.0
	for k in VALUES:
		s += absf(get_value(k))
	return s / VALUES.size()


## [[value, strength], ...] strongest first.
func strongest(n: int = 3, positive_only: bool = true) -> Array:
	var list := []
	for k in VALUES:
		var x := get_value(k)
		if positive_only and x <= 0.0:
			continue
		list.append([k, x])
	list.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
	return list.slice(0, n)


## Personal leanings the founders bring with them: faint, individual, and
## derived from their temperament - not a shared culture.
static func from_personality(p: Personality) -> CulturalValues:
	var c := CulturalValues.new()
	var t := func(k: StringName) -> float: return p.get_trait(k) - 0.5
	c.values[&"generosity"] = t.call(&"generosity") * 0.25
	c.values[&"cooperation"] = (t.call(&"empathy") - t.call(&"independence")) * 0.15
	c.values[&"independence"] = t.call(&"independence") * 0.2
	c.values[&"courage"] = t.call(&"courage") * 0.2
	c.values[&"curiosity"] = t.call(&"curiosity") * 0.2
	c.values[&"achievement"] = t.call(&"ambition") * 0.2
	c.values[&"hierarchy"] = t.call(&"status_desire") * 0.15
	c.values[&"loyalty"] = t.call(&"loyalty") * 0.2
	c.values[&"craftsmanship"] = t.call(&"industriousness") * 0.12
	c.values[&"strength"] = t.call(&"aggressiveness") * 0.15
	return c


func to_array() -> Array:
	var out := []
	for k in VALUES:
		out.append(values[k])
	return out


static func from_array(a: Array) -> CulturalValues:
	var c := CulturalValues.new()
	for i in mini(a.size(), VALUES.size()):
		c.values[VALUES[i]] = float(a[i])
	return c
