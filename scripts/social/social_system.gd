class_name SocialSystem
extends RefCounted
## Tribe-wide social layer: relationships, memories, perception and
## conversations. Runs on the simulation tick at a slower, staggered cadence
## and changes game state only through deterministic, validated rules.
##
## Every experience goes through remember(): it creates a memory, updates the
## rememberer's opinion of whoever was involved, nudges their personality and
## re-evaluates bonds (friend / rival / partner).

## Each villager gets a social update (perception, memory decay...) this often.
const UPDATE_INTERVAL := 1.0
const WITNESS_RADIUS := 16.0
## Founders already know the land around the camp.
const FOUNDER_KNOWLEDGE_RADIUS := 30.0
const ADULT_AGE := 17.0

var ctx: WorldContext
var graph := RelationshipGraph.new()
var conversations: ConversationSystem
var romance: RomanceSystem
var promises: PromiseBook
var rng := RandomNumberGenerator.new()
## Counters for UI / tests.
var stats := {"conversations": 0, "topics": {}, "friendships": 0, "rivalries": 0, "partnerships": 0,
	"memories": 0, "misled": 0, "help_given": 0, "help_refused": 0}

var _names: Dictionary = {}   # villager id -> name (kept after death)
var _dead: Dictionary = {}    # villager id -> true
var _by_id: Dictionary = {}   # villager id -> Villager (living)
var _phase_timer := 0.0
var _phase := 0
var _updating_bond := false


func _init(context: WorldContext) -> void:
	ctx = context
	rng.seed = hash([social_seed(), "social"])
	conversations = ConversationSystem.new(self)
	romance = RomanceSystem.new(self)
	promises = PromiseBook.new(self)


## Seed for everything social. Same world + different social seed = same
## valley, different people (and so a different society and settlement).
func social_seed() -> int:
	return ctx.config.social_seed if ctx.config.social_seed != 0 else ctx.world_seed


# --------------------------------------------------------------------------
# Villager lifecycle
# --------------------------------------------------------------------------

func register_villager(v: Villager) -> void:
	_names[v.villager_id] = v.villager_name
	_by_id[v.villager_id] = v
	romance.register(v)


func get_villager(id: int) -> Villager:
	var v = _by_id.get(id)
	return v if v != null and is_instance_valid(v) and not v.is_dead else null


func is_alive(id: int) -> bool:
	return get_villager(id) != null


func name_of(id: int) -> String:
	return _names.get(id, "someone")


## Founding families and first impressions for the starting tribe.
func setup_founders(villagers: Array[Villager]) -> void:
	var order: Array[Villager] = villagers.duplicate()
	# Deterministic shuffle with the social rng.
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	# Two founding couples (a woman and a man each, so they can raise children).
	var women: Array[Villager] = order.filter(func(v): return v.age_years >= 18.0 and v.sex == &"female")
	var men: Array[Villager] = order.filter(func(v): return v.age_years >= 18.0 and v.sex == &"male")
	var couples: Array = []
	var used := {}
	while not women.is_empty() and not men.is_empty() and couples.size() < 2:
		var a: Villager = women.pop_front()
		var b: Villager = men.pop_front()
		couples.append([a, b])
		used[a.villager_id] = true
		used[b.villager_id] = true
	var rest: Array[Villager] = order.filter(func(v): return not used.has(v.villager_id))
	var siblings: Array = []
	if rest.size() >= 2:
		siblings.append([rest[0], rest[1]])

	# Everyone in a small tribe knows everyone a little.
	for a in villagers:
		for b in villagers:
			if a == b:
				continue
			var trust := 0.4 + a.personality.get_trait(&"trust") * 0.25
			graph.set_opinion(a.villager_id, b.villager_id, rng.randf_range(-0.15, 0.3), trust)
			graph.add_familiarity(a.villager_id, b.villager_id, 0.15)  # added twice -> 0.3
	for pair in couples:
		_bond_founders(pair[0], pair[1], 0.75, 0.75, 0.85, &"partner")
		graph.set_field(pair[0].villager_id, pair[1].villager_id, "attraction", 0.7)
		graph.set_field(pair[1].villager_id, pair[0].villager_id, "attraction", 0.7)
		romance.together_since[RelationshipGraph._bond_key(pair[0].villager_id, pair[1].villager_id)] = 1
	for pair in siblings:
		_bond_founders(pair[0], pair[1], 0.5, 0.68, 0.9, &"kin")
	for v in villagers:
		v.knowledge.perceive(FOUNDER_KNOWLEDGE_RADIUS)
		v.needs.social = rng.randf_range(0.0, 40.0)


