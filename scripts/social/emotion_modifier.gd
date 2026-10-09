class_name EmotionModifier
extends DecisionModifier
## Feelings bend decisions without overriding survival: fear avoids risk,
## grief and sadness sap the will to work, anger and frustration make
## villagers restless, pride and hope make them work harder, gratitude makes
## them help, curiosity makes them explore.


func get_label() -> String:
	return "Emotions"


func modify_scores(villager: Node, scores: Dictionary) -> void:
	var em: Emotions = villager.emotions
	var grief := em.get_value(&"grief")
	var sadness := em.get_value(&"sadness")
	var fear := em.get_value(&"fear")
	var drive := 1.0 + 0.15 * (em.get_value(&"pride") + em.get_value(&"hope") + em.get_value(&"satisfaction")) \
			- 0.35 * grief - 0.15 * sadness - 0.1 * em.get_value(&"frustration")
	for g in [&"gather_food", &"gather_wood", &"gather_stone", &"build", &"farm", &"fish", &"craft"]:
		if scores.has(g):
			scores[g] *= maxf(0.4, drive)
	if scores.has(&"explore"):
		scores[&"explore"] *= (1.0 - 0.6 * fear) * (1.0 + 0.5 * em.get_value(&"curiosity"))
	if scores.has(&"socialize"):
		scores[&"socialize"] *= 1.0 + 0.6 * grief + 0.3 * sadness + 0.4 * em.get_value(&"affection")
	if scores.has(&"help"):
		scores[&"help"] *= 1.0 + 0.3 * em.get_value(&"gratitude")
	if scores.has(&"idle"):
		scores[&"idle"] *= 1.0 + grief + em.get_value(&"frustration")
