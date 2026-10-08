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
