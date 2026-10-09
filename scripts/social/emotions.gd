class_name Emotions
extends RefCounted
## A villager's emotional state: 18 emotions with intensity (0..1), each
## decaying at its own rate. Events add emotion scaled by personality, and
## every change keeps its cause so the state can be explained.

const LIST: Array[StringName] = [
	&"happiness", &"sadness", &"fear", &"anger", &"frustration", &"affection",
	&"loneliness", &"jealousy", &"pride", &"shame", &"gratitude", &"hope",
	&"grief", &"stress", &"trust", &"resentment", &"curiosity", &"satisfaction"]

## Days for an emotion to fall to half intensity.
const HALF_LIFE_DAYS := {
	&"happiness": 0.5, &"sadness": 1.2, &"fear": 0.35, &"anger": 0.25, &"frustration": 0.4,
	&"affection": 2.0, &"loneliness": 0.0, &"jealousy": 1.0, &"pride": 1.2, &"shame": 1.5,
	&"gratitude": 2.0, &"hope": 1.0, &"grief": 6.0, &"stress": 0.6, &"trust": 2.0,
	&"resentment": 3.0, &"curiosity": 0.5, &"satisfaction": 0.8,
}

const POSITIVE := [&"happiness", &"affection", &"pride", &"gratitude", &"hope", &"trust", &"satisfaction"]
const NEGATIVE := [&"sadness", &"fear", &"anger", &"frustration", &"jealousy", &"shame", &"grief",
	&"stress", &"resentment"]
const MAX_CAUSES := 16

var values: Dictionary = {}
## Recent reasons: [{"emotion", "amount", "why", "day"}], newest last.
var causes: Array = []


func _init() -> void:
	for e in LIST:
		values[e] = 0.0


func get_value(e: StringName) -> float:
	return float(values.get(e, 0.0))


## Personality makes some people feel some things much more strongly.
static func reactivity(e: StringName, p: Personality) -> float:
	match e:
		&"anger": return lerpf(0.5, 1.6, p.get_trait(&"aggressiveness")) * lerpf(1.3, 0.7, p.get_trait(&"patience"))
		&"fear": return lerpf(1.6, 0.5, p.get_trait(&"courage"))
		&"jealousy": return lerpf(0.2, 1.8, p.get_trait(&"jealousy"))
		&"grief", &"sadness": return lerpf(0.7, 1.3, p.get_trait(&"empathy"))
		&"gratitude", &"affection": return lerpf(0.7, 1.3, p.get_trait(&"empathy"))
		&"pride", &"shame": return lerpf(0.5, 1.5, p.get_trait(&"status_desire"))
		&"resentment": return lerpf(1.4, 0.6, p.get_trait(&"trust")) * lerpf(1.2, 0.8, p.get_trait(&"patience"))
		&"frustration", &"stress": return lerpf(1.3, 0.7, p.get_trait(&"patience"))
		&"curiosity": return lerpf(0.4, 1.6, p.get_trait(&"curiosity"))
		&"hope": return lerpf(0.8, 1.2, p.get_trait(&"risk_tolerance"))
	return 1.0


## Adds (or, with a negative amount, soothes) an emotion.
func feel(e: StringName, amount: float, why: String, p: Personality) -> void:
	if not values.has(e) or amount == 0.0:
		return
	var v: float = values[e]
	if amount > 0.0:
		amount *= reactivity(e, p)
		v = v + amount * (1.0 - v)  # saturates towards 1
	else:
		v = maxf(0.0, v + amount)
	values[e] = clampf(v, 0.0, 1.0)
	if absf(amount) >= 0.05:
		causes.append({"emotion": String(e), "amount": amount, "why": why, "day": SimClock.get_day()})
		if causes.size() > MAX_CAUSES:
			causes.pop_front()


func decay(dt_days: float) -> void:
	for e in LIST:
		var hl: float = HALF_LIFE_DAYS[e]
		if hl > 0.0:
			values[e] = values[e] * pow(0.5, dt_days / hl)


## Overall wellbeing, -1 .. 1.
func mood() -> float:
	var pos := 0.0
	var neg := 0.0
	for e in POSITIVE:
		pos += values[e]
	for e in NEGATIVE:
		neg += values[e]
	neg += values[&"loneliness"] * 0.5
	return clampf(tanh((pos - neg) * 0.9), -1.0, 1.0)


## Strongest emotions, e.g. [["grief", 0.8], ...].
func dominant(n: int = 3, min_value: float = 0.12) -> Array:
	var list := []
	for e in LIST:
		if values[e] >= min_value:
			list.append([e, values[e]])
	list.sort_custom(func(a, b): return a[1] > b[1])
	return list.slice(0, n)


## Most recent reasons for an emotion (strongest first).
func reasons_for(e: StringName, n: int = 2) -> PackedStringArray:
	var out: PackedStringArray = []
	for i in range(causes.size() - 1, -1, -1):
		var c: Dictionary = causes[i]
		if c["emotion"] == String(e) and c["amount"] > 0.0 and not out.has(c["why"]):
			out.append(c["why"])
			if out.size() >= n:
				break
	return out


func to_dict() -> Dictionary:
	var v := {}
	for e in LIST:
		v[String(e)] = values[e]
	return {"values": v, "causes": causes.duplicate(true)}


static func from_dict(d: Dictionary) -> Emotions:
	var em := Emotions.new()
	for e in LIST:
		em.values[e] = float(d["values"].get(String(e), 0.0))
	em.causes = Array(d["causes"]).duplicate(true)
	return em
