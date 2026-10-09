class_name SocialModifier
extends DecisionModifier
## Mood (from memories) biases decisions: grieving or unhappy villagers work
## less and seek company; happy ones work a little harder.


func get_label() -> String:
	return "Mood"


func modify_scores(villager: Node, scores: Dictionary) -> void:
	var mood: float = villager.memory.mood()
	var work_mult := 1.0
	if mood < -0.35:
		work_mult = 0.8
		if scores.has(&"socialize"):
			scores[&"socialize"] = scores[&"socialize"] * 1.3 + 0.1
		if scores.has(&"idle"):
			scores[&"idle"] *= 1.5
	elif mood > 0.4:
		work_mult = 1.08
	for g in [&"gather_food", &"gather_wood", &"gather_stone", &"build"]:
		if scores.has(g):
			scores[g] *= work_mult
