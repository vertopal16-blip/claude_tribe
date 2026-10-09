class_name ConversationSystem
extends RefCounted
## Brings villagers together and decides what their conversations achieve.
##
## Pairs form among villagers who are idle or looking for company and stand
## close together. The topic and result depend on both personalities, their
## relationship, needs, mood and what each of them actually knows. The outcome
## is decided up front, shown as speech while they talk, and applied (after
## validation) only if neither of them is interrupted.

const PAIR_INTERVAL := 1.0
const TALK_RANGE := 6.0
const DURATION := 5.0
const ABANDON_AFTER := 12.0

var social: SocialSystem
var active: Array[Dictionary] = []
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
	var candidates: Array[Villager] = []
	for v in social.ctx.tribe.villagers:
		if _available(v):
			candidates.append(v)
	var used := {}
	for a in candidates:
		if used.has(a):
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
		if social.graph.has_tag(a.villager_id, best.villager_id, &"rival"):
			p *= maxf(a.personality.get_trait(&"aggressiveness"), best.personality.get_trait(&"aggressiveness"))
		if social.rng.randf() < p:
			used[a] = true
			used[best] = true
			start(a, best)


## Starts a conversation. With `forced_topic` the first villager is the speaker.
func start(a: Villager, b: Villager, forced_topic: StringName = &"") -> void:
	var speaker := a
	var listener := b
	if forced_topic == &"":
		var wa := a.needs.social / 100.0 + a.personality.get_trait(&"sociability") + (0.6 if a.needs.is_hungry() else 0.0)
		var wb := b.needs.social / 100.0 + b.personality.get_trait(&"sociability") + (0.6 if b.needs.is_hungry() else 0.0)
		if wb > wa:
			speaker = b
			listener = a
	var outcome := decide(speaker, listener, forced_topic)
	var c := {"speaker": speaker, "listener": listener, "outcome": outcome, "elapsed": 0.0, "replied": false}
	c["task_s"] = ConverseTask.new(speaker, listener)
	c["task_l"] = ConverseTask.new(listener, speaker)
	# set_task ends each villager's previous task before the new one starts.
	speaker.set_task(c["task_s"])
	listener.set_task(c["task_l"])
	c["task_s"].start()
	c["task_l"].start()
	speaker.say(outcome.line_speaker)
	active.append(c)


func _advance(c: Dictionary, dt: float) -> void:
	var s: Villager = c["speaker"]
	var l: Villager = c["listener"]
	var still_talking: bool = is_instance_valid(s) and is_instance_valid(l) and not s.is_dead and not l.is_dead \
			and s.current_task == c["task_s"] and l.current_task == c["task_l"]
	c["elapsed"] += dt
	if not still_talking or c["elapsed"] > ABANDON_AFTER:
		_finish(c, false)
		return
	if not c["replied"] and c["elapsed"] >= DURATION * 0.45:
		c["replied"] = true
		l.say(c["outcome"].line_listener)
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
# Rules: what is talked about and what comes of it
# --------------------------------------------------------------------------

func decide(s: Villager, l: Villager, forced_topic: StringName = &"") -> ConversationOutcome:
	var o := ConversationOutcome.new()
	o.speaker_id = s.villager_id
	o.listener_id = l.villager_id
	var topic := forced_topic if forced_topic != &"" else _pick_topic(s, l)
	o.topic = topic
	match topic:
		&"ask_food": _resolve_ask_food(o, s, l)
		&"offer_food": _resolve_offer_food(o, s, l)
		&"share_location": _resolve_share_location(o, s, l)
		&"console": _resolve_console(o, s, l)
		&"gossip": _resolve_gossip(o, s, l)
		&"insult": _resolve_insult(o, s, l)
		&"flirt": _resolve_flirt(o, s, l)
		_: _resolve_small_talk(o, s, l)
	return o


