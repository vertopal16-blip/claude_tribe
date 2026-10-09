class_name RelationshipGraph
extends RefCounted
## Sparse graph of how villagers feel about each other.
##
## * Opinions are directional (A may trust B while B despises A):
##   affinity (-1..1) and trust (0..1), keyed by (from, to).
## * Bonds are mutual: familiarity (0..1) and tags (kin, partner, friend, rival).
## Only villager ids are stored, so the graph persists and outlives deaths.

const DEFAULT_TRUST := 0.5

var _opinions: Dictionary = {}  # Vector2i(from, to) -> {"affinity", "trust"}
var _bonds: Dictionary = {}     # Vector2i(min, max) -> {"familiarity", "tags": Array}


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


func set_opinion(from: int, to: int, aff: float, tr: float) -> void:
	_opinions[Vector2i(from, to)] = {"affinity": clampf(aff, -1.0, 1.0), "trust": clampf(tr, 0.0, 1.0)}


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
	for key: Vector2i in _bonds:
		if (key.x == id or key.y == id) and _bonds[key]["tags"].has(t):
			out.append(key.y if key.x == id else key.x)
	return out


func partner_of(id: int) -> int:
	var p := with_tag(id, &"partner")
	return -1 if p.is_empty() else p[0]


func is_kin(a: int, b: int) -> bool:
	return has_tag(a, b, &"kin")


## Ids `id` has any opinion about, for UI and planning.
func known_by(id: int) -> Array[int]:
	var out: Array[int] = []
	for key: Vector2i in _opinions:
		if key.x == id:
			out.append(key.y)
	return out


func to_dict() -> Dictionary:
	var ops := []
	for key: Vector2i in _opinions:
		ops.append([key.x, key.y, _opinions[key]["affinity"], _opinions[key]["trust"]])
	var bonds := []
	for key: Vector2i in _bonds:
		bonds.append([key.x, key.y, _bonds[key]["familiarity"], _bonds[key]["tags"].duplicate()])
	return {"opinions": ops, "bonds": bonds}


static func from_dict(d: Dictionary) -> RelationshipGraph:
	var g := RelationshipGraph.new()
	for o in d["opinions"]:
		g._opinions[Vector2i(int(o[0]), int(o[1]))] = {"affinity": float(o[2]), "trust": float(o[3])}
	for b in d["bonds"]:
		g._bonds[Vector2i(int(b[0]), int(b[1]))] = {"familiarity": float(b[2]), "tags": Array(b[3]).duplicate()}
	return g
