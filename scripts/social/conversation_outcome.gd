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
## Opinion shifts from gossip: [from, about, d_affinity]
var opinion_shifts: Array = []
var try_partnership := false
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
		social.graph.adjust_opinion(shift[0], shift[1], shift[2], 0.0)
	for m in memories:
		social.remember(social.get_villager(m[0]), m[1], m[2], m[3], -1, m[4])
	social.graph.add_familiarity(speaker_id, listener_id, 0.04)
	s.needs.social = maxf(0.0, s.needs.social - loneliness_relief)
	l.needs.social = maxf(0.0, l.needs.social - loneliness_relief)
	if try_partnership:
		social.try_partnership(s, l)


func to_dict() -> Dictionary:
	return {"topic": String(topic), "speaker": speaker_id, "listener": listener_id, "success": success,
		"memories": memories.duplicate(true), "facts": facts_to_listener.keys(), "food": food_amount}
