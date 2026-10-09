class_name KnowledgeStore
extends RefCounted
## Facts one villager holds about resource locations.
##
## A fact is a snapshot: what the villager (or whoever told them) saw at a
## given time. It can be out of date - a bush may since have been eaten -
## which is how misunderstandings and wasted trips arise.

## entity_id -> {"type", "pos", "amount", "regrows", "time", "source"}
## source = -1 when seen personally, otherwise the id of the villager who told.
var facts: Dictionary = {}
var _counts_dirty := true
var _available_counts: Dictionary = {}
## type -> {entity_id: true}, so lookups only scan facts of one type.
var _by_type: Dictionary = {}


func _index(entity_id: int, type: int) -> void:
	if not _by_type.has(type):
		_by_type[type] = {}
	_by_type[type][entity_id] = true


func ids_of_type(type: int) -> Array:
	var d = _by_type.get(type)
	return [] if d == null else d.keys()


func observe(node: ResourceNode, time: float) -> void:
	var f = facts.get(node.entity_id)
	if f == null:
		facts[node.entity_id] = {"type": node.resource_type, "pos": node.global_position, "amount": node.amount,
			"regrows": node.regrows, "time": time, "source": -1}
		_index(node.entity_id, node.resource_type)
		_counts_dirty = true
		return
	if int(f["amount"]) != node.amount:
		_counts_dirty = true
	f["amount"] = node.amount
	f["time"] = time
	f["source"] = -1


## Accepts a fact from someone else unless we already know something newer.
func learn(entity_id: int, fact: Dictionary, from_id: int) -> bool:
	var existing = facts.get(entity_id)
	if existing != null and float(existing["time"]) >= float(fact["time"]):
		return false
	var copy := fact.duplicate()
	copy["source"] = from_id
	facts[entity_id] = copy
	_index(entity_id, int(copy["type"]))
	_counts_dirty = true
	return true


func forget(entity_id: int) -> void:
	var f = facts.get(entity_id)
	if f == null:
		return
	facts.erase(entity_id)
	if _by_type.has(int(f["type"])):
		_by_type[int(f["type"])].erase(entity_id)
	_counts_dirty = true


func get_fact(entity_id: int):
	return facts.get(entity_id)


## Number of known locations believed to still have something.
func count_available(type: int) -> int:
	if _counts_dirty:
		_available_counts = ResourceType.empty_amounts()
		for f in facts.values():
			if int(f["amount"]) > 0:
				_available_counts[int(f["type"])] += 1
		_counts_dirty = false
	return int(_available_counts.get(type, 0))


func size() -> int:
	return facts.size()


func to_dict() -> Dictionary:
	var out := {}
	for id in facts:
		var f: Dictionary = facts[id]
		var p: Vector3 = f["pos"]
		out[str(id)] = [f["type"], [p.x, p.y, p.z], f["amount"], f["regrows"], f["time"], f["source"]]
	return out


static func from_dict(d: Dictionary) -> KnowledgeStore:
	var k := KnowledgeStore.new()
	for id in d:
		var a: Array = d[id]
		k.facts[int(id)] = {"type": int(a[0]), "pos": Vector3(a[1][0], a[1][1], a[1][2]), "amount": int(a[2]),
			"regrows": bool(a[3]), "time": float(a[4]), "source": int(a[5])}
		k._index(int(id), int(a[0]))
	return k
