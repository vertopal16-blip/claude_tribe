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
	hut.housing = 6
	hut.description = "Family home for up to 6. Sleeping inside restores energy twice as fast."
	_defs[hut.id] = hut

	var farm := BuildingDef.new()
	farm.id = &"farm"
	farm.display_name = "Farm"
	farm.description = "Tilled field. Farmers tend it until the crop ripens, then harvest food."
	farm.costs = {ResourceType.WOOD: 15}
	farm.build_work = 18.0
	farm.footprint_radius = 3.2
	farm.required_tech = &"agriculture"
	farm.work_skill = &"farming"
	_defs[farm.id] = farm

	var workshop := BuildingDef.new()
	workshop.id = &"workshop"
	workshop.display_name = "Workshop"
	workshop.description = "Toolmakers turn wood and stone into tools that make work faster."
	workshop.costs = {ResourceType.WOOD: 25, ResourceType.STONE: 15}
	workshop.build_work = 28.0
	workshop.footprint_radius = 2.4
	workshop.required_tech = &"toolmaking"
	workshop.work_skill = &"toolmaking"
	_defs[workshop.id] = workshop

	var longhouse := BuildingDef.new()
	longhouse.id = &"longhouse"
	longhouse.display_name = "Longhouse"
	longhouse.description = "Meeting hall: gatherings, councils and celebrations take place here."
	longhouse.costs = {ResourceType.WOOD: 60, ResourceType.STONE: 25}
	longhouse.build_work = 45.0
	longhouse.footprint_radius = 3.4
	longhouse.required_tech = &"carpentry"
	longhouse.min_population = 12
	longhouse.max_builders = 5
	_defs[longhouse.id] = longhouse

	var shrine := BuildingDef.new()
	shrine.id = &"shrine"
	shrine.display_name = "Shrine"
	shrine.description = "Sacred stones where the tribe honours its dead and holds ceremonies."
	shrine.costs = {ResourceType.WOOD: 10, ResourceType.STONE: 30}
	shrine.build_work = 22.0
	shrine.footprint_radius = 2.0
	_defs[shrine.id] = shrine

	# Cultural structures: only proposed once the tribe's culture calls for them.
	var circle := BuildingDef.new()
	circle.id = &"gathering_circle"
	circle.display_name = "Gathering circle"
	circle.description = "A ring of standing stones around a fire pit where the tribe holds its ceremonies."
	circle.costs = {ResourceType.WOOD: 15, ResourceType.STONE: 35}
	circle.build_work = 30.0
	circle.footprint_radius = 4.4
	circle.max_builders = 5
	_defs[circle.id] = circle

	var totem := BuildingDef.new()
	totem.id = &"totem"
	totem.display_name = "Totem"
	totem.description = "A carved and painted pole showing the tribe's symbols."
	totem.costs = {ResourceType.WOOD: 25, ResourceType.STONE: 5}
	totem.build_work = 26.0
	totem.footprint_radius = 1.0
	totem.work_skill = &"woodcutting"
	_defs[totem.id] = totem

	var memorial := BuildingDef.new()
	memorial.id = &"memorial_stone"
	memorial.display_name = "Memorial stone"
	memorial.description = "A standing stone raised in memory of someone the tribe will not forget."
	memorial.costs = {ResourceType.STONE: 25}
	memorial.build_work = 20.0
	memorial.footprint_radius = 1.2
	memorial.work_skill = &"stonework"
	_defs[memorial.id] = memorial
