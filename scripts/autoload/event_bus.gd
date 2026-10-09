extends Node
## Global, decoupled event channel.
##
## Gameplay systems emit; UI, notifications and (later) memory / social systems
## listen. Nothing in the simulation depends on who is listening.

signal stockpile_changed(amounts: Dictionary)
signal population_changed(count: int)
signal villager_spawned(villager: Node)
signal villager_died(villager: Node, cause: String)
## Meaningful villager actions ("ate", "delivered", "completed_building"...).
## Emitted only through Villager.record_event(), so `data` is always plain,
## serializable values: stable ids instead of node references, plus
## "villager_id", "time", "day" and "position". Intended consumers: a future
## per-villager memory system, statistics and save files.
signal villager_event(villager: Node, event_name: StringName, data: Dictionary)
## A villager formed a memory (social layer). `record` is MemoryRecord.to_dict().
signal social_event(villager: Node, kind: StringName, record: Dictionary)
## A conversation completed and its (validated) outcome was applied.
signal conversation_finished(outcome: Dictionary)
signal building_placed(building: Node)
signal building_completed(building: Node)
signal building_removed(building: Node)
signal selection_changed(target: Node)
signal camera_focus_requested(position: Vector3)
signal notification_posted(text: String, kind: StringName)


func notify(text: String, kind: StringName = &"info") -> void:
	notification_posted.emit(text, kind)
