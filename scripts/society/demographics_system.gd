class_name DemographicsSystem
extends RefCounted
## Life cycle of the tribe: conception, pregnancy, birth, growing up, old age
## and natural death. Births only happen to established couples who are
## healthy, fed and housed, while the tribe has food to spare, so the
## population grows with its means rather than without limit.

const CHECK_INTERVAL := 20.0
## Food in store per person below which couples hold off on children.
const FOOD_PER_PERSON_FOR_CHILDREN := 4.0

const SYLLABLES_A := ["Ka", "Ru", "Ne", "So", "Ma", "Ti", "Lo", "Ve", "Ar", "En", "Il", "Da", "Ko", "Sa", "Ul", "Yo", "Fe", "Ba", "Ri", "Om"]
const SYLLABLES_B := ["ra", "no", "li", "sa", "ten", "ka", "mi", "ro", "va", "dun", "ne", "la", "ko", "ris", "ta", "en", "ya", "ru"]

var society: SocietySystem
var ctx: WorldContext
var births := 0
var natural_deaths := 0
var _timer := 0.0
var _stage: Dictionary = {}  # villager id -> last known life stage
var _used_names: Dictionary = {}


func _init(s: SocietySystem) -> void:
	society = s
	ctx = s.ctx


func register_name(n: String) -> void:
	_used_names[n] = true


func tick(dt: float) -> void:
	_timer += dt
	if _timer < CHECK_INTERVAL:
		return
	_timer -= CHECK_INTERVAL
	var day_fraction := CHECK_INTERVAL / ctx.config.day_length_seconds
	for v in ctx.tribe.villagers.duplicate():
		if v.is_dead:
			continue
		_track_stage(v)
		if v.pregnancy_days >= 0.0:
			v.pregnancy_days += day_fraction
			if v.pregnancy_days >= ctx.config.pregnancy_days:
				give_birth(v)
		elif can_conceive(v) and society.rng.randf() < _chance(conception_chance(v), day_fraction):
			conceive(v)
		_check_old_age(v, day_fraction)


static func _chance(per_day: float, day_fraction: float) -> float:
	return 1.0 - pow(1.0 - clampf(per_day, 0.0, 1.0), day_fraction)


# --------------------------------------------------------------------------
# Reproduction
# --------------------------------------------------------------------------

func fertile(v: Villager) -> bool:
	var cfg := ctx.config
	if v.sex == &"female":
		return v.age_years >= cfg.fertile_min_age and v.age_years <= cfg.fertile_max_age
	return v.age_years >= cfg.fertile_min_age and v.age_years <= cfg.elder_age + 5.0


## Everything a couple needs before a child can come. Returns "" if possible,
## otherwise the reason (shown in the inspector).
func conception_blocker(v: Villager) -> String:
	var cfg := ctx.config
	if v.sex != &"female" or not fertile(v):
		return "not able to bear children"
	if v.pregnancy_days >= 0.0:
		return "already expecting"
	var partner := ctx.social.get_villager(ctx.social.partner_of(v.villager_id))
	if partner == null:
		return "no partner"
	if partner.sex == v.sex or not fertile(partner):
		return "partner can't father children"
	if SimClock.get_day() - v.last_birth_day < cfg.birth_spacing_days:
		return "recovering from the last birth"
	if v.needs.health < 60.0 or partner.needs.health < 60.0 or v.needs.hunger > 65.0:
		return "not healthy or fed enough"
	if ctx.tribe.population() >= cfg.max_population:
		return "the tribe is at its limit"
	var home := v.home if v.home != null and is_instance_valid(v.home) else partner.home
	if home == null or not is_instance_valid(home) or not home.is_complete:
		return "no home of their own"
	if household_size(home) >= home.def.housing:
		return "the home is full"
	var stock := float(ctx.tribe.stockpile.get_amount(ResourceType.FOOD))
	if stock < FOOD_PER_PERSON_FOR_CHILDREN * ctx.tribe.population():
		return "the tribe's food stores are too low"
	return ""


