class_name DecisionModifier
extends RefCounted
## Extension point for anything that biases what a villager decides to do.
##
## The brain computes base utility scores from needs and tribe demand, then
## passes them through every modifier attached to the villager. Future systems
## (personality traits, memories, relationships, mood, ambitions) plug in here
## as new DecisionModifier subclasses without touching the brain or tasks.

## Short name shown in debugging / inspection UI.
func get_label() -> String:
	return "Modifier"


## `scores` maps goal ids (StringName) to utility floats; modify in place.
func modify_scores(_villager: Node, _scores: Dictionary) -> void:
	pass
