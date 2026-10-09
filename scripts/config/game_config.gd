class_name GameConfig
extends Resource
## All tunable gameplay and performance parameters in one place.
## Edit res://config/default_config.tres in the inspector to rebalance.

@export_group("World")
## 0 = random seed every run.
@export var world_seed: int = 0
@export var world_size: float = 160.0
@export var boundary_width: float = 22.0
@export var terrain_cell_size: float = 2.0
@export var hill_height: float = 5.0
@export var mountain_height: float = 26.0
@export var water_level: float = 0.0
@export var settlement_flat_radius: float = 14.0
@export var settlement_height: float = 2.6
@export var lake_radius_min: float = 11.0
@export var lake_radius_max: float = 14.0

@export_group("Navigation")
@export var nav_cell_size: float = 1.0
## Terrain steeper than this (normal.y below the value) is not walkable.
@export var max_walkable_slope_normal_y: float = 0.72

@export_group("Resources")
@export var tree_count: int = 230
@export var rock_count: int = 70
@export var bush_count: int = 95
@export var start_area_inner_radius: float = 13.0
@export var start_area_outer_radius: float = 32.0
@export var start_area_trees: int = 18
@export var start_area_rocks: int = 7
@export var start_area_bushes: int = 14
@export var tree_wood: int = 12
@export var rock_stone: int = 24
@export var bush_food: int = 8
## Sim-seconds until a felled tree is harvestable again.
@export var tree_regrow_time: float = 300.0
## Sim-seconds per berry regrown on a bush.
@export var bush_regrow_interval: float = 20.0

@export_group("Tribe")
@export var starting_villagers: int = 8
@export var starting_food: int = 40
@export var starting_wood: int = 12
@export var starting_stone: int = 4
@export var starting_huts: int = 2
## Maximum distance from the campfire at which buildings may be placed.
@export var settlement_build_radius: float = 40.0
@export var auto_build_huts: bool = true
## Sim-days per year of age. Low on purpose so generations pass in a session.
@export var days_per_year: float = 2.0

@export_group("Villager")
@export var move_speed: float = 3.4
@export var carry_capacity: int = 8
@export var gather_interval: float = 1.7
@export var build_rate: float = 1.0
@export var food_hunger_value: float = 20.0
## Hunger points gained per sim-second (0 = full, 100 = starving).
@export var hunger_rate: float = 0.30
@export var hungry_threshold: float = 50.0
@export var critical_hunger: float = 78.0
## Energy lost per sim-second at full activity.
@export var energy_drain: float = 0.2
@export var tired_threshold: float = 28.0
@export var energy_recovery: float = 1.1
@export var health_regen: float = 0.25
@export var starvation_damage: float = 0.6
@export var exhaustion_damage: float = 0.15

@export_group("Social")
## 0 = derive from world_seed. Same world_seed with a different social_seed
## gives the same valley with different people.
@export var social_seed: int = 0
## Loneliness gained per sim-second for an average villager (0..100 scale).
@export var loneliness_rate: float = 0.24

@export_group("Demographics")
@export var youth_age: float = 12.0
@export var adult_age: float = 16.0
@export var elder_age: float = 55.0
@export var fertile_min_age: float = 17.0
@export var fertile_max_age: float = 42.0
## Days from conception to birth.
@export var pregnancy_days: float = 3.0
## Minimum days between births for one mother.
@export var birth_spacing_days: float = 5.0
## Daily chance of conception for an eligible, well-off couple.
@export var conception_chance: float = 0.35
## Hard safety cap; births normally stop far earlier for lack of food/homes.
@export var max_population: int = 80

@export_group("Simulation")
@export var sim_tick_interval: float = 0.25
@export var max_ticks_per_frame: int = 8
@export var day_length_seconds: float = 240.0
@export var start_time_of_day: float = 0.29

@export_group("Performance")
## New task decisions (which include pathfinding) allowed per simulation tick
## across the whole tribe. Spreads out bursts such as everyone waking up.
@export var max_decisions_per_tick: int = 8
@export var grass_instances: int = 9000
@export var flower_instances: int = 900
@export var pebble_instances: int = 700
@export var mountain_tree_instances: int = 420
@export var shadows_enabled: bool = true
@export var shadow_max_distance: float = 140.0


func get_playable_half_extent() -> float:
	return world_size * 0.5 - boundary_width
