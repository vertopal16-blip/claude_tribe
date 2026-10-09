class_name ConversationOutcome
extends RefCounted
## The result of a conversation, as plain data, decided BEFORE anything changes.
##
## Nothing in the game state changes until validate() passes and apply() runs.
## This is the contract any future dialogue generator (e.g. a language model)
## must go through: it may only propose an outcome, never touch the world.

var topic: StringName
var speaker_id: int
var listener_id: int
var success := true
## Visual style while talking: &"talk", &"warm", &"romance", &"argue", &"fight".
var style: StringName = &"talk"
var line_speaker := ""
var line_listener := ""
## [villager_id, kind, other_id, subject_id, detail]
var memories: Array = []
## Knowledge the listener receives: entity_id -> fact (must be held by the speaker).
var facts_to_listener: Dictionary = {}
## Food handed over: giver id -> receiver id, amount.
var food_giver := -1
var food_receiver := -1
var food_amount := 0
## Opinion changes: [from, about, field, delta]
var opinion_shifts: Array = []
## Health lost in a fight: villager_id -> damage.
var injuries: Dictionary = {}
## Behaviour suggestions: [villager_id, goal, bonus, seconds, reason]
var suggestions: Array = []
## Promises: [from_id, to_id, kind, object_id, due_days, text]
var promises: Array = []
## Skill teaching: [teacher_id, student_id, skill, strength]
var teaching: Array = []
## Technology explained: [teacher_id, student_id, tech]
var tech_shared: Array = []
## Romance: a welcomed flirt [speaker, listener], form a couple, break up.
var flirt: Array = []
var couple: Array = []
var breakup: Array = []
## Tags to set: [a, b, tag, on]
var tags: Array = []
## Chronicle entries: [category, text, [ids]]
var history: Array = []
## Proposal stance changes: [proposal_id, villager_id, stance]
var stances: Array = []
## Leadership endorsements: [voter_id, candidate_id]
var endorsements: Array = []
## Skill practice from the talk itself: [villager_id, skill, seconds]
var practice: Array = []
var witnesses_fight := false
var loneliness_relief := 45.0


func add_memory(villager_id: int, kind: StringName, other_id: int = -1, subject_id: int = -1, detail: String = "") -> void:
	memories.append([villager_id, kind, other_id, subject_id, detail])


## Checks every proposed effect against the current, authoritative state.
func validate(social: SocialSystem) -> bool:
	var s := social.get_villager(speaker_id)
	var l := social.get_villager(listener_id)
	if s == null or l == null:
		return false
	for id in facts_to_listener:
		if s.knowledge.store.get_fact(id) == null:
			return false  # can't share what you don't know
	if food_amount > 0:
		var giver := social.get_villager(food_giver)
		if giver == null or social.get_villager(food_receiver) == null:
			return false
		if giver.inventory.carried_type != ResourceType.FOOD or giver.inventory.amount < food_amount:
			return false
	for t in teaching:
		var teacher := social.get_villager(t[0])
		var student := social.get_villager(t[1])
		if teacher == null or student == null or teacher.skills.get_level(t[2]) <= student.skills.get_level(t[2]):
			return false
	for t in tech_shared:
		var teacher := social.get_villager(t[0])
		if teacher == null or not social.ctx.society.tech.knows(teacher, t[2]):
			return false
	if not couple.is_empty():
		var a := social.get_villager(couple[0])
		var b := social.get_villager(couple[1])
		if a == null or b == null or not social.romance.eligible(a) or not social.romance.eligible(b):
			return false
	for m in memories:
		if not MemoryPolicy.has_kind(m[1]) or social.get_villager(m[0]) == null:
			return false
	return true


func apply(social: SocialSystem) -> void:
	var s := social.get_villager(speaker_id)
	var l := social.get_villager(listener_id)
	for id in facts_to_listener:
		l.knowledge.store.learn(id, facts_to_listener[id], speaker_id)
	if food_amount > 0:
		var giver := social.get_villager(food_giver)
		var receiver := social.get_villager(food_receiver)
		var given := giver.inventory.remove(food_amount)
		receiver.needs.eat(given)
		social.stats.help_given += 1
	for shift in opinion_shifts:
		social.graph.adjust_field(shift[0], shift[1], shift[2], shift[3])
	for id in injuries:
		var v := social.get_villager(id)
		if v != null:
			v.needs.health = maxf(1.0, v.needs.health - injuries[id])
	for t in teaching:
		var student := social.get_villager(t[1])
		var teacher := social.get_villager(t[0])
		student.skills.learn_from(t[2], teacher.skills.get_level(t[2]), t[3], student.personality)
		teacher.practice(&"persuasion", 4.0)
	for t in tech_shared:
		social.ctx.society.tech.learn(social.get_villager(t[1]), t[2], social.get_villager(t[0]))
	for t in tags:
		social.graph.set_tag(t[0], t[1], t[2], t[3])
	for pr in practice:
		var pv := social.get_villager(pr[0])
		if pv != null:
			pv.practice(pr[1], pr[2])
	for m in memories:
		social.remember(social.get_villager(m[0]), m[1], m[2], m[3], -1, m[4])
	for sg in suggestions:
		var v := social.get_villager(sg[0])
		if v != null:
			v.brain.suggest(sg[1], sg[2], sg[3], sg[4])
	for p in promises:
		social.promises.make(p[0], p[1], p[2], p[3], p[4], p[5])
	for st in stances:
		social.ctx.society.proposals.set_stance(st[0], st[1], st[2])
	for e in endorsements:
		social.ctx.society.politics.endorse(e[0], e[1])
	if witnesses_fight:
		for w in social.ctx.tribe.villagers_near(s.global_position, SocialSystem.WITNESS_RADIUS):
			if w != s and w != l and not w.is_hidden():
				social.remember(w, &"saw_fight", speaker_id, listener_id)
	for h in history:
		social.ctx.society.history.add(h[0], h[1], h[2])
	social.graph.add_familiarity(speaker_id, listener_id, 0.04)
	s.needs.social = maxf(0.0, s.needs.social - loneliness_relief)
	l.needs.social = maxf(0.0, l.needs.social - loneliness_relief)
	if not flirt.is_empty():
		social.romance.on_flirt_success(social.get_villager(flirt[0]), social.get_villager(flirt[1]))
	if not couple.is_empty():
		social.romance.form_couple(social.get_villager(couple[0]), social.get_villager(couple[1]))
	if not breakup.is_empty():
		social.romance.break_up(social.get_villager(breakup[0]), social.get_villager(breakup[1]), breakup[2])
	s.remember_line(line_speaker, l.villager_name)
	l.remember_line(line_listener, s.villager_name)


func to_dict() -> Dictionary:
	return {"topic": String(topic), "speaker": speaker_id, "listener": listener_id, "success": success,
		"memories": memories.duplicate(true), "facts": facts_to_listener.keys(), "food": food_amount,
		"style": String(style)}