func can_conceive(v: Villager) -> bool:
	return conception_blocker(v) == ""


## Daily chance: couples who are close, happy and want a family try more.
func conception_chance(v: Villager) -> float:
	var partner_id := ctx.social.partner_of(v.villager_id)
	var bond := (ctx.social.graph.affinity(v.villager_id, partner_id) + ctx.social.graph.affinity(partner_id, v.villager_id)) * 0.5
	var children := children_of(v.villager_id).size()
	var wish := 0.6 + 0.4 * (v.personality.get_trait(&"empathy") + v.personality.get_trait(&"sociability")) * 0.5
	var age_factor := 1.0 - clampf((v.age_years - 32.0) / 14.0, 0.0, 0.8)
	return ctx.config.conception_chance * clampf(bond + 0.3, 0.1, 1.2) * wish * age_factor / (1.0 + children * 0.35) \
			* society.culture.conception_factor(v) \
			* (1.0 + 0.4 * v.emotions.mood())


func conceive(mother: Villager) -> void:
	var father_id := ctx.social.partner_of(mother.villager_id)
	mother.pregnancy_days = 0.0
	mother.pregnancy_partner = father_id
	mother.emotions.feel(&"hope", 0.5, "Expecting a child", mother.personality)
	society.history.add(&"family", "%s is expecting a child with %s." % [mother.villager_name, ctx.social.name_of(father_id)],
			[mother.villager_id, father_id])


func give_birth(mother: Villager) -> Villager:
	var father := ctx.social.get_villager(mother.pregnancy_partner)
	var father_id := mother.pregnancy_partner
	mother.pregnancy_days = -1.0
	mother.pregnancy_partner = -1
	mother.last_birth_day = SimClock.get_day()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ctx.social.social_seed(), mother.villager_id, SimClock.tick_count, "birth"])
	var dad_p := father.personality if father != null else mother.personality
	var dad_s := father.skills if father != null else mother.skills
	var personality := Personality.inherit(mother.personality, dad_p, rng)
	var skills := VillagerSkills.inherit(mother.skills, dad_s, rng)
	var sex: StringName = &"female" if rng.randf() < 0.5 else &"male"
	var parents: Array[int] = [mother.villager_id]
	if father_id >= 0:
		parents.append(father_id)
	var child_name := society.culture.name_for_child(parents, rng, new_name(rng))
	_used_names[child_name] = true
	var child := ctx.tribe.add_villager(mother.global_position, 0.0, sex, personality, skills, parents, child_name)
	child.born_day = SimClock.get_day()
	if mother.home != null and is_instance_valid(mother.home):
		child.home = mother.home
	births += 1
	_link_family(child, parents)
	# Children know what their parents know about the land around them.
	for id in mother.knowledge.store.facts:
		child.knowledge.store.learn(id, mother.knowledge.store.facts[id], mother.villager_id)
	for pid in parents:
		var parent := ctx.social.get_villager(pid)
		if parent != null:
			ctx.social.remember(parent, &"child_born", -1, child.villager_id)
	for sib in siblings_of(child.villager_id):
		var s := ctx.social.get_villager(sib)
		if s != null:
			ctx.social.remember(s, &"sibling_born", -1, child.villager_id)
	society.history.add(&"birth", "%s was born to %s and %s." % [child.villager_name, mother.villager_name,
			ctx.social.name_of(father_id)], [child.villager_id, mother.villager_id, father_id])
	society.culture.on_birth(child, parents)
	EventBus.villager_born.emit(child)
	EventBus.notify("%s was born to %s and %s." % [child.villager_name, mother.villager_name, ctx.social.name_of(father_id)], &"social")
	return child


func _link_family(child: Villager, parents: Array[int]) -> void:
	var g := ctx.social.graph
	var cid := child.villager_id
	for pid in parents:
		g.set_tag(cid, pid, &"kin", true)
		g.set_opinion(pid, cid, 0.85, 0.8)
		g.set_opinion(cid, pid, 0.8, 0.85)
		g.add_familiarity(cid, pid, 1.0)
	for sib in siblings_of(cid):
		g.set_tag(cid, sib, &"kin", true)
		g.set_opinion(sib, cid, 0.45, 0.6)
		g.set_opinion(cid, sib, 0.5, 0.6)
		g.add_familiarity(cid, sib, 0.6)


