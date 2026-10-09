class_name ConversationSystem
extends RefCounted
## Brings villagers together and decides what their conversations achieve.
##
## Every conversation has a purpose (an intent) chosen from the two people's
## actual situation: needs, emotions, relationship and history, family,
## occupation, knowledge, tribe problems, projects and politics. The result
## is decided up front by deterministic, seeded rules, shown as speech while
## they talk, and applied only after validation and only if neither of them
## was interrupted. Recently used topics between the same pair are avoided.

const PAIR_INTERVAL := 1.0
const TALK_RANGE := 6.0
const DURATION := 5.0
const ABANDON_AFTER := 12.0
## A topic used by the same pair within this many sim-seconds is unlikely to repeat.
const REPEAT_WINDOW := 150.0

const TONE := {
	&"talk": Color(1, 0.98, 0.9), &"warm": Color(0.75, 1.0, 0.75), &"romance": Color(1.0, 0.72, 0.85),
	&"argue": Color(1.0, 0.7, 0.45), &"fight": Color(1.0, 0.4, 0.35), &"civic": Color(0.7, 0.85, 1.0),
}

var social: SocialSystem
var active: Array[Dictionary] = []
## Vector2i(min,max) -> {topic: last sim time}
var _pair_topics: Dictionary = {}
var _timer := 0.0


func _init(s: SocialSystem) -> void:
	social = s


func tick(dt: float) -> void:
	for c in active.duplicate():
		_advance(c, dt)
	_timer -= dt
	if _timer <= 0.0:
		_timer = PAIR_INTERVAL
		_pair_up()


func is_talking(v: Villager) -> bool:
	return v.current_task is ConverseTask


func _available(v: Villager) -> bool:
	if v.is_dead or v.is_hidden():
		return false
	return v.current_task is SocializeTask or v.current_task is IdleTask


func _pair_up() -> void:
	var used := {}
	for a in social.ctx.tribe.villagers:
		if used.has(a) or not _available(a):
			continue
		var best: Villager = null
		var best_desire := -INF
		for b in social.ctx.tribe.villagers_near(a.global_position, TALK_RANGE):
			if b == a or used.has(b) or not _available(b):
				continue
			var desire := social.closeness(a.villager_id, b.villager_id) + social.graph.familiarity(a.villager_id, b.villager_id) * 0.3
			if desire > best_desire:
				best_desire = desire
				best = b
		if best == null:
			continue
		var soc := (a.personality.get_trait(&"sociability") + best.personality.get_trait(&"sociability")) * 0.5
		var p := 0.25 + 0.5 * soc
		if a.current_task is SocializeTask or best.current_task is SocializeTask:
			p += 0.35
		# Rivals avoid each other unless someone is spoiling for a fight.
		if social.graph.has_tag(a.villager_id, best.villager_id, &"rival") or social.graph.has_tag(a.villager_id, best.villager_id, &"enemy"):
			p *= maxf(a.personality.get_trait(&"aggressiveness"), best.personality.get_trait(&"aggressiveness"))
		if social.rng.randf() < p:
			used[a] = true
			used[best] = true
			start(a, best)


## Can `v` be pulled into a conversation right now? Never while eating,
## resting or already talking.
static func can_be_engaged(v: Villager) -> bool:
	if v == null or v.is_dead or v.is_hidden():
		return false
	var t := v.current_task
	return t == null or (t.is_interruptible() and not t is ConverseTask)


## Starts a conversation. With `forced_topic` the first villager is the speaker.
## Returns false (and changes nothing) if the other person can't be engaged.
func start(a: Villager, b: Villager, forced_topic: StringName = &"") -> bool:
	if not can_be_engaged(b):
		return false
	var speaker := a
	var listener := b
	if forced_topic == &"":
		if _initiative(b) > _initiative(a):
			speaker = b
			listener = a
	var outcome := decide(speaker, listener, forced_topic)
	var c := {"speaker": speaker, "listener": listener, "outcome": outcome, "elapsed": 0.0, "replied": false}
	c["task_s"] = ConverseTask.new(speaker, listener)
	c["task_l"] = ConverseTask.new(listener, speaker)
	c["task_s"].style = outcome.style
	c["task_l"].style = outcome.style
	# set_task ends each villager's previous task before the new one starts.
	speaker.set_task(c["task_s"])
	listener.set_task(c["task_l"])
	c["task_s"].start()
	c["task_l"].start()
	speaker.say(outcome.line_speaker, 3.5, TONE.get(outcome.style, Color.WHITE))
	active.append(c)
	var key := RelationshipGraph._bond_key(speaker.villager_id, listener.villager_id)
	if not _pair_topics.has(key):
		_pair_topics[key] = {}
	_pair_topics[key][outcome.topic] = SimClock.sim_time
	return true


func _initiative(v: Villager) -> float:
	return v.needs.social / 100.0 + v.personality.get_trait(&"sociability") + (0.6 if v.needs.is_hungry() else 0.0) \
			+ v.emotions.get_value(&"anger") * 0.5 + v.emotions.get_value(&"affection") * 0.3


func _advance(c: Dictionary, dt: float) -> void:
	# A participant who died may already have been freed.
	if not is_instance_valid(c["speaker"]) or not is_instance_valid(c["listener"]):
		_finish(c, false)
		return
	var s: Villager = c["speaker"]
	var l: Villager = c["listener"]
	var still_talking: bool = not s.is_dead and not l.is_dead \
			and s.current_task == c["task_s"] and l.current_task == c["task_l"]
	c["elapsed"] += dt
	if not still_talking or c["elapsed"] > ABANDON_AFTER:
		_finish(c, false)
		return
	if not c["replied"] and c["elapsed"] >= DURATION * 0.45:
		c["replied"] = true
		var o: ConversationOutcome = c["outcome"]
		l.say(o.line_listener, 3.5, TONE.get(o.style, Color.WHITE))
	if c["elapsed"] >= DURATION:
		_finish(c, true)


