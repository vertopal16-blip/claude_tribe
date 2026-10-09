class_name PersonalityModifier
extends DecisionModifier
## Personality traits bias goal scores. Combined with the brain's weighted
## random choice this makes traits shape behaviour probabilistically: a lazy
## villager still works, just less often.


func get_label() -> String:
	return "Personality"


func modify_scores(villager: Node, scores: Dictionary) -> void:
	var p: Personality = villager.personality
	var work := lerpf(0.7, 1.3, p.get_trait(&"industriousness"))
	for g in [&"gather_food", &"gather_wood", &"gather_stone", &"build"]:
		if scores.has(g):
			scores[g] *= work
	if scores.has(&"build"):
		scores[&"build"] *= lerpf(0.9, 1.15, p.get_trait(&"ambition"))
	if scores.has(&"idle"):
		scores[&"idle"] *= lerpf(1.6, 0.6, p.get_trait(&"industriousness"))
	if scores.has(&"socialize"):
		scores[&"socialize"] *= lerpf(0.4, 1.6, p.get_trait(&"sociability"))
	if scores.has(&"explore"):
		scores[&"explore"] *= lerpf(0.6, 1.5, p.get_trait(&"curiosity")) * lerpf(0.85, 1.15, p.get_trait(&"courage"))
	if scores.has(&"help"):
		scores[&"help"] *= lerpf(0.75, 1.1, p.get_trait(&"empathy"))