func new_name(rng: RandomNumberGenerator) -> String:
	for attempt in 40:
		var n: String = SYLLABLES_A[rng.randi() % SYLLABLES_A.size()] + SYLLABLES_B[rng.randi() % SYLLABLES_B.size()]
		if rng.randf() < 0.3:
			n += SYLLABLES_B[rng.randi() % SYLLABLES_B.size()]
		if not _used_names.has(n):
			_used_names[n] = true
			return n
	return "Child%d" % rng.randi_range(100, 999)


# --------------------------------------------------------------------------
# Family queries (from parent ids, so they also work for the dead)
# --------------------------------------------------------------------------

var parents_by_child: Dictionary = {}  # child id -> [parent ids]


func record_parents(child_id: int, parents: Array[int]) -> void:
	if not parents.is_empty():
		var plain := []  # untyped, so saved and loaded data compare equal
		plain.append_array(parents)
		parents_by_child[child_id] = plain


func parents_of(id: int) -> Array:
	return parents_by_child.get(id, [])


func children_of(id: int) -> Array[int]:
	var out: Array[int] = []
	for cid in parents_by_child:
		if parents_by_child[cid].has(id):
			out.append(cid)
	return out


func siblings_of(id: int) -> Array[int]:
	var out: Array[int] = []
	var mine: Array = parents_of(id)
	if mine.is_empty():
		return out
	for cid in parents_by_child:
		if cid != id:
			for p in parents_by_child[cid]:
				if mine.has(p):
					out.append(cid)
					break
	return out


func household_size(home: Building) -> int:
	var n := 0
	for v in ctx.tribe.villagers:
		if v.home == home:
			n += 1
	return n


# --------------------------------------------------------------------------
# Growing up and growing old
# --------------------------------------------------------------------------

func _track_stage(v: Villager) -> void:
	var stage := v.life_stage()
	var prev = _stage.get(v.villager_id)
	_stage[v.villager_id] = stage
	if prev == null or prev == stage:
		return
	match stage:
		&"youth":
			ctx.social.remember(v, &"grew_up", -1, -1, -1, "a youth")
			society.history.add(&"life", "%s is no longer a child." % v.villager_name, [v.villager_id])
		&"adult":
			ctx.social.remember(v, &"grew_up", -1, -1, -1, "an adult")
			society.history.add(&"life", "%s has come of age." % v.villager_name, [v.villager_id])
			society.culture.on_came_of_age(v)
		&"elder":
			society.history.add(&"life", "%s is now one of the elders." % v.villager_name, [v.villager_id])


func _check_old_age(v: Villager, day_fraction: float) -> void:
	var over := v.age_years - ctx.config.elder_age
	if over <= 0.0:
		return
	var per_day := 0.12 * pow(over / 25.0, 2.0) * lerpf(1.4, 0.8, v.needs.health / 100.0)
	if society.rng.randf() < _chance(per_day, day_fraction):
		natural_deaths += 1
		v.die("old age")


func to_dict() -> Dictionary:
	var pbc := {}
	for cid in parents_by_child:
		pbc[str(cid)] = parents_by_child[cid]
	return {"births": births, "natural_deaths": natural_deaths, "parents": pbc, "names": _used_names.keys(),
		"stage": _stage.duplicate()}


func load_dict(d: Dictionary) -> void:
	births = int(d["births"])
	natural_deaths = int(d["natural_deaths"])
	parents_by_child.clear()
	for cid in d["parents"]:
		parents_by_child[int(cid)] = Array(d["parents"][cid]).map(func(x): return int(x))
	for n in d["names"]:
		_used_names[n] = true
	_stage.clear()
	for k in d["stage"]:
		_stage[int(k)] = StringName(d["stage"][k])