func _pick_topic(s: Villager, l: Villager) -> StringName:
	var g := social.graph
	var sid := s.villager_id
	var lid := l.villager_id
	var ps := s.personality
	var w := {&"small_talk": 1.0}
	if s.needs.is_hungry() and l.inventory.carried_type == ResourceType.FOOD and l.inventory.amount > 0:
		w[&"ask_food"] = 4.0
	if _best_fact_to_share(s, l) >= 0:
		w[&"share_location"] = 0.6 + ps.get_trait(&"generosity")
	if l.memory.mood() < -0.3 and _grief_subject(l) >= 0:
		w[&"console"] = 2.5 * ps.get_trait(&"empathy")
	if _gossip_subject(s, l) >= 0:
		w[&"gossip"] = 0.4 + 0.6 * ps.get_trait(&"sociability")
	var aff := g.affinity(sid, lid)
	var aggr := ps.get_trait(&"aggressiveness")
	var compat := ps.compatibility(l.personality)
	var hostility := maxf(0.0, aggr - 0.45) * (1.5 if s.memory.mood() < -0.2 else 0.6) + maxf(0.0, -aff) * 2.0 \
			+ maxf(0.0, 0.45 - compat) * 1.5 * aggr
	if hostility > 0.1:
		w[&"insult"] = hostility
	if social.can_partner(s, l) and aff > 0.25 and g.affinity(lid, sid) > 0.1 and g.familiarity(sid, lid) > 0.3:
		w[&"flirt"] = 0.6 + aff
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


func _resolve_small_talk(o: ConversationOutcome, s: Villager, l: Villager) -> void:
	var soc := (s.personality.get_trait(&"sociability") + l.personality.get_trait(&"sociability")) * 0.5
	var compat := s.personality.compatibility(l.personality)
	var p := clampf(0.15 + 0.3 * soc + 0.5 * compat + 0.3 * social.graph.affinity(l.villager_id, s.villager_id), 0.05, 0.97)
	o.success = social.rng.randf() < p
	# Kindred spirits warm to each other faster; clashing temperaments cool.
	var shift := (compat - 0.45) * 0.12
	o.opinion_shifts.append([s.villager_id, l.villager_id, shift])
	o.opinion_shifts.append([l.villager_id, s.villager_id, shift])
	var kind := &"chatted" if o.success else &"awkward_talk"
	o.add_memory(s.villager_id, kind, l.villager_id)
	o.add_memory(l.villager_id, kind, s.villager_id)
	_lines(o, &"small_talk" if o.success else &"small_talk_fail", s, l)


func _best_fact_to_share(s: Villager, l: Villager) -> int:
	# Share what the tribe needs most.
	var types := ResourceType.ALL.duplicate()
	types.sort_custom(func(a, b): return social.ctx.tribe.get_demand(a) > social.ctx.tribe.get_demand(b))
	for t in types:
		var id := s.knowledge.shareable_fact(t, l.knowledge)
		if id >= 0:
			return id
	return -1


func _resolve_share_location(o: ConversationOutcome, s: Villager, l: Villager) -> void:
	var id := _best_fact_to_share(s, l)
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


func _resolve_ask_food(o: ConversationOutcome, s: Villager, l: Villager) -> void:
	var pl := l.personality
	var bond := 0.0
	if social.graph.has_tag(l.villager_id, s.villager_id, &"partner") or social.graph.is_kin(l.villager_id, s.villager_id):
		bond = 0.35
	var p := 0.15 + 0.45 * pl.get_trait(&"generosity") + 0.25 * pl.get_trait(&"empathy") \
			+ 0.3 * social.graph.affinity(l.villager_id, s.villager_id) + bond - (0.35 if l.needs.is_hungry() else 0.0)
	o.success = social.rng.randf() < clampf(p, 0.02, 0.98)
	if o.success:
		o.food_giver = l.villager_id
		o.food_receiver = s.villager_id
		o.food_amount = clampi(s.needs.food_wanted(), 1, mini(3, l.inventory.amount))
		o.add_memory(s.villager_id, &"was_helped", l.villager_id)
		o.add_memory(l.villager_id, &"helped", s.villager_id)
	else:
		social.stats.help_refused += 1
		o.add_memory(s.villager_id, &"was_refused", l.villager_id)
		o.add_memory(l.villager_id, &"refused", s.villager_id)
	_lines(o, &"ask_food" if o.success else &"ask_food_refused", s, l)


