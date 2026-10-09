class_name MemoryRecord
extends RefCounted
## One remembered experience. Plain data, referencing others only by id.

var kind: StringName
var time: float = 0.0
var day: int = 1
## The other villager involved (-1 = none).
var other_id: int = -1
## A third villager the memory is about (gossip, deaths of kin...).
var subject_id: int = -1
## A world object involved (building / resource entity id).
var object_id: int = -1
var valence: float = 0.0
var salience: float = 0.0
## How many similar experiences this record summarizes.
var count: int = 1
var detail: String = ""


func same_topic(o: MemoryRecord) -> bool:
	return kind == o.kind and other_id == o.other_id and subject_id == o.subject_id


func to_dict() -> Dictionary:
	return {"kind": String(kind), "time": time, "day": day, "other": other_id, "subject": subject_id,
		"object": object_id, "valence": valence, "salience": salience, "count": count, "detail": detail}


static func from_dict(d: Dictionary) -> MemoryRecord:
	var r := MemoryRecord.new()
	r.kind = StringName(d["kind"])
	r.time = float(d["time"])
	r.day = int(d["day"])
	r.other_id = int(d["other"])
	r.subject_id = int(d["subject"])
	r.object_id = int(d["object"])
	r.valence = float(d["valence"])
	r.salience = float(d["salience"])
	r.count = int(d["count"])
	r.detail = String(d["detail"])
	return r