func _finish(c: Dictionary, completed: bool) -> void:
	active.erase(c)
	var outcome: ConversationOutcome = c["outcome"]
	if completed and outcome.validate(social):
		outcome.apply(social)
		social.stats.conversations += 1
		var topics: Dictionary = social.stats.topics
		topics[String(outcome.topic)] = int(topics.get(String(outcome.topic), 0)) + 1
		EventBus.conversation_finished.emit(outcome.to_dict())
	for key in ["task_s", "task_l"]:
		var t: ConverseTask = c[key]
		t.done = true


# --------------------------------------------------------------------------
# Choosing what to talk about
# --------------------------------------------------------------------------

func decide(s: Villager, l: Villager, forced_topic: StringName = &"") -> ConversationOutcome:
	var o := ConversationOutcome.new()
	o.speaker_id = s.villager_id
	o.listener_id = l.villager_id
	var data := {}
	var topic := forced_topic if forced_topic != &"" else _pick_topic(s, l, data)
	o.topic = topic
	var handler := "_resolve_" + String(topic)
	if has_method(handler):
		call(handler, o, s, l, data)
	elif social.ctx.society != null and social.ctx.society.culture.handles(topic):
		social.ctx.society.culture.resolve(topic, o, s, l, data, self)
	else:
		_resolve_small_talk(o, s, l, data)
	return o


## Weighs every intent that makes sense right now; picks one (seeded).
func _pick_topic(s: Villager, l: Villager, data: Dictionary) -> StringName:
	return _weighted(topic_weights(s, l, data), s.villager_id, l.villager_id)


## Every intent that makes sense for `s` to raise with `l` right now, with
## its weight (before the repetition penalty). `data` receives context.
func topic_weights(s: Villager, l: Villager, data: Dictionary = {}) -> Dictionary:
	var g := social.graph
	var sid := s.villager_id
	var lid := l.villager_id
	var ps := s.personality
	var em := s.emotions
	var w := {&"small_talk": 1.0}
	var romance := social.romance
	if s.is_child() or l.is_child():
		# Children chat, play and learn; adult affairs stay between adults.
		if g.is_kin(sid, lid):
			w[&"family_talk"] = 2.0
		var lesson_c := _best_lesson(s, l)
		if lesson_c != &"":
			data["skill"] = lesson_c
			w[&"teach"] = 1.0
		if l.emotions.get_value(&"grief") > 0.3:
			w[&"console"] = 1.5
		# Adults tell children the tribe's stories and teach them what matters.
		if social.ctx.society != null:
			social.ctx.society.culture.add_topics(s, l, w, data)
		return w

	if s.needs.is_hungry() and l.inventory.carried_type == ResourceType.FOOD and l.inventory.amount > 0:
		w[&"ask_food"] = 4.0
	var fact := _best_fact_to_share(s, l)
	if fact >= 0:
		data["fact"] = fact
		w[&"share_location"] = 0.5 + ps.get_trait(&"generosity")
	if l.emotions.get_value(&"grief") > 0.3 or l.emotions.get_value(&"sadness") > 0.5:
		w[&"console"] = 2.5 * ps.get_trait(&"empathy") + 0.5 * maxf(0.0, g.affinity(sid, lid))
	var rumor_subject := _gossip_subject(s, l)
	if rumor_subject >= 0:
		data["rumor_subject"] = rumor_subject
		w[&"rumor"] = 0.3 + 0.6 * ps.get_trait(&"sociability")
	var grudge := g.resentment(sid, lid)
	var aff := g.affinity(sid, lid)
	var anger := em.get_value(&"anger") + em.get_value(&"frustration") * 0.5
	if grudge > 0.3:
		w[&"accuse"] = (grudge + anger) * (0.5 + ps.get_trait(&"courage") * 0.6)
	var complaint_subject := _most_resented(s, lid)
	if complaint_subject >= 0:
		data["complaint_subject"] = complaint_subject
		w[&"complain"] = g.resentment(sid, complaint_subject) * (0.6 + anger)
	var hostility := maxf(0.0, ps.get_trait(&"aggressiveness") - 0.45) * (1.5 if em.mood() < -0.2 else 0.6) \
			+ maxf(0.0, -aff) * 1.5 + anger * ps.get_trait(&"aggressiveness") \
			+ maxf(0.0, 0.45 - ps.compatibility(l.personality)) * ps.get_trait(&"aggressiveness")
	# Affection takes the edge off: people rarely lash out at those they love.
	hostility *= 1.0 - 0.7 * maxf(0.0, aff)
	if hostility > 0.15:
		w[&"insult"] = hostility
	if (grudge > 0.15 or g.resentment(lid, sid) > 0.2) and aff > -0.4:
		w[&"reconcile"] = (ps.get_trait(&"empathy") + ps.get_trait(&"patience")) * 0.8 * (1.0 - anger)
	# Romance
	var partner := social.partner_of(sid)
	if partner == lid:
		w[&"couple_talk"] = 1.2 + 2.0 * maxf(g.resentment(sid, lid), g.resentment(lid, sid))
	elif romance.ready_to_propose(s, l):
		w[&"propose_partnership"] = 5.0
	elif romance.is_interested(s, l):
		# Flirting with someone already taken is rarer (and riskier).
		var taken := 1.0 if romance.is_single(lid) else 0.4
		w[&"flirt"] = (1.5 + romance.attraction(s, l) * 4.0 * lerpf(0.6, 1.4, ps.get_trait(&"courage"))) * taken
	# Family
	if g.is_kin(sid, lid):
		w[&"family_talk"] = 1.0
	# Teaching and working together
	var lesson := _best_lesson(s, l)
	if lesson != &"":
		data["skill"] = lesson
		w[&"teach"] = 0.5 + ps.get_trait(&"patience") * 0.6 + (0.8 if l.life_stage() == &"youth" else 0.0)
	if VillagerBrain.GATHER_GOALS.has(s.brain.last_work_goal) and l.work_capacity() > 0.0:
		w[&"coordinate_work"] = 0.3 + ps.get_trait(&"industriousness") * 0.5
	var my_site := _own_site(s)
	if my_site != null and l.is_adult():
		data["site"] = my_site
		w[&"ask_build_help"] = 1.5
	# Knowledge, projects and politics (from the society layer)
	social.ctx.society.add_topics(s, l, w, data)
	return w