func _bond_founders(a: Villager, b: Villager, aff: float, tr: float, fam: float, tag: StringName) -> void:
	graph.set_opinion(a.villager_id, b.villager_id, aff + rng.randf_range(-0.08, 0.08), tr)
	graph.set_opinion(b.villager_id, a.villager_id, aff + rng.randf_range(-0.08, 0.08), tr)
	graph.add_familiarity(a.villager_id, b.villager_id, fam)
	graph.set_tag(a.villager_id, b.villager_id, tag, true)


## Couples, used to hand out the starting huts.
func founding_couples() -> Array:
	var out := []
	var seen := {}
	for id in _by_id:
		var p := partner_of(id)
		if p >= 0 and not seen.has(id):
			seen[id] = true
			seen[p] = true
			out.append([id, p])
	return out


# --------------------------------------------------------------------------
# Tick
# --------------------------------------------------------------------------

var _promise_timer := 0.0


func tick(dt: float) -> void:
	conversations.tick(dt)
	romance.tick(dt)
	_promise_timer += dt
	if _promise_timer >= 30.0:
		_promise_timer = 0.0
		promises.check_due()
	# Spread per-villager updates across 4 sub-phases of UPDATE_INTERVAL.
	_phase_timer += dt
	var step := UPDATE_INTERVAL / 4.0
	while _phase_timer >= step:
		_phase_timer -= step
		_phase = (_phase + 1) % 4
		for v in ctx.tribe.villagers:
			if v.villager_id % 4 == _phase:
				_update_villager(v)


func _update_villager(v: Villager) -> void:
	if v.is_dead:
		return
	if not v.is_hidden():
		v.knowledge.perceive_if_needed()
	var dt_days := UPDATE_INTERVAL / ctx.config.day_length_seconds
	v.memory.decay(dt_days)
	v.emotions.decay(dt_days)
	var p := v.personality
	# Ongoing circumstances feed emotions continuously.
	v.emotions.values[&"loneliness"] = v.needs.social / 100.0
	if v.needs.hunger > 70.0:
		v.emotions.feel(&"stress", 0.04, "Going hungry", p)
	if v.needs.energy < 15.0:
		v.emotions.feel(&"stress", 0.03, "Exhausted", p)
	if v.needs.health < 50.0:
		v.emotions.feel(&"fear", 0.04, "Feeling unwell", p)
	if v.needs.is_starving() and not v.memory.has_recent(&"starved", SimClock.sim_time - ctx.config.day_length_seconds):
		remember(v, &"starved")
	# Over time, memories are reinterpreted in the light of how we feel now,
	# and grudges fade - faster for patient, caring, loyal people.
	if (v.villager_id + int(SimClock.sim_time)) % 20 == 0:
		v.memory.reinterpret(func(id): return graph.affinity(v.villager_id, id))
		var forgiving := (p.get_trait(&"patience") + p.get_trait(&"empathy") + p.get_trait(&"loyalty")) / 3.0
		var half_life_days := lerpf(14.0, 3.0, forgiving)
		graph.fade_resentment(v.villager_id, pow(0.5, (20.0 / ctx.config.day_length_seconds) / half_life_days))


# --------------------------------------------------------------------------
# Experiences -> memory, opinions, personality, bonds
# --------------------------------------------------------------------------

