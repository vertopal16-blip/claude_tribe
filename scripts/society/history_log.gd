class_name HistoryLog
extends RefCounted
## The tribe's chronicle: important developments with day, category and the
## villagers involved. Bounded; persisted with the save game.

const MAX_ENTRIES := 600

## [{"day", "time", "category", "text", "who": [ids]}]
var entries: Array = []
## category -> count (never trimmed), useful for tests and statistics.
var counts: Dictionary = {}


func add(category: StringName, text: String, who: Array = []) -> void:
	entries.append({"day": SimClock.get_day(), "time": SimClock.get_clock_string(), "category": String(category),
		"text": text, "who": who.duplicate()})
	counts[String(category)] = int(counts.get(String(category), 0)) + 1
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	EventBus.history_added.emit(entries.back())


func count(category: StringName) -> int:
	return int(counts.get(String(category), 0))


func about(villager_id: int, n: int = 8) -> Array:
	var out := []
	for i in range(entries.size() - 1, -1, -1):
		if entries[i]["who"].has(villager_id):
			out.append(entries[i])
			if out.size() >= n:
				break
	return out


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "counts": counts.duplicate()}


func load_dict(d: Dictionary) -> void:
	entries = Array(d["entries"]).duplicate(true)
	counts = Dictionary(d["counts"]).duplicate()
