extends Node
## Global, decoupled event channel.
##
## Gameplay systems emit; UI, notifications and (later) memory / social systems
## listen. Nothing in the simulation depends on who is listening.

signal stockpile_changed(amounts: Dictionary)
signal population_changed(count: int)
signal villager_spawned(villager: Node)
signal villager_died(villager: Node, cause: String)
## Generic hook for meaningful villager actions ("ate", "delivered", "built"...).
## Intended consumer: a future per-villager memory system.
signal villager_event(villager: Node, event_name: StringName, data: Dictionary)
signal building_placed(building: Node)
signal building_completed(building: Node)
signal building_removed(building: Node)
signal selection_changed(target: Node)
signal camera_focus_requested(position: Vector3)
signal notification_posted(text: String, kind: StringName)


func notify(text: String, kind: StringName = &"info") -> void:
	notification_posted.emit(text, kind)
