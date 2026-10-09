class_name RelationshipGraph
extends RefCounted
## Sparse graph of how villagers feel about each other.
##
## * Opinions are directional (A may adore B while B barely notices A):
##   affinity (-1..1), trust (0..1), respect (-1..1), attraction (0..1) and
##   resentment (0..1), keyed by (from, to).
## * Bonds are mutual: familiarity (0..1) and tags (kin, partner, spouse,
##   ex_partner, courting, friend, close_friend, rival, enemy, mentor).
## Only villager ids are stored, so the graph persists and outlives deaths.

const DEFAULT_TRUST := 0.5

const FIELDS := ["affinity", "trust", "respect", "attraction", "resentment"]
const RANGES := {"affinity": [-1.0, 1.0], "trust": [0.0, 1.0], "respect": [-1.0, 1.0],
	"attraction": [0.0, 1.0], "resentment": [0.0, 1.0]}

var _opinions: Dictionary = {}  # Vector2i(from, to) -> {field: value}
var _bonds: Dictionary = {}     # Vector2i(min, max) -> {"familiarity", "tags": Array}
## Per-villager indexes so lookups never scan the whole tribe.
var _known: Dictionary = {}      # from id -> {to id: true}
var _bonded: Dictionary = {}     # id -> {other id: true}


static func _bond_key(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


func affinity(from: int, to: int) -> float:
	var o = _opinions.get(Vector2i(from, to))
	return 0.0 if o == null else o["affinity"]


func trust(from: int, to: int) -> float:
	var o = _opinions.get(Vector2i(from, to))
	return DEFAULT_TRUST if o == null else o["trust"]


func familiarity(a: int, b: int) -> float:
	var bond = _bonds.get(_bond_key(a, b))
	return 0.0 if bond == null else bond["familiarity"]


func _ensure_opinion(from: int, to: int) -> Dictionary:
	var key := Vector2i(from, to)
	if not _opinions.has(key):
		_opinions[key] = {"affinity": 0.0, "trust": DEFAULT_TRUST, "respect": 0.0, "attraction": 0.0, "resentment": 0.0}
		_index_opinion(from, to)
	return _opinions[key]


func _index_opinion(from: int, to: int) -> void:
	if not _known.has(from):
		_known[from] = {}
	_known[from][to] = true


func _index_bond(a: int, b: int) -> void:
	for pair in [[a, b], [b, a]]:
		if not _bonded.has(pair[0]):
			_bonded[pair[0]] = {}
		_bonded[pair[0]][pair[1]] = true


func has_opinion(from: int, to: int) -> bool:
	return _opinions.has(Vector2i(from, to))


func get_field(from: int, to: int, field: String) -> float:
	var o = _opinions.get(Vector2i(from, to))
	if o == null:
		return DEFAULT_TRUST if field == "trust" else 0.0
	return float(o.get(field, 0.0))


func set_field(from: int, to: int, field: String, value: float) -> void:
	if from == to:
		return
	var r: Array = RANGES[field]
	_ensure_opinion(from, to)[field] = clampf(value, r[0], r[1])


func adjust_field(from: int, to: int, field: String, delta: float) -> void:
	set_field(from, to, field, get_field(from, to, field) + delta)


func respect(from: int, to: int) -> float:
	return get_field(from, to, "respect")


func attraction(from: int, to: int) -> float:
	return get_field(from, to, "attraction")


func resentment(from: int, to: int) -> float:
	return get_field(from, to, "resentment")


func set_opinion(from: int, to: int, aff: float, tr: float) -> void:
	if from == to:
		return
	var o := _ensure_opinion(from, to)
	o["affinity"] = clampf(aff, -1.0, 1.0)
	o["trust"] = clampf(tr, 0.0, 1.0)


func adjust_opinion(from: int, to: int, d_affinity: float, d_trust: float) -> void:
	if from == to:
		return
	set_opinion(from, to, affinity(from, to) + d_affinity, trust(from, to) + d_trust)


func add_familiarity(a: int, b: int, d: float) -> void:
	if a == b:
		return
	var bond := _ensure_bond(a, b)
	bond["familiarity"] = clampf(bond["familiarity"] + d, 0.0, 1.0)


func _ensure_bond(a: int, b: int) -> Dictionary:
	var key := _bond_key(a, b)
	if not _bonds.has(key):
		_bonds[key] = {"familiarity": 0.0, "tags": []}
		_index_bond(a, b)
	return _bonds[key]


func has_tag(a: int, b: int, tag: StringName) -> bool:
	var bond = _bonds.get(_bond_key(a, b))
	return bond != null and bond["tags"].has(String(tag))


func set_tag(a: int, b: int, tag: StringName, on: bool) -> bool:
	var bond := _ensure_bond(a, b)
	var tags: Array = bond["tags"]
	var t := String(tag)
	if on and not tags.has(t):
		tags.append(t)
		return true
	if not on and tags.has(t):
		tags.erase(t)
		return true
	return false


## Ids of everyone `id` has a bond with that carries `tag`.
func with_tag(id: int, tag: StringName) -> Array[int]:
	var out: Array[int] = []
	var t := String(tag)
	for other in _bonded.get(id, {}):
		if _bonds[_bond_key(id, other)]["tags"].has(t):
			out.append(other)
	return out


func partner_of(id: int) -> int:
	var p := with_tag(id, &"partner")
	return -1 if p.is_empty() else p[0]


func is_kin(a: int, b: int) -> bool:
	return has_tag(a, b, &"kin")


## Grudges fade with time: multiplies every resentment `id` holds.
func fade_resentment(id: int, factor: float) -> void:
	for to in _known.get(id, {}):
		var o: Dictionary = _opinions[Vector2i(id, to)]
		o["resentment"] = o["resentment"] * factor


## All tags on the bond between a and b.
func tags(a: int, b: int) -> Array:
	var bond = _bonds.get(_bond_key(a, b))
	return [] if bond == null else bond["tags"].duplicate()


## Ids `id` has any opinion about, for UI and planning.
func known_by(id: int) -> Array[int]:
	var out: Array[int] = []
	out.assign(_known.get(id, {}).keys())
	return out


func to_dict() -> Dictionary:
	var ops := []
	for key: Vector2i in _opinions:
		var o: Dictionary = _opinions[key]
		var row := [key.x, key.y]
		for f in FIELDS:
			row.append(o.get(f, 0.0))
		ops.append(row)
	var bonds := []
	for key: Vector2i in _bonds:
		bonds.append([key.x, key.y, _bonds[key]["familiarity"], _bonds[key]["tags"].duplicate()])
	return {"opinions": ops, "bonds": bonds}


static func from_dict(d: Dictionary) -> RelationshipGraph:
	var g := RelationshipGraph.new()
	for o in d["opinions"]:
		var entry := {}
		for i in FIELDS.size():
			entry[FIELDS[i]] = float(o[2 + i])
		g._opinions[Vector2i(int(o[0]), int(o[1]))] = entry
		g._index_opinion(int(o[0]), int(o[1]))
	for b in d["bonds"]:
		g._bonds[Vector2i(int(b[0]), int(b[1]))] = {"familiarity": float(b[2]), "tags": Array(b[3]).duplicate()}
		g._index_bond(int(b[0]), int(b[1]))
	return g
