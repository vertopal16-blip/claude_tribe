class_name ProfessionModifier
extends DecisionModifier
## Villagers who have a profession prefer its work; skilled people gravitate
## to what they are good at even before it becomes their profession.

const WORK_SKILL := {
	&"gather_food": &"foraging", &"gather_wood": &"woodcutting", &"gather_stone": &"stonework",
	&"build": &"building", &"farm": &"farming", &"fish": &"fishing", &"craft": &"toolmaking",
	&"heal": &"healing",
}


func get_label() -> String:
	return "Skill & profession"


func modify_scores(villager: Node, scores: Dictionary) -> void:
	var prof: StringName = villager.profession
	for g in WORK_SKILL:
		if not scores.has(g):
			continue
		var skill: StringName = WORK_SKILL[g]
		var mult: float = 1.0 + villager.skills.get_level(skill) / 250.0
		if ProfessionSystem.skill_of(prof) == skill:
			mult *= 1.45
		scores[g] *= mult