func _weighted(w: Dictionary, sid: int, lid: int) -> StringName:
	# Don't keep having the same conversation.
	var recent: Dictionary = _pair_topics.get(RelationshipGraph._bond_key(sid, lid), {})
	for t in w:
		if recent.has(t) and SimClock.sim_time - float(recent[t]) < REPEAT_WINDOW:
			w[t] *= 0.2
	var total := 0.0
	for k in w:
		total += w[k]
	var roll := social.rng.randf() * total
	for k in w:
		roll -= w[k]
		if roll <= 0.0:
			return k
	return &"small_talk"


func _lines(o: ConversationOutcome, key: StringName, s: Villager, l: Villager, extra: Dictionary = {}) -> void:
	var values := {"speaker": s.villager_name, "listener": l.villager_name}
	values.merge(extra)
	var pair := DialogueRenderer.render(key, social.rng, values)
	o.line_speaker = pair[0]
	o.line_listener = pair[1]


# --------------------------------------------------------------------------
# Everyday talk
# --------------------------------------------------------------------------

func _resolve_small_talk(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var soc := (s.personality.get_trait(&"sociability") + l.personality.get_trait(&"sociability")) * 0.5
	# Kindred temperaments and shared beliefs both make conversation easy.
	var compat := s.personality.compatibility(l.personality) + (social.ctx.society.culture.similarity(s, l) - 0.5) * 0.3
	var p := clampf(0.15 + 0.3 * soc + 0.5 * compat + 0.3 * social.graph.affinity(l.villager_id, s.villager_id), 0.05, 0.97)
	o.success = social.rng.randf() < p
	# Kindred spirits warm to each other faster; clashing temperaments cool.
	var shift := (compat - 0.45) * 0.12
	o.opinion_shifts.append([s.villager_id, l.villager_id, "affinity", shift])
	o.opinion_shifts.append([l.villager_id, s.villager_id, "affinity", shift])
	var kind := &"chatted" if o.success else &"awkward_talk"
	o.add_memory(s.villager_id, kind, l.villager_id)
	o.add_memory(l.villager_id, kind, s.villager_id)
	o.style = &"talk" if o.success else &"argue"
	_lines(o, &"small_talk" if o.success else &"small_talk_fail", s, l, DialogueRenderer.context_for(social, s, l))


func _best_fact_to_share(s: Villager, l: Villager) -> int:
	var types := ResourceType.ALL.duplicate()
	types.sort_custom(func(a, b): return social.ctx.tribe.get_demand(a) > social.ctx.tribe.get_demand(b))
	for t in types:
		var id := s.knowledge.shareable_fact(t, l.knowledge)
		if id >= 0:
			return id
	return -1


func _resolve_share_location(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var id: int = data.get("fact", _best_fact_to_share(s, l))
	if id < 0:
		_resolve_small_talk(o, s, l, data)
		return
	var fact: Dictionary = s.knowledge.store.get_fact(id)
	var res := ResourceType.display_name(int(fact["type"])).to_lower()
	var where := DialogueRenderer.direction_words(social.ctx.tribe.center, fact["pos"])
	var believe := social.rng.randf() < 0.3 + 0.7 * social.graph.trust(l.villager_id, s.villager_id)
	o.success = believe
	o.add_memory(s.villager_id, &"taught_location", l.villager_id, -1, res)
	if believe:
		o.facts_to_listener[id] = fact.duplicate()
		o.add_memory(l.villager_id, &"learned_location", s.villager_id, -1, res)
	else:
		o.add_memory(l.villager_id, &"doubted", s.villager_id, -1, res)
	_lines(o, &"share_location" if believe else &"share_location_doubt", s, l, {"res": res, "where": where})


func _resolve_family_talk(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var parent_child := social.ctx.society.demographics.parents_of(l.villager_id).has(s.villager_id)
	o.style = &"warm"
	o.add_memory(s.villager_id, &"chatted", l.villager_id)
	o.add_memory(l.villager_id, &"chatted", s.villager_id)
	o.opinion_shifts.append([l.villager_id, s.villager_id, "affinity", 0.04])
	var lesson := _best_lesson(s, l)
	if parent_child and lesson != &"":
		# Parents pass on what they know.
		o.teaching.append([s.villager_id, l.villager_id, lesson, 0.05])
		_lines(o, &"parent_advice", s, l, {"skill": String(lesson)})
		return
	_lines(o, &"family", s, l, DialogueRenderer.context_for(social, s, l))


# --------------------------------------------------------------------------
# Help
# --------------------------------------------------------------------------

func _resolve_ask_food(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var pl := l.personality
	var bond := 0.0
	if social.graph.has_tag(l.villager_id, s.villager_id, &"partner") or social.graph.is_kin(l.villager_id, s.villager_id):
		bond = 0.35
	var custom := social.ctx.society.culture.sharing_bonus()
	var p := 0.15 + 0.45 * pl.get_trait(&"generosity") + 0.25 * pl.get_trait(&"empathy") + custom \
			+ 0.3 * social.graph.affinity(l.villager_id, s.villager_id) + bond - (0.35 if l.needs.is_hungry() else 0.0) \
			+ 0.2 * l.emotions.get_value(&"gratitude")
	o.success = social.rng.randf() < clampf(p, 0.02, 0.98) and l.inventory.amount > 0
	if o.success:
		o.style = &"warm"
		o.food_giver = l.villager_id
		o.food_receiver = s.villager_id
		o.food_amount = clampi(s.needs.food_wanted(), 1, maxi(1, mini(3, l.inventory.amount)))
		o.add_memory(s.villager_id, &"was_helped", l.villager_id)
		o.add_memory(l.villager_id, &"helped", s.villager_id)
	else:
		social.stats.help_refused += 1
		o.add_memory(s.villager_id, &"was_refused", l.villager_id)
		o.add_memory(l.villager_id, &"refused", s.villager_id)
	_lines(o, &"ask_food" if o.success else &"ask_food_refused", s, l)


func _resolve_offer_food(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	o.style = &"warm"
	o.food_giver = s.villager_id
	o.food_receiver = l.villager_id
	o.food_amount = clampi(l.needs.food_wanted(), 1, maxi(1, mini(3, s.inventory.amount)))
	o.add_memory(l.villager_id, &"was_helped", s.villager_id)
	o.add_memory(s.villager_id, &"helped", l.villager_id)
	_lines(o, &"offer_food", s, l)


func _grief_subject(v: Villager) -> int:
	for r in v.memory.notable(6):
		if r.kind in [&"lost_partner", &"lost_family", &"lost_friend", &"lost_child", &"saw_death"]:
			return r.subject_id
	return -1


func _resolve_console(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var subject := _grief_subject(l)
	var p := clampf(0.55 + 0.5 * social.graph.affinity(l.villager_id, s.villager_id), 0.1, 0.97)
	o.success = social.rng.randf() < p
	o.style = &"warm"
	if o.success:
		o.add_memory(l.villager_id, &"was_comforted", s.villager_id, subject)
		o.add_memory(s.villager_id, &"comforted", l.villager_id, subject)
	else:
		o.add_memory(s.villager_id, &"awkward_talk", l.villager_id)
	if subject < 0:
		_lines(o, &"cheer_up" if o.success else &"console_fail", s, l)
	else:
		_lines(o, &"console" if o.success else &"console_fail", s, l, {"subject": social.name_of(subject)})


## Ask someone to keep a promise of help with your own home.
func _own_site(v: Villager) -> Building:
	for b in social.ctx.tribe.buildings:
		if b.is_construction_site() and b.owner_ids.has(v.villager_id):
			return b
	return null


func _resolve_ask_build_help(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var site: Building = data["site"]
	var p := 0.25 + 0.4 * maxf(0.0, social.graph.affinity(l.villager_id, s.villager_id)) \
			+ 0.25 * l.personality.get_trait(&"generosity") + 0.15 * l.personality.get_trait(&"loyalty")
	o.success = social.rng.randf() < clampf(p, 0.05, 0.95)
	o.style = &"civic"
	if o.success:
		var honest := l.personality.get_trait(&"honesty")
		o.promises.append([l.villager_id, s.villager_id, &"help_build", site.entity_id, 2.0, "help build their home"])
		# Honest people mean it; others are more likely to forget.
		o.suggestions.append([l.villager_id, &"build", 0.25 * lerpf(0.4, 1.2, honest), 160.0, "Promised %s help with their home" % s.villager_name])
		_lines(o, &"ask_build_help", s, l)
	else:
		o.add_memory(s.villager_id, &"was_refused", l.villager_id)
		_lines(o, &"ask_build_help_no", s, l)


# --------------------------------------------------------------------------
# Rumours and complaints
# --------------------------------------------------------------------------

## A living third villager the speaker feels strongly about and the listener knows.
func _gossip_subject(s: Villager, l: Villager) -> int:
	var best := -1
	var best_strength := 0.35
	for other in social.graph.known_by(s.villager_id):
		if other == l.villager_id or not social.is_alive(other):
			continue
		var strength := absf(social.graph.affinity(s.villager_id, other))
		if strength > best_strength and social.graph.familiarity(l.villager_id, other) > 0.0:
			best_strength = strength
			best = other
	return best


func _resolve_rumor(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var subject: int = data.get("rumor_subject", _gossip_subject(s, l))
	if subject < 0:
		_resolve_small_talk(o, s, l, data)
		return
	var g := social.graph
	var opinion := g.affinity(s.villager_id, subject)
	# Deceitful people exaggerate; the rumour may not match what happened.
	var distortion := (1.0 - s.personality.get_trait(&"honesty")) * 0.5
	var told := clampf(opinion - distortion if opinion < 0.0 else opinion + distortion * 0.3, -1.0, 1.0)
	# How much the listener believes depends on trust in the speaker versus
	# their own view of the subject. Suspicious listeners shrug rumours off.
	var credibility := g.trust(l.villager_id, s.villager_id) * l.personality.get_trait(&"trust") * 1.6
	var own := g.affinity(l.villager_id, subject)
	var believed := social.rng.randf() < clampf(credibility - absf(own - told) * 0.3, 0.05, 0.95)
	o.style = &"talk"
	o.add_memory(s.villager_id, &"chatted", l.villager_id)
	var name := social.name_of(subject)
	if believed:
		o.opinion_shifts.append([l.villager_id, subject, "affinity", told * 0.25])
		o.opinion_shifts.append([l.villager_id, subject, "trust", told * 0.1])
		o.add_memory(l.villager_id, &"heard_rumor", s.villager_id, subject, "is a good soul" if told > 0.0 else "can't be trusted")
		_lines(o, &"rumor_good" if told > 0.0 else &"rumor_bad", s, l, {"subject": name})
	else:
		o.success = false
		o.opinion_shifts.append([l.villager_id, s.villager_id, "trust", -0.04])
		o.add_memory(l.villager_id, &"disagreed", s.villager_id, subject, "what they said about %s" % name)
		_lines(o, &"rumor_doubted", s, l, {"subject": name})


## Who the speaker resents most (not the listener).
func _most_resented(s: Villager, exclude: int) -> int:
	var best := -1
	var best_v := 0.3
	for other in social.graph.known_by(s.villager_id):
		if other == exclude or not social.is_alive(other):
			continue
		var r := social.graph.resentment(s.villager_id, other)
		if r > best_v:
			best_v = r
			best = other
	return best


func _resolve_complain(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var subject: int = data.get("complaint_subject", -1)
	if subject < 0:
		_resolve_small_talk(o, s, l, data)
		return
	var reason := _grievance(s, subject)
	var sympathy := social.graph.affinity(l.villager_id, s.villager_id) - social.graph.affinity(l.villager_id, subject)
	o.success = social.rng.randf() < clampf(0.4 + sympathy * 0.6, 0.05, 0.95)
	o.style = &"argue"
	o.add_memory(s.villager_id, &"complained", l.villager_id, subject, reason)
	if o.success:
		o.opinion_shifts.append([l.villager_id, subject, "affinity", -0.08])
		o.opinion_shifts.append([l.villager_id, s.villager_id, "affinity", 0.04])
		_lines(o, &"complain_agree", s, l, {"subject": social.name_of(subject), "reason": reason})
	else:
		o.opinion_shifts.append([l.villager_id, s.villager_id, "affinity", -0.03])
		_lines(o, &"complain_defend", s, l, {"subject": social.name_of(subject), "reason": reason})


## The worst thing `s` remembers about `other`, as a short phrase.
func _grievance(s: Villager, other: int) -> String:
	var worst: MemoryRecord = null
	for r in s.memory.about(other):
		if worst == null or r.valence < worst.valence:
			worst = r
	if worst == null:
		return "the way they act"
	match worst.kind:
		&"misled": return "sending me on a fool's errand"
		&"was_refused": return "refusing to help me"
		&"was_insulted", &"humiliated": return "insulting me"
		&"fought": return "attacking me"
		&"jealous_of", &"partner_unfaithful": return "chasing my partner"
		&"accused": return "accusing me unfairly"
		&"vetoed": return "blocking my plans"
		&"heard_rumor": return "what everyone says about them"
	return "how they treated me"


# --------------------------------------------------------------------------
# Conflict and reconciliation
# --------------------------------------------------------------------------

func _resolve_insult(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	o.success = true
	o.loneliness_relief = 5.0
	if _escalates(s, l):
		_fight(o, s, l, "a quarrel that got out of hand")
		return
	var pl := l.personality
	var retaliate := social.rng.randf() < pl.get_trait(&"aggressiveness") * 0.6 + pl.get_trait(&"courage") * 0.3
	if retaliate:
		o.style = &"argue"
		o.add_memory(s.villager_id, &"argued", l.villager_id, -1, "nothing much")
		o.add_memory(l.villager_id, &"argued", s.villager_id, -1, "nothing much")
		_lines(o, &"argue", s, l)
	else:
		o.style = &"argue"
		var crowd := social.ctx.tribe.villagers_near(s.global_position, 8.0).size() > 3
		o.add_memory(l.villager_id, &"humiliated" if crowd else &"was_insulted", s.villager_id)
		o.add_memory(s.villager_id, &"insulted", l.villager_id)
		_lines(o, &"insult", s, l)


func _resolve_accuse(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var reason := _grievance(s, l.villager_id)
	o.loneliness_relief = 5.0
	o.add_memory(s.villager_id, &"accused_someone", l.villager_id, -1, reason)
	# An honest, patient listener may own up; a proud or hot-headed one won't.
	var pl := l.personality
	var apologize := social.rng.randf() < clampf(pl.get_trait(&"honesty") * 0.5 + pl.get_trait(&"empathy") * 0.3
			+ pl.get_trait(&"patience") * 0.2 - pl.get_trait(&"status_desire") * 0.3, 0.02, 0.9)
	if apologize:
		o.style = &"warm"
		o.add_memory(s.villager_id, &"reconciled", l.villager_id)
		o.add_memory(l.villager_id, &"reconciled", s.villager_id)
		o.history.append([&"dispute", "%s confronted %s about %s; they made peace." % [s.villager_name, l.villager_name, reason],
				[s.villager_id, l.villager_id]])
		_lines(o, &"accuse_apology", s, l, {"reason": reason})
		return
	o.add_memory(l.villager_id, &"accused", s.villager_id, -1, reason)
	if _escalates(s, l):
		_fight(o, s, l, reason)
		return
	o.style = &"argue"
	o.add_memory(s.villager_id, &"argued", l.villager_id, -1, reason)
	o.add_memory(l.villager_id, &"argued", s.villager_id, -1, reason)
	o.history.append([&"dispute", "%s accused %s of %s." % [s.villager_name, l.villager_name, reason], [s.villager_id, l.villager_id]])
	_lines(o, &"accuse_deny", s, l, {"reason": reason})


## Do tempers flare into a physical fight? Needs anger, nerve and little patience on both sides.
func _escalates(s: Villager, l: Villager) -> bool:
	var heat := 0.0
	for v in [s, l]:
		var p: Personality = v.personality
		heat += v.emotions.get_value(&"anger") * p.get_trait(&"aggressiveness") * (1.2 - p.get_trait(&"patience")) \
				* (0.5 + p.get_trait(&"courage") * 0.5)
	heat -= social.ctx.society.culture.peace_norm() * 0.3
	return social.rng.randf() < clampf(heat - 0.15, 0.0, 0.6)


func _fight(o: ConversationOutcome, s: Villager, l: Villager, reason: String) -> void:
	o.style = &"fight"
	o.injuries[s.villager_id] = social.rng.randf_range(6.0, 18.0)
	o.injuries[l.villager_id] = social.rng.randf_range(6.0, 18.0)
	o.add_memory(s.villager_id, &"fought", l.villager_id)
	o.add_memory(l.villager_id, &"fought", s.villager_id)
	o.witnesses_fight = true
	social.ctx.society.politics.record_dispute(s.villager_id, l.villager_id, reason)
	o.history.append([&"dispute", "%s and %s came to blows over %s." % [s.villager_name, l.villager_name, reason],
			[s.villager_id, l.villager_id]])
	_lines(o, &"fight", s, l)


func _resolve_reconcile(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var pl := l.personality
	var g := social.graph
	var p := 0.25 + 0.35 * pl.get_trait(&"empathy") + 0.25 * pl.get_trait(&"patience") + 0.25 * g.trust(l.villager_id, s.villager_id) \
			- 0.5 * g.resentment(l.villager_id, s.villager_id)
	o.success = social.rng.randf() < clampf(p, 0.05, 0.9)
	if o.success:
		o.style = &"warm"
		o.add_memory(s.villager_id, &"reconciled", l.villager_id)
		o.add_memory(l.villager_id, &"reconciled", s.villager_id)
		o.tags.append([s.villager_id, l.villager_id, &"rival", false])
		# Only real feuds make the chronicle.
		if maxf(g.resentment(s.villager_id, l.villager_id), g.resentment(l.villager_id, s.villager_id)) > 0.45:
			o.history.append([&"dispute", "%s and %s settled their differences." % [s.villager_name, l.villager_name],
					[s.villager_id, l.villager_id]])
		_lines(o, &"reconcile", s, l)
	else:
		o.style = &"argue"
		o.add_memory(s.villager_id, &"ignored", l.villager_id)
		_lines(o, &"reconcile_no", s, l)


# --------------------------------------------------------------------------
# Romance
# --------------------------------------------------------------------------

func _resolve_flirt(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var romance := social.romance
	o.success = social.rng.randf() < romance.flirt_reception(s, l)
	o.style = &"romance"
	if o.success:
		o.add_memory(s.villager_id, &"flirted", l.villager_id)
		o.add_memory(l.villager_id, &"flirted", s.villager_id)
		o.opinion_shifts.append([l.villager_id, s.villager_id, "affinity", 0.05])
		o.flirt = [s.villager_id, l.villager_id]
		_lines(o, &"flirt", s, l, DialogueRenderer.context_for(social, s, l))
	else:
		o.add_memory(s.villager_id, &"rejected", l.villager_id)
		o.opinion_shifts.append([s.villager_id, l.villager_id, "attraction", -0.05])
		_lines(o, &"flirt_rejected", s, l)


func _resolve_propose_partnership(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	o.style = &"romance"
	if social.romance.accepts_partnership(s, l):
		o.couple = [s.villager_id, l.villager_id]
		_lines(o, &"propose_yes", s, l)
	else:
		o.success = false
		o.add_memory(s.villager_id, &"proposal_refused", l.villager_id)
		o.tags.append([s.villager_id, l.villager_id, &"courting", false])
		o.history.append([&"romance", "%s asked %s to be partners, but was refused." % [s.villager_name, l.villager_name],
				[s.villager_id, l.villager_id]])
		_lines(o, &"propose_no", s, l)


## Partners talk about their life together - and sometimes fight about it.
func _resolve_couple_talk(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var g := social.graph
	var tension := maxf(g.resentment(s.villager_id, l.villager_id), g.resentment(l.villager_id, s.villager_id))
	if tension < 0.2:
		o.style = &"romance"
		o.add_memory(s.villager_id, &"flirted", l.villager_id)
		o.add_memory(l.villager_id, &"flirted", s.villager_id)
		_lines(o, &"couple_warm", s, l, DialogueRenderer.context_for(social, s, l))
		return
	var topic := _grievance(s, l.villager_id)
	var mend := (s.personality.get_trait(&"patience") + l.personality.get_trait(&"empathy")) * 0.5 - tension * 0.5
	if social.rng.randf() < clampf(mend + 0.2, 0.05, 0.9):
		o.style = &"warm"
		o.add_memory(s.villager_id, &"reconciled", l.villager_id)
		o.add_memory(l.villager_id, &"reconciled", s.villager_id)
		_lines(o, &"couple_mend", s, l, {"reason": topic})
	else:
		o.style = &"argue"
		o.add_memory(s.villager_id, &"argued", l.villager_id, -1, topic)
		o.add_memory(l.villager_id, &"argued", s.villager_id, -1, topic)
		if tension > 0.6 and social.rng.randf() < 0.4:
			o.breakup = [s.villager_id, l.villager_id, "a bitter argument about %s" % topic]
			_lines(o, &"couple_breakup", s, l, {"reason": topic})
		else:
			_lines(o, &"couple_argue", s, l, {"reason": topic})


# --------------------------------------------------------------------------
# Teaching and work
# --------------------------------------------------------------------------

## A skill `s` could usefully teach `l`, or &"".
func _best_lesson(s: Villager, l: Villager) -> StringName:
	if not s.is_adult() or l.life_stage() == &"child" and s.villager_id not in social.ctx.society.demographics.parents_of(l.villager_id):
		return &""
	var best: StringName = &""
	var best_gap := 15.0
	for k in VillagerSkills.LIST:
		var gap := s.skills.get_level(k) - l.skills.get_level(k)
		if s.skills.get_level(k) >= 25.0 and gap > best_gap:
			best_gap = gap
			best = k
	return best


func _resolve_teach(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var skill: StringName = data.get("skill", _best_lesson(s, l))
	if skill == &"":
		_resolve_small_talk(o, s, l, data)
		return
	var willing := 0.4 + 0.4 * l.personality.get_trait(&"curiosity") + 0.3 * maxf(0.0, social.graph.respect(l.villager_id, s.villager_id))
	o.success = social.rng.randf() < clampf(willing, 0.1, 0.95)
	o.style = &"civic"
	if not o.success:
		o.add_memory(s.villager_id, &"ignored", l.villager_id)
		_lines(o, &"teach_no", s, l, {"skill": String(skill)})
		return
	var strength := 0.06 * lerpf(0.7, 1.4, s.personality.get_trait(&"patience")) * social.ctx.society.culture.learning_bonus(l, s)
	o.teaching.append([s.villager_id, l.villager_id, skill, strength])
	o.add_memory(s.villager_id, &"taught", l.villager_id, -1, String(skill))
	o.add_memory(l.villager_id, &"was_taught", s.villager_id, -1, String(skill))
	# Repeated lessons make a mentor.
	if social.graph.familiarity(s.villager_id, l.villager_id) > 0.5 and s.skills.get_level(skill) >= 45.0:
		o.tags.append([s.villager_id, l.villager_id, &"mentor", true])
	_lines(o, &"teach", s, l, {"skill": String(skill)})


func _resolve_coordinate_work(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var goal := s.brain.last_work_goal
	var res := ResourceType.display_name(VillagerBrain.GATHER_GOALS.get(goal, ResourceType.WOOD)).to_lower()
	var p := 0.3 + 0.4 * maxf(0.0, social.graph.affinity(l.villager_id, s.villager_id)) + 0.3 * l.personality.get_trait(&"industriousness")
	o.success = social.rng.randf() < clampf(p, 0.05, 0.95)
	o.style = &"civic"
	o.add_memory(s.villager_id, &"chatted", l.villager_id)
	if o.success:
		o.suggestions.append([l.villager_id, goal, 0.3, 120.0, "%s asked for help gathering %s" % [s.villager_name, res]])
		o.add_memory(l.villager_id, &"worked_together", s.villager_id)
		_lines(o, &"coordinate", s, l, {"res": res})
	else:
		_lines(o, &"coordinate_no", s, l, {"res": res})


# --------------------------------------------------------------------------
# Knowledge, projects, problems and politics (society layer)
# --------------------------------------------------------------------------

func _resolve_share_discovery(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var tech: StringName = data.get("tech", social.ctx.society.tech.teachable(s, l))
	if tech == &"":
		_resolve_small_talk(o, s, l, data)
		return
	var label: String = TechSystem.TECHS[tech]["label"]
	var open := 0.35 + 0.4 * l.personality.get_trait(&"curiosity") + 0.3 * social.graph.trust(l.villager_id, s.villager_id) \
			- 0.25 * social.ctx.society.culture.norm(&"tradition")
	o.success = social.rng.randf() < clampf(open, 0.05, 0.95)
	o.style = &"civic"
	o.add_memory(s.villager_id, &"chatted", l.villager_id)
	if o.success:
		o.tech_shared.append([s.villager_id, l.villager_id, tech])
		_lines(o, &"discovery", s, l, {"tech": label})
	else:
		o.add_memory(l.villager_id, &"disagreed", s.villager_id, -1, label)
		_lines(o, &"discovery_doubt", s, l, {"tech": label})


func _resolve_discuss_proposal(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var props := social.ctx.society.proposals
	var pid: int = data.get("proposal", props.advocacy(s).get("id", -1))
	if not props.proposals.has(pid):
		_resolve_small_talk(o, s, l, data)
		return
	var p: Dictionary = props.proposals[pid]
	var label := props.label_of(p)
	var view: Array = props.evaluate(l, p)
	# Persuasive, trusted speakers move people.
	var pull := s.skills.get_level(&"persuasion") / 100.0 * 0.3 + social.graph.trust(l.villager_id, s.villager_id) * 0.2 - 0.1
	var lean: float = view[0] + pull + social.rng.randf_range(-0.15, 0.15)
	o.style = &"civic"
	o.practice.append([s.villager_id, &"persuasion", 4.0])
	var values := {"project": label, "why": p["reason"]}
	if lean > 0.15:
		o.stances.append([pid, l.villager_id, 1])
		o.add_memory(l.villager_id, &"persuaded", s.villager_id, -1, label)
		_lines(o, &"proposal_support", s, l, values)
	elif lean < -0.15:
		o.success = false
		o.stances.append([pid, l.villager_id, -1])
		o.add_memory(l.villager_id, &"disagreed", s.villager_id, -1, label)
		o.add_memory(s.villager_id, &"disagreed", l.villager_id, -1, label)
		values["counter"] = _counter_argument(l, p)
		_lines(o, &"proposal_oppose", s, l, values)
	else:
		_lines(o, &"proposal_undecided", s, l, values)


func _counter_argument(l: Villager, p: Dictionary) -> String:
	var g := social.graph
	if g.has_tag(l.villager_id, p["proposer"], &"rival") or g.affinity(l.villager_id, p["proposer"]) < -0.2:
		return "Not if it's %s's idea." % social.name_of(p["proposer"])
	if p["kind"] == "building":
		var def := BuildingCatalog.get_def(StringName(p["type"]))
		for k in def.costs:
			if social.ctx.tribe.stockpile.get_amount(k) < def.costs[k]:
				return "We can't spare the %s." % ResourceType.display_name(k).to_lower()
	if social.ctx.tribe.stockpile.get_amount(ResourceType.FOOD) < social.ctx.tribe.population() * 4:
		return "Food comes first."
	return "I don't see the point."


## Food is short: what should be done? The answer depends on what these two
## know, what they do for a living and whom they blame.
func _resolve_problem_food(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var society := social.ctx.society
	o.style = &"civic"
	var plan := ""
	if society.tech.knows(s, &"agriculture") or society.tech.knows(l, &"agriculture"):
		var existing := society.proposals.open_proposal_for(&"farm")
		if existing.is_empty():
			plan = "We should plant a field. I'll put it to the others."
			var proposer := s if society.tech.knows(s, &"agriculture") else l
			society.proposals._new_proposal(proposer, &"farm", "building", "Food is short; fields would feed us.")
		else:
			plan = "The farm %s proposed is our best hope." % social.name_of(existing["proposer"])
			o.stances.append([existing["id"], l.villager_id, 1])
	elif society.tech.knows(s, &"fishing") or society.tech.knows(l, &"fishing"):
		plan = "There are fish in the lake. Let's go."
		o.suggestions.append([s.villager_id, &"fish", 0.3, 200.0, "Agreed with %s to fish" % l.villager_name])
		o.suggestions.append([l.villager_id, &"fish", 0.3, 200.0, "Agreed with %s to fish" % s.villager_name])
	else:
		# Someone to blame: the person they resent most, if anyone.
		var blame := _most_resented(l, s.villager_id)
		if blame >= 0 and l.personality.get_trait(&"trust") < 0.5:
			plan = "If %s didn't eat so much, we'd have enough." % social.name_of(blame)
			o.opinion_shifts.append([s.villager_id, blame, "affinity", -0.08 * social.graph.trust(s.villager_id, l.villager_id)])
			o.add_memory(s.villager_id, &"heard_rumor", l.villager_id, blame, "is hoarding food")
		else:
			plan = "Let's gather berries together, right now."
			o.suggestions.append([s.villager_id, &"gather_food", 0.35, 200.0, "Agreed with %s to gather food" % l.villager_name])
			o.suggestions.append([l.villager_id, &"gather_food", 0.35, 200.0, "Agreed with %s to gather food" % s.villager_name])
	o.add_memory(s.villager_id, &"chatted", l.villager_id)
	o.add_memory(l.villager_id, &"chatted", s.villager_id)
	_lines(o, &"problem_food", s, l, {"plan": plan})


func _resolve_endorse(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var politics := social.ctx.society.politics
	var cand_id: int = data.get("candidate", s.villager_id)
	var cand := social.get_villager(cand_id)
	if cand == null:
		_resolve_small_talk(o, s, l, data)
		return
	var g := social.graph
	var lean := g.affinity(l.villager_id, cand_id) * 0.6 + g.respect(l.villager_id, cand_id) * 0.5 \
			+ (g.trust(l.villager_id, cand_id) - 0.5) + politics.influence(cand) * 0.004 \
			+ social.ctx.society.groups.alignment(l.villager_id, cand_id) * 0.3 + l.personality.get_trait(&"loyalty") * 0.1 - 0.35
	var current: int = politics.endorsements.get(l.villager_id, -1)
	if current >= 0:
		lean -= 0.25 * l.personality.get_trait(&"loyalty")  # loyal people stick with their choice
	o.style = &"civic"
	if social.rng.randf() < clampf(lean + 0.4, 0.03, 0.95):
		o.endorsements.append([l.villager_id, cand_id])
		o.add_memory(l.villager_id, &"endorsed", cand_id)
		_lines(o, &"endorse", s, l, {"candidate": cand.villager_name})
	else:
		o.success = false
		o.add_memory(s.villager_id, &"disagreed", l.villager_id, -1, "leadership")
		_lines(o, &"endorse_no", s, l, {"candidate": cand.villager_name})


func _resolve_trade(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var economy := social.ctx.society.economy
	o.style = &"civic"
	if economy.would_gift(l, s):
		o.success = economy.give_tool(l, s, false)
		o.add_memory(s.villager_id, &"got_tool", l.villager_id)
		o.add_memory(l.villager_id, &"helped", s.villager_id)
		_lines(o, &"trade", s, l, {"price": "a smile and", "res": "thanks"})
		return
	var price := EconomySystem.TRADE_PRICE
	var goods := s.inventory.carried_type
	if goods != ResourceType.NONE and goods != ResourceType.TOOLS and s.inventory.amount >= price:
		var res := ResourceType.display_name(goods).to_lower()
		if economy.give_tool(l, s, true):
			# Payment is real goods from the buyer's hands, handed in to the
			# store on the maker's behalf.
			s.inventory.remove(price)
			social.ctx.tribe.stockpile.add(goods, price)
			o.add_memory(s.villager_id, &"traded", l.villager_id, -1, "%d %s for a tool" % [price, res])
			o.add_memory(l.villager_id, &"traded", s.villager_id, -1, "a tool for %d %s" % [price, res])
			_lines(o, &"trade", s, l, {"price": str(price), "res": res})
			return
	o.success = false
	o.add_memory(s.villager_id, &"was_refused", l.villager_id)
	_lines(o, &"trade_no", s, l, {"price": str(price), "res": "goods"})


func _resolve_mediate(o: ConversationOutcome, s: Villager, l: Villager, _data: Dictionary) -> void:
	var society := social.ctx.society
	var d: Dictionary = society.pending_mediation.get(s.villager_id, {})
	society.pending_mediation.erase(s.villager_id)
	var other_id: int = d.get("b", -1) if d.get("a", -1) == l.villager_id else d.get("a", -1)
	o.style = &"civic"
	if other_id < 0:
		_resolve_small_talk(o, s, l, _data)
		return
	var g := social.graph
	var p := 0.25 + 0.4 * g.respect(l.villager_id, s.villager_id) + 0.3 * g.trust(l.villager_id, s.villager_id) \
			+ 0.2 * l.personality.get_trait(&"patience") - 0.4 * g.resentment(l.villager_id, other_id)
	o.success = social.rng.randf() < clampf(p, 0.05, 0.9)
	if o.success:
		o.opinion_shifts.append([l.villager_id, other_id, "resentment", -0.35])
		o.opinion_shifts.append([other_id, l.villager_id, "resentment", -0.2])
		o.add_memory(l.villager_id, &"mediated", s.villager_id, other_id)
		o.tags.append([l.villager_id, other_id, &"rival", false])
		o.history.append([&"dispute", "%s settled the feud between %s and %s." % [s.villager_name, l.villager_name,
				social.name_of(other_id)], [s.villager_id, l.villager_id, other_id]])
		social.ctx.society.politics.add_prestige(s, 3.0)
		_lines(o, &"mediate", s, l, {"subject": social.name_of(other_id)})
	else:
		o.add_memory(s.villager_id, &"ignored", l.villager_id)
		_lines(o, &"mediate_no", s, l, {"subject": social.name_of(other_id)})
