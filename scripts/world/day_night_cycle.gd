class_name DayNightCycle
extends Node
## Drives the sun, moon, sky and ambient light from SimClock's time of day,
## so it follows pause and speed controls automatically.

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial

var _sun_colors := Gradient.new()
var _sky_top := Gradient.new()
var _sky_horizon := Gradient.new()


func setup(sun_light: DirectionalLight3D, moon_light: DirectionalLight3D, env: Environment) -> void:
	sun = sun_light
	moon = moon_light
	environment = env
	sky_material = env.sky.sky_material as ProceduralSkyMaterial
	# Gradients are indexed by daylight-ish value (0 night .. 1 noon).
	_sun_colors.set_color(0, Color(1.0, 0.45, 0.25))
	_sun_colors.set_color(1, Color(1.0, 0.96, 0.88))
	_sun_colors.add_point(0.35, Color(1.0, 0.72, 0.48))
	_sky_top.set_color(0, Color(0.03, 0.05, 0.12))
	_sky_top.set_color(1, Color(0.30, 0.52, 0.82))
	_sky_top.add_point(0.4, Color(0.25, 0.30, 0.55))
	_sky_horizon.set_color(0, Color(0.07, 0.09, 0.17))
	_sky_horizon.set_color(1, Color(0.70, 0.80, 0.88))
	_sky_horizon.add_point(0.35, Color(0.95, 0.58, 0.38))
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if sun == null:
		return
	var tod := SimClock.get_time_of_day()
	var daylight := SimClock.get_daylight()
	# Sun travels east -> west; angle 0 at sunrise (06:00), PI at sunset.
	var sun_angle := (tod - 0.25) * TAU
	sun.rotation = Vector3(-sin(sun_angle) * deg_to_rad(68.0) - deg_to_rad(4.0), deg_to_rad(-35.0) + cos(sun_angle) * deg_to_rad(70.0), 0.0)
	sun.light_energy = lerpf(0.0, 1.0, daylight)
	sun.light_color = _sun_colors.sample(daylight)
	sun.visible = daylight > 0.01
	sun.shadow_enabled = sun.visible and sun.get_meta("shadows", true)

	var night := 1.0 - daylight
	moon.light_energy = 0.22 * night
	moon.visible = night > 0.05
	moon.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(150.0) + sun_angle * 0.2, 0.0)

	if sky_material:
		sky_material.sky_top_color = _sky_top.sample(daylight)
		sky_material.sky_horizon_color = _sky_horizon.sample(daylight)
		sky_material.ground_horizon_color = _sky_horizon.sample(daylight).darkened(0.2)
		sky_material.ground_bottom_color = _sky_top.sample(daylight).darkened(0.5)
	environment.ambient_light_energy = lerpf(0.28, 0.42, daylight)
	environment.ambient_light_color = Color(0.32, 0.38, 0.62).lerp(Color(0.78, 0.84, 0.95), daylight)
	environment.fog_light_color = _sky_horizon.sample(daylight)
