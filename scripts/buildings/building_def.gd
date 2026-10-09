class_name BuildingDef
extends Resource
## Data describing a building type. New buildings are added as new defs in
## BuildingCatalog; the construction and AI code work on this data only.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Resource costs: { ResourceType: amount }.
@export var costs: Dictionary = {}
## Work-seconds needed once all materials are delivered.
@export var build_work: float = 20.0
@export var footprint_radius: float = 2.0
@export var housing: int = 0
## Energy recovery multiplier for villagers resting inside.
@export var rest_multiplier: float = 1.0
@export var is_storage: bool = false
@export var is_campfire: bool = false
@export var player_buildable: bool = false
@export var max_builders: int = 3
## Technology someone must know before this can be proposed and built.
@export var required_tech: StringName = &""
## Minimum population before anyone sees a need for it.
@export var min_population: int = 0
## Which skill its work trains (farm -> farming, workshop -> toolmaking...).
@export var work_skill: StringName = &""


func total_cost() -> int:
	var t := 0
	for k in costs:
		t += int(costs[k])
	return t


func cost_string() -> String:
	var parts: PackedStringArray = []
	for k in ResourceType.ALL:
		if costs.has(k) and int(costs[k]) > 0:
			parts.append("%d %s" % [costs[k], ResourceType.display_name(k).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "free"
