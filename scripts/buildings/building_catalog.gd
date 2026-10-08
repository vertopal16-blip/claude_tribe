class_name BuildingCatalog
extends RefCounted
## Registry of all building definitions.

static var _defs: Dictionary = {}


static func get_def(id: StringName) -> BuildingDef:
	_ensure()
	return _defs.get(id)


static func buildable() -> Array[BuildingDef]:
	_ensure()
	var out: Array[BuildingDef] = []
	for d: BuildingDef in _defs.values():
		if d.player_buildable:
			out.append(d)
	return out


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	var campfire := BuildingDef.new()
	campfire.id = &"campfire"
	campfire.display_name = "Campfire"
	campfire.description = "Heart of the camp. Villagers without a hut sleep beside it."
	campfire.footprint_radius = 1.2
	campfire.rest_multiplier = 1.0
	campfire.is_campfire = true
	_defs[campfire.id] = campfire

	var stockpile := BuildingDef.new()
	stockpile.id = &"stockpile"
	stockpile.display_name = "Stockpile"
	stockpile.description = "Shared tribal storage for food, wood and stone."
	stockpile.footprint_radius = 1.6
	stockpile.is_storage = true
	_defs[stockpile.id] = stockpile

	var hut := BuildingDef.new()
	hut.id = &"hut"
	hut.display_name = "Hut"
	hut.description = "Shelter for 2 villagers. Sleeping inside restores energy twice as fast."
	hut.costs = {ResourceType.WOOD: 20, ResourceType.STONE: 8}
	hut.build_work = 24.0
	hut.footprint_radius = 2.2
	hut.housing = 2
	hut.rest_multiplier = 2.0
	hut.player_buildable = true
	hut.max_builders = 3
	_defs[hut.id] = hut
