class_name Main
extends Node3D
## Bootstraps the game: config -> terrain -> navigation -> settlement ->
## resources -> villagers -> lighting -> camera -> interaction -> UI.

const CONFIG_PATH := "res://config/default_config.tres"

@export var config: GameConfig

var ctx := WorldContext.new()
var terrain: Terrain
var tribe: Tribe
var rts_camera: RtsCamera
var interaction: WorldInteraction
var hud: Hud
var day_night: DayNightCycle
var world_seed: int = 0


func _ready() -> void:
	if config == null:
		config = load(CONFIG_PATH) as GameConfig
	if config == null:
		push_warning("Could not load %s, using built-in defaults." % CONFIG_PATH)
		config = GameConfig.new()
	InputSetup.register()
	SimClock.configure(config)

	world_seed = config.world_seed if config.world_seed != 0 else int(Time.get_unix_time_from_system()) % 1000000
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	print("[Tribal] World seed: %d" % world_seed)

	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	terrain = Terrain.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	terrain.generate(config, world_seed)

	var nav := NavGrid.new()
	nav.build(terrain, config)

	ctx.config = config
	ctx.terrain = terrain
	ctx.nav = nav
	ctx.resources = ResourceRegistry.new(nav)
	ctx.rng = rng
	ctx.world_root = world

	tribe = Tribe.new()
	tribe.name = "Tribe"
	world.add_child(tribe)
	ctx.tribe = tribe
	tribe.setup(ctx)

	var counts := WorldGenerator.new().populate(ctx)
	print("[Tribal] Placed %d trees, %d rocks, %d berry bushes" % [counts.trees, counts.rocks, counts.bushes])
	if nav.access_region(tribe.center) != nav.main_region():
		push_warning("Settlement is not in the largest walkable region.")

	tribe.spawn_initial_villagers()
	SimClock.sim_tick.connect(tribe.sim_tick)

	_setup_lighting()

	rts_camera = RtsCamera.new()
	rts_camera.name = "RtsCamera"
	add_child(rts_camera)
	rts_camera.setup(terrain, tribe.center)

	interaction = WorldInteraction.new()
	interaction.name = "WorldInteraction"
	interaction.setup(ctx, rts_camera)
	add_child(interaction)

	hud = Hud.new()
	hud.name = "Hud"
	hud.setup(ctx, interaction, rts_camera)
	add_child(hud)
	EventBus.notify("%s has settled in the valley. Population: %d." % [tribe.tribe_name, tribe.population()])


func _setup_lighting() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = config.shadows_enabled
	sun.set_meta("shadows", config.shadows_enabled)
	sun.directional_shadow_max_distance = config.shadow_max_distance
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5
	add_child(sun)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.shadow_enabled = false
	add_child(moon)

	day_night = DayNightCycle.new()
	day_night.name = "DayNightCycle"
	add_child(day_night)
	day_night.setup(sun, moon, env)
