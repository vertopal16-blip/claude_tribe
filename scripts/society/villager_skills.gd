class_name VillagerSkills
extends RefCounted
## Skill levels (0..100) learned by doing, watching and being taught.
## Levels decay slowly when not practised. Aptitude (inborn / inherited)
## scales how fast each skill is learned.

const LIST: Array[StringName] = [&"foraging", &"woodcutting", &"stonework", &"building", &"farming",
	&"fishing", &"toolmaking", &"healing", &"persuasion"]
## Skills whose work benefits from carrying a tool.
const TOOL_SKILLS := [&"woodcutting", &"stonework", &"building", &"farming", &"fishing"]
const MASTERY := 60
## Level gained per second of practice at aptitude 1.0, before diminishing returns.
const PRACTICE_RATE := 0.05
## Level lost per day without practice (only above DECAY_FLOOR).
const DECAY_PER_DAY := 0.6
const DECAY_FLOOR := 15.0

var levels: Dictionary = {}
var aptitude: Dictionary = {}
## Sim time each skill was last used (for decay).
var last_used: Dictionary = {}
## Recent practice seconds per skill (decays daily): what this person
## actually spends their days doing.
var recent: Dictionary = {}


static func generate(rng: RandomNumberGenerator, age: float) -> VillagerSkills:
	var s := VillagerSkills.new()
	for k in LIST:
		s.aptitude[k] = clampf(rng.randfn(1.0, 0.25), 0.4, 1.6)
		# Adults arrive with some experience in a couple of things.
		s.levels[k] = 0.0
		s.last_used[k] = 0.0
	if age >= 16.0:
		for i in 2:
			var k: StringName = LIST[rng.randi() % 5]
			s.levels[k] = minf(45.0, s.levels[k] + rng.randf_range(10.0, 30.0))
	return s


## A newborn: aptitudes blended from the parents, no experience.
static func inherit(a: VillagerSkills, b: VillagerSkills, rng: RandomNumberGenerator) -> VillagerSkills:
	var s := VillagerSkills.new()
	for k in LIST:
		var blend := (float(a.aptitude.get(k, 1.0)) + float(b.aptitude.get(k, 1.0))) * 0.5
		s.aptitude[k] = clampf(lerpf(blend, rng.randfn(1.0, 0.25), 0.4), 0.4, 1.6)
		s.levels[k] = 0.0
		s.last_used[k] = SimClock.sim_time
	return s


func get_level(k: StringName) -> float:
	return float(levels.get(k, 0.0))


## Novice 0.55x, average 1.0x (~47), master 1.5x.
func efficiency(k: StringName) -> float:
	return 0.55 + 0.95 * get_level(k) / 100.0


func practice(k: StringName, seconds: float, p: Personality) -> void:
	if not levels.has(k):
		return
	var lvl: float = levels[k]
	var rate := PRACTICE_RATE * float(aptitude[k]) * lerpf(0.8, 1.2, p.get_trait(&"patience"))
	levels[k] = minf(100.0, lvl + rate * seconds * (1.0 - lvl / 110.0))
	last_used[k] = SimClock.sim_time
	recent[k] = float(recent.get(k, 0.0)) + seconds


## Share of recent work spent on `k` (0..1).
func recent_share(k: StringName) -> float:
	var total := 0.0
	for x in recent.values():
		total += x
	return 0.0 if total < 30.0 else float(recent.get(k, 0.0)) / total


## Learning from someone better (watching or being taught). Returns gain.
func learn_from(k: StringName, teacher_level: float, strength: float, p: Personality) -> float:
	var lvl := get_level(k)
	if teacher_level <= lvl:
		return 0.0
	var gain := (teacher_level - lvl) * strength * float(aptitude.get(k, 1.0)) * lerpf(0.7, 1.3, p.get_trait(&"curiosity"))
	levels[k] = minf(100.0, lvl + gain)
	last_used[k] = SimClock.sim_time
	return gain


## Called periodically; `elapsed` seconds of sim time have passed.
func decay(day_length: float, elapsed: float) -> void:
	var days := elapsed / day_length
	var keep := pow(0.6, days)
	for k in recent:
		recent[k] *= keep
	var now := SimClock.sim_time
	for k in LIST:
		var idle_days := (now - float(last_used.get(k, 0.0))) / day_length
		if idle_days > 1.0 and levels[k] > DECAY_FLOOR:
			levels[k] = maxf(DECAY_FLOOR, levels[k] - DECAY_PER_DAY * days)


func best() -> StringName:
	var top: StringName = &""
	var top_v := 0.0
	for k in LIST:
		if k != &"persuasion" and levels[k] > top_v:
			top_v = levels[k]
			top = k
	return top


func to_dict() -> Dictionary:
	var out := {}
	for k in LIST:
		out[String(k)] = [levels[k], aptitude[k], last_used[k], recent.get(k, 0.0)]
	return out


static func from_dict(d: Dictionary) -> VillagerSkills:
	var s := VillagerSkills.new()
	for k in LIST:
		var row: Array = d.get(String(k), [0.0, 1.0, 0.0])
		s.levels[k] = float(row[0])
		s.aptitude[k] = float(row[1])
		s.last_used[k] = float(row[2])
		if row.size() > 3:
			s.recent[k] = float(row[3])
	return s
