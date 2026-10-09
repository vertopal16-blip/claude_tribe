class_name PromiseBook
extends RefCounted
## Promises villagers make to each other ("I'll help build your home").
## Kept promises build trust and respect; broken ones are remembered.

## [{"from", "to", "kind", "object", "due_day", "text", "made_day"}]
var open: Array = []
var kept := 0
var broken := 0
var social: SocialSystem


func _init(s: SocialSystem) -> void:
	social = s


func make(from_id: int, to_id: int, kind: StringName, object_id: int, due_days: float, text: String) -> void:
	open.append({"from": from_id, "to": to_id, "kind": String(kind), "object": object_id,
		"due_day": SimClock.get_day() + due_days, "text": text, "made_day": SimClock.get_day()})


## Called when villager `who` contributes to building `building_id`.
func on_contribution(who: int, building_id: int) -> void:
	for p in open.duplicate():
		if p["from"] == who and p["kind"] == "help_build" and p["object"] == building_id:
			_resolve(p, true)


func check_due() -> void:
	var day := SimClock.get_day()
	for p in open.duplicate():
		var obj := _building(p["object"])
		if obj == null or obj.is_complete:
			# Finished (or gone) without them: broken if they never came.
			_resolve(p, false)
		elif day > p["due_day"]:
			_resolve(p, false)


func _building(id: int) -> Building:
	for b in social.ctx.tribe.buildings:
		if b.entity_id == id:
			return b
	return null


func _resolve(p: Dictionary, was_kept: bool) -> void:
	open.erase(p)
	var to := social.get_villager(p["to"])
	if to == null:
		return
	if was_kept:
		kept += 1
		social.remember(to, &"promise_kept", p["from"], -1, -1, p["text"])
	else:
		broken += 1
		social.remember(to, &"promise_broken", p["from"], -1, -1, p["text"])


func promises_by(id: int) -> Array:
	return open.filter(func(p): return p["from"] == id)


func to_dict() -> Dictionary:
	return {"open": open.duplicate(true), "kept": kept, "broken": broken}


func load_dict(d: Dictionary) -> void:
	open = Array(d["open"]).duplicate(true)
	kept = int(d["kept"])
	broken = int(d["broken"])