func _resolve_offer_food(o: ConversationOutcome, s: Villager, l: Villager) -> void:
	o.food_giver = s.villager_id
	o.food_receiver = l.villager_id
	o.food_amount = clampi(l.needs.food_wanted(), 1, maxi(1, mini(3, s.inventory.amount)))
	o.add_memory(l.villager_id, &"was_helped", s.villager_id)
	o.add_memory(s.villager_id, &"helped", l.villager_id)
	_lines(o, &"offer_food", s, l)


func _grief_subject(v: Villager) -> int:
	for r in v.memory.notable(6):
		if r.kind in [&"lost_partner", &"lost_family", &"lost_friend", &"saw_death"]:
			return r.subject_id
	return -1


func _resolve_console(o: ConversationOutcome, s: Villager, l: Villager) -> void:
	var subject := _grief_subject(l)
	var p := clampf(0.55 + 0.5 * social.graph.affinity(l.villager_id, s.villager_id), 0.1, 0.97)
	o.success = social.rng.randf() < p
	if o.success:
		o.add_memory(l.villager_id, &"was_comforted", s.villager_id, subject)
		o.add_memory(s.villager_id, &"comforted", l.villager_id, subject)
	else:
		o.add_memory(s.villager_id, &"awkward_talk", l.villager_id)
	_lines(o, &"console" if o.success else &"console_fail", s, l, {"subject": social.name_of(subject)})


## A living third villager the speaker feels strongly about and the listener knows.
func _gossip_subject(s: Villager, l: Villager) -> int:
	var best := -1
	var best_strength := 0.4
	for other in social.graph.known_by(s.villager_id):
		if other == l.villager_id or not social.is_alive(other):
			continue
		var strength := absf(social.graph.affinity(s.villager_id, other))
		if strength > best_strength and social.graph.familiarity(l.villager_id, other) > 0.0:
			best_strength = strength
			best = other
	return best


func _resolve_gossip(o: ConversationOutcome, s: Villager, l: Villager) -> void:
	var subject := _gossip_subject(s, l)
	var opinion := social.graph.affinity(s.villager_id, subject)
	# Listeners adopt part of the opinion, as much as they trust the speaker.
	var shift := opinion * 0.2 * social.graph.trust(l.villager_id, s.villager_id)
	o.opinion_shifts.append([l.villager_id, subject, shift])
	o.add_memory(l.villager_id, &"heard_gossip", s.villager_id, subject)
	o.add_memory(s.villager_id, &"chatted", l.villager_id)
	_lines(o, &"gossip_good" if opinion > 0.0 else &"gossip_bad", s, l, {"subject": social.name_of(subject)})


func _resolve_insult(o: ConversationOutcome, s: Villager, l: Villager) -> void:
	var pl := l.personality
	var retaliate := social.rng.randf() < pl.get_trait(&"aggressiveness") * 0.6 + pl.get_trait(&"courage") * 0.3
	o.success = true
	if retaliate:
		o.add_memory(s.villager_id, &"argued", l.villager_id)
		o.add_memory(l.villager_id, &"argued", s.villager_id)
		_lines(o, &"argue", s, l)
	else:
		o.add_memory(l.villager_id, &"was_insulted", s.villager_id)
		o.add_memory(s.villager_id, &"insulted", l.villager_id)
		_lines(o, &"insult", s, l)
	o.loneliness_relief = 10.0


func _resolve_flirt(o: ConversationOutcome, s: Villager, l: Villager) -> void:
	var p := clampf(social.graph.affinity(l.villager_id, s.villager_id) + 0.25 * l.personality.get_trait(&"sociability"), 0.02, 0.95)
	o.success = social.rng.randf() < p
	if o.success:
		o.add_memory(s.villager_id, &"flirted", l.villager_id)
		o.add_memory(l.villager_id, &"flirted", s.villager_id)
		o.try_partnership = true
	else:
		o.add_memory(s.villager_id, &"rejected", l.villager_id)
	_lines(o, &"flirt" if o.success else &"flirt_rejected", s, l)
