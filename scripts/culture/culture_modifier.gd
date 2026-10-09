class_name CultureModifier
extends DecisionModifier
## What a person believes shapes what they choose to do: those who value
## craftsmanship make and build, those who value nature work the land and
## spare the trees, the curious and brave go exploring, the cooperative and
## generous help, the spiritual attend ceremonies, the ambitious seek office.
## These are personal beliefs, so a villager can act against the tribe's
## culture when their own values differ.


func get_label() -> String:
	return "Beliefs"


func modify_scores(villager: Node, scores: Dictionary) -> void:
	var v := villager as Villager
	if v == null or v.ctx.society == null or v.is_child():
		return
	var cv := v.ctx.society.culture.values_of(v)
	var craft := cv.get_value(&"craftsmanship")
	var nature := cv.get_value(&"nature")
	var curious := cv.get_value(&"curiosity") + cv.get_value(&"knowledge") * 0.5
	var brave := cv.get_value(&"courage")
	var achieve := cv.get_value(&"achievement")
	var helpful := cv.get_value(&"cooperation") + cv.get_value(&"generosity") * 0.7 + cv.get_value(&"hospitality") * 0.3 \
			- cv.get_value(&"independence") * 0.6
	_mul(scores, &"craft", 1.0 + 0.6 * craft)
	_mul(scores, &"build", 1.0 + 0.3 * craft + 0.2 * cv.get_value(&"cooperation"))
	_mul(scores, &"farm", 1.0 + 0.25 * nature)
	_mul(scores, &"fish", 1.0 + 0.2 * nature + 0.2 * brave)
	_mul(scores, &"gather_food", 1.0 + 0.15 * nature)
	# Respect for nature: fell trees only when the tribe really needs wood.
	if v.ctx.tribe.get_demand(ResourceType.WOOD) < 0.5:
		_mul(scores, &"gather_wood", 1.0 - 0.35 * maxf(0.0, nature))
	_mul(scores, &"explore", 1.0 + 0.5 * curious + 0.3 * brave - 0.25 * cv.get_value(&"tradition"))
	_mul(scores, &"help", 1.0 + 0.6 * helpful)
	_mul(scores, &"heal", 1.0 + 0.3 * cv.get_value(&"knowledge") + 0.2 * helpful)
	_mul(scores, &"socialize", 1.0 + 0.2 * cv.get_value(&"family") + 0.15 * cv.get_value(&"hospitality"))
	_mul(scores, &"idle", 1.0 - 0.3 * maxf(0.0, achieve))
	_mul(scores, &"ceremony", 1.0 + 0.6 * cv.get_value(&"spirituality") + 0.4 * cv.get_value(&"tradition"))
	_mul(scores, &"campaign", 1.0 + 0.6 * cv.get_value(&"hierarchy") - 0.6 * cv.get_value(&"equality"))
	for g in VillagerBrain.WORK_GOALS + [&"gather_food", &"gather_wood", &"gather_stone"]:
		_mul(scores, g, 1.0 + 0.15 * achieve)
	# Customs one keeps: the evening fire draws people together at dusk.
	var culture := v.ctx.society.culture
	var tod := SimClock.get_time_of_day()
	if tod >= 0.7 and scores.has(&"socialize"):
		scores[&"socialize"] += culture.evening_bonus()


static func _mul(scores: Dictionary, goal: StringName, f: float) -> void:
	if scores.has(goal):
		scores[goal] *= maxf(0.3, f)