func remember(v: Villager, kind: StringName, other_id: int = -1, subject_id: int = -1,
		object_id: int = -1, detail: String = "") -> MemoryRecord:
	if not MemoryPolicy.has_kind(kind):
		push_warning("Unknown memory kind %s" % kind)
		return null
	var r := MemoryRecord.new()
	r.kind = kind
	r.time = SimClock.sim_time
	r.day = SimClock.get_day()
	r.other_id = other_id
	r.subject_id = subject_id
	r.object_id = object_id
	r.detail = detail
	r.valence = MemoryPolicy.valence(kind)
	r.salience = MemoryPolicy.salience(kind)
	# Everyone experiences things through their own temperament: the same
	# argument stings an impatient person more than a patient one.
	var p := v.personality
	if r.valence < 0.0:
		r.valence *= lerpf(1.3, 0.75, p.get_trait(&"patience"))
	else:
		r.valence *= lerpf(0.85, 1.15, p.get_trait(&"empathy"))
	# Experiences with the people closest to us weigh more.
	if other_id >= 0 and (graph.has_tag(v.villager_id, other_id, &"partner") or graph.is_kin(v.villager_id, other_id)):
		r.salience = minf(1.0, r.salience * 1.3)
	v.memory.remember(r)
	stats.memories += 1

	# Feelings: personality scales how strongly each one is felt.
	var why := MemoryPolicy.describe(r, name_of)
	for em in MemoryPolicy.EMOTIONS.get(kind, []):
		v.emotions.feel(em[0], em[1], why, p)

	if other_id >= 0 and other_id != v.villager_id:
		var d_aff := MemoryPolicy.affinity_delta(kind)
		var d_trust := MemoryPolicy.trust_delta(kind)
		# Caring people warm up faster; suspicious people hold grudges.
		d_aff *= lerpf(0.7, 1.3, p.get_trait(&"empathy")) if d_aff > 0.0 else lerpf(1.3, 0.8, p.get_trait(&"trust"))
		d_trust *= lerpf(0.7, 1.2, p.get_trait(&"trust")) if d_trust > 0.0 else lerpf(1.3, 0.8, p.get_trait(&"trust"))
		graph.adjust_opinion(v.villager_id, other_id, d_aff, d_trust)
		# Hurt turns into lasting resentment; kindness slowly heals it.
		if d_aff < 0.0:
			graph.adjust_field(v.villager_id, other_id, "resentment", -d_aff * 0.6 * lerpf(1.2, 0.6, p.get_trait(&"patience")))
		else:
			graph.adjust_field(v.villager_id, other_id, "resentment", -d_aff * 0.5)
		if RESPECT.has(kind):
			graph.adjust_field(v.villager_id, other_id, "respect", RESPECT[kind])
		graph.add_familiarity(v.villager_id, other_id, 0.02)
		_update_bond(v.villager_id, other_id)
		if r.valence > 0.1 and kind in [&"chatted", &"worked_together", &"built_together", &"was_helped", &"was_comforted", &"reconciled"]:
			var other := get_villager(other_id)
			if other != null:
				romance.on_good_time(v, other)

	for drift in MemoryPolicy.TRAIT_DRIFT.get(kind, []):
		v.personality.drift(drift[0], drift[1])
	EventBus.social_event.emit(v, kind, r.to_dict())
	return r


## How experiences change respect for the other person involved.
const RESPECT := {
	&"was_helped": 0.1, &"was_taught": 0.15, &"learned_discovery": 0.1, &"mediated": 0.15,
	&"persuaded": 0.06, &"fought": -0.05, &"misled": -0.1, &"was_refused": -0.05,
	&"accused": -0.05, &"humiliated": -0.15, &"promise_kept": 0.1, &"got_tool": 0.05,
	&"worked_together": 0.02, &"built_together": 0.04,
}


func _update_bond(a: int, b: int) -> void:
	if _updating_bond or not is_alive(a) or not is_alive(b):
		return
	_updating_bond = true
	var fa := graph.affinity(a, b)
	var fb := graph.affinity(b, a)
	var fam := graph.familiarity(a, b)
	var friends := fa > 0.45 and fb > 0.45 and fam > 0.3
	var rivals := (fa < -0.4 and fb < -0.25) or (fb < -0.4 and fa < -0.25) or fa < -0.65 or fb < -0.65
	if graph.set_tag(a, b, &"rival", rivals) and rivals:
		graph.set_tag(a, b, &"friend", false)
		stats.rivalries += 1
		remember(get_villager(a), &"became_rivals", b)
		remember(get_villager(b), &"became_rivals", a)
		EventBus.notify("%s and %s have become rivals." % [name_of(a), name_of(b)], &"social")
	elif not rivals and graph.set_tag(a, b, &"friend", friends) and friends:
		stats.friendships += 1
		remember(get_villager(a), &"became_friends", b)
		remember(get_villager(b), &"became_friends", a)
		EventBus.notify("%s and %s have become friends." % [name_of(a), name_of(b)], &"social")
	_updating_bond = false


func can_partner(a: Villager, b: Villager) -> bool:
	if a == null or b == null or a == b:
		return false
	if a.age_years < ADULT_AGE or b.age_years < ADULT_AGE:
		return false
	if partner_of(a.villager_id) >= 0 or partner_of(b.villager_id) >= 0:
		return false
	return not graph.is_kin(a.villager_id, b.villager_id)


## Forms a partnership if both feel strongly enough. Returns true on success.
func try_partnership(a: Villager, b: Villager) -> bool:
	if not can_partner(a, b):
		return false
	var ia := a.villager_id
	var ib := b.villager_id
	if graph.affinity(ia, ib) < 0.6 or graph.affinity(ib, ia) < 0.6 or graph.familiarity(ia, ib) < 0.45:
		return false
	graph.set_tag(ia, ib, &"partner", true)
	stats.partnerships += 1
	remember(a, &"became_partners", ib)
	remember(b, &"became_partners", ia)
	EventBus.notify("%s and %s are now partners!" % [a.villager_name, b.villager_name], &"social")
	return true


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

## Living partner id, or -1.
func partner_of(id: int) -> int:
	for p in graph.with_tag(id, &"partner"):
		if is_alive(p):
			return p
	return -1


func friends_of(id: int) -> Array[int]:
	return graph.with_tag(id, &"friend").filter(func(o): return is_alive(o))


