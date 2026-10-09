class_name WorldContext
extends RefCounted
## Shared references to the world's systems. Passed to villagers and tasks so
## they never reach into the scene tree or global singletons to find things.

var config: GameConfig
var terrain: Terrain
var nav: NavGrid
var resources: ResourceRegistry
var tribe: Tribe
var rng: RandomNumberGenerator
## Node under which world entities (villagers, buildings, nodes) are spawned.
var world_root: Node3D
var world_seed: int = 0

var _next_entity_id := 1


## Stable id for world objects (buildings, resource nodes). Unlike instance
## ids these are deterministic for a given seed and safe to persist, so
## memories and save files can refer to "that hut" or "that tree".
func allocate_entity_id() -> int:
	var id := _next_entity_id
	_next_entity_id += 1
	return id
