class_name VillagerMemory
extends RefCounted
## Bounded per-villager memory.
##
## * Short-term: recent experiences, decaying fast. Repeats of the same thing
##   (same kind, same people) merge into one record with a count.
## * Long-term: only important experiences (or often repeated ones) are
##   promoted; they decay slowly. Both stores have hard capacity limits, so
##   memory never grows without bound however long the game runs.

const SHORT_CAPACITY := 24
const LONG_CAPACITY := 16
## Salience lost per sim-day (fraction).
const SHORT_DECAY_PER_DAY := 0.6
const LONG_DECAY_PER_DAY := 0.08
const FORGET_BELOW := 0.04
## Repeating an experience this often makes it memorable.
const REPEAT_PROMOTION := 4

var short: Array[MemoryRecord] = []
var long: Array[MemoryRecord] = []


func remember(r: MemoryRecord) -> void:
	for existing in short:
		if existing.same_topic(r):
			existing.count += r.count
			existing.time = r.time
			existing.day = r.day
			existing.salience = minf(1.0, maxf(existing.salience, r.salience) + 0.03)
			existing.valence = lerpf(existing.valence, r.valence, 0.3)
			if r.detail != "":
				existing.detail = r.detail
			_maybe_promote(existing)
			return
	short.append(r)
	_maybe_promote(r)
	if short.size() > SHORT_CAPACITY:
		consolidate()


func _maybe_promote(r: MemoryRecord) -> void:
	if r.salience < MemoryPolicy.LONG_TERM_THRESHOLD and r.count < REPEAT_PROMOTION:
		return
	for existing in long:
		if existing.same_topic(r):
			existing.count = maxi(existing.count, r.count)
			existing.time = r.time
			existing.day = r.day
			existing.salience = minf(1.0, maxf(existing.salience, r.salience))
			return
	var copy := MemoryRecord.from_dict(r.to_dict())
	long.append(copy)
	if long.size() > LONG_CAPACITY:
		long.sort_custom(func(a, b): return a.salience > b.salience)
		long.resize(LONG_CAPACITY)


## Drops the least salient short-term records until within capacity.
func consolidate() -> void:
	short.sort_custom(func(a, b): return a.salience > b.salience)
	if short.size() > SHORT_CAPACITY:
		short.resize(SHORT_CAPACITY)
	short.sort_custom(func(a, b): return a.time < b.time)


func decay(dt_days: float) -> void:
	var fs := 1.0 - SHORT_DECAY_PER_DAY * dt_days
	var fl := 1.0 - LONG_DECAY_PER_DAY * dt_days
	for i in range(short.size() - 1, -1, -1):
		short[i].salience *= fs
		if short[i].salience < FORGET_BELOW:
			short.remove_at(i)
	for i in range(long.size() - 1, -1, -1):
		long[i].salience *= fl
		if long[i].salience < FORGET_BELOW:
			long.remove_at(i)


func size() -> int:
	return short.size() + long.size()


## -1 (grieving / miserable) .. 1 (happy), from salient recent feelings.
func mood() -> float:
	var total := 0.0
	for r in short:
		total += r.valence * r.salience
	for r in long:
		total += r.valence * r.salience * 0.5
	return clampf(tanh(total * 0.8), -1.0, 1.0)


## Records about a given villager (as "other" or "subject").
func about(villager_id: int) -> Array[MemoryRecord]:
	var out: Array[MemoryRecord] = []
	for r in long + short:
		if r.other_id == villager_id or r.subject_id == villager_id:
			out.append(r)
	return out


func has_recent(kind: StringName, since_time: float) -> bool:
	for r in short:
		if r.kind == kind and r.time >= since_time:
			return true
	return false


## The most notable memories: long-term first, then vivid recent ones.
func notable(n: int) -> Array[MemoryRecord]:
	var all: Array[MemoryRecord] = []
	var seen := {}
	for r in long + short:
		var key := "%s/%d/%d" % [r.kind, r.other_id, r.subject_id]
		if seen.has(key):
			continue
		seen[key] = true
		all.append(r)
	all.sort_custom(func(a, b): return a.salience * (1.0 + 0.002 * a.time) > b.salience * (1.0 + 0.002 * b.time))
	if all.size() > n:
		all.resize(n)
	return all


func to_dict() -> Dictionary:
	return {"short": short.map(func(r): return r.to_dict()), "long": long.map(func(r): return r.to_dict())}


static func from_dict(d: Dictionary) -> VillagerMemory:
	var m := VillagerMemory.new()
	for x in d["short"]:
		m.short.append(MemoryRecord.from_dict(x))
	for x in d["long"]:
		m.long.append(MemoryRecord.from_dict(x))
	return m