func rivals_of(id: int) -> Array[int]:
	return graph.with_tag(id, &"rival").filter(func(o): return is_alive(o))


func kin_of(id: int) -> Array[int]:
	return graph.with_tag(id, &"kin").filter(func(o): return is_alive(o))


## How close `from` feels to `to`, including family ties (-1..~1.5).
func closeness(from: int, to: int) -> float:
	var c := graph.affinity(from, to)
	if graph.has_tag(from, to, &"partner"):
		c += 0.5
	elif graph.is_kin(from, to):
		c += 0.35
	return c


## Someone close to `v` who is going hungry and could use `v`'s food.
func find_person_to_help(v: Villager, max_distance: float = 50.0) -> Villager:
	var best: Villager = null
	var best_score := 0.3
	var empathy := v.personality.get_trait(&"empathy")
	for o in ctx.tribe.villagers_near(v.global_position, max_distance):
		if o == v or o.is_dead or o.is_hidden():
			continue
		if o.needs.hunger < ctx.config.hungry_threshold + 10.0:
			continue
		if o.inventory.carried_type == ResourceType.FOOD or o.current_task is EatTask:
			continue
		var d := v.global_position.distance_to(o.global_position)
		if d > max_distance:
			continue
		# Caring villagers help even people they barely know.
		var score := closeness(v.villager_id, o.villager_id) + empathy * 0.3 - d * 0.004
		if score > best_score:
			best_score = score
			best = o
	return best


static func mood_label(mood: float) -> String:
	if mood < -0.5:
		return "Grieving"
	if mood < -0.15:
		return "Unhappy"
	if mood < 0.3:
		return "Content"
	return "Happy"


# --------------------------------------------------------------------------
# World events
# --------------------------------------------------------------------------

func on_villager_died(dead: Villager) -> void:
	var id := dead.villager_id
	_dead[id] = true
	_by_id.erase(id)
	for o in ctx.tribe.villagers:
		if o == dead or o.is_dead:
			continue
		var oid := o.villager_id
		if graph.has_tag(oid, id, &"partner"):
			remember(o, &"lost_partner", -1, id)
		elif graph.is_kin(oid, id):
			remember(o, &"lost_family", -1, id)
		elif graph.affinity(oid, id) > 0.35:
			remember(o, &"lost_friend", -1, id)
		elif o.global_position.distance_to(dead.global_position) < WITNESS_RADIUS:
			remember(o, &"saw_death", -1, id)


func on_building_completed(b: Building) -> void:
	var bname := b.def.display_name.to_lower()
	var crew: Array[Villager] = []
	for cid in b.contributor_ids:
		var c := get_villager(cid)
		if c != null:
			crew.append(c)
	for c in crew:
		remember(c, &"built", -1, -1, b.entity_id, bname)
		for other in crew:
			if other != c:
				remember(c, &"built_together", other.villager_id, -1, b.entity_id, bname)
	for oid in b.owner_ids:
		var owner := get_villager(oid)
		if owner != null:
			ctx.tribe.assign_home(owner, b)
			remember(owner, &"moved_in", -1, -1, b.entity_id)


func on_misled(v: Villager, teller_id: int, what: String) -> void:
	stats.misled += 1
	remember(v, &"misled", teller_id, -1, -1, what)


# --------------------------------------------------------------------------
# Persistence
# --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var people := {}
	for v in ctx.tribe.villagers:
		people[str(v.villager_id)] = {
			"personality": v.personality.to_dict(),
			"memory": v.memory.to_dict(),
			"knowledge": v.knowledge.store.to_dict(),
			"loneliness": v.needs.social,
		}
	var names := {}
	for id in _names:
		names[str(id)] = _names[id]
	return {"graph": graph.to_dict(), "people": people, "names": names, "dead": _dead.keys(),
		"romance": romance.to_dict(), "promises": promises.to_dict(), "stats": stats.duplicate(true)}


## Restores social state onto the current (living) villagers by id.
func load_dict(d: Dictionary) -> void:
	graph = RelationshipGraph.from_dict(d["graph"])
	romance.load_dict(d["romance"])
	promises.load_dict(d["promises"])
	stats = Dictionary(d["stats"]).duplicate(true)
	for id in d["names"]:
		_names[int(id)] = d["names"][id]
	_dead.clear()
	for id in d["dead"]:
		_dead[int(id)] = true
	for v in ctx.tribe.villagers:
		var p = d["people"].get(str(v.villager_id))
		if p == null:
			continue
		v.personality = Personality.from_dict(p["personality"])
		v.memory = VillagerMemory.from_dict(p["memory"])
		v.knowledge.store = KnowledgeStore.from_dict(p["knowledge"])
		v.needs.social = float(p["loneliness"])
