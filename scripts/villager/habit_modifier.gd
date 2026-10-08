class_name HabitModifier
extends DecisionModifier
## Villagers mildly prefer to continue the kind of work they did last, which
## reduces pointless job switching (and walking) between trips.

## Multiplier, so habit only tips close decisions and never overrides real demand.
var bonus := 1.2


func get_label() -> String:
	return "Habit"


func modify_scores(villager: Node, scores: Dictionary) -> void:
	var last: StringName = villager.brain.last_work_goal
	if last != &"" and scores.has(last) and scores[last] > 0.0:
		scores[last] *= bonus
