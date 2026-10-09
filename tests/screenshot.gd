extends Node
## Renders screenshots of the real game for visual review.
## Run (needs a display / xvfb):
##   godot --path . res://tests/screenshot.tscn -- --out=/tmp/shots --seed=1234

var main: Main
var out_dir := "user://screenshots"
var seed_value := 1234
var frame := 0
var shots: Array = []
var _shot_index := 0
var _wait := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.split("=")[1]
		elif arg.begins_with("--seed="):
			seed_value = int(arg.split("=")[1])
		elif arg.begins_with("--shots="):
			set_meta("max_shots", int(arg.split("=")[1]))
		elif arg.begins_with("--load="):
			# Start from a saved (e.g. culturally developed) tribe.
			Main.pending_load = SaveSystem.read(arg.split("=")[1])
		elif arg == "--culture":
			set_meta("culture", true)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cfg: GameConfig = load("res://config/default_config.tres").duplicate()
	cfg.world_seed = seed_value
	main = load("res://scenes/main.tscn").instantiate()
	main.config = cfg
	add_child(main)
	# name, run until this time of day (fraction), camera distance, yaw (deg), focus offset, select villager
	if has_meta("culture"):
		var d0 := float(SimClock.get_day() - 1) + SimClock.get_time_of_day()
		shots = [
			["culture_village", d0 + 0.02, 34.0, 35.0, Vector3.ZERO, false],
			["culture_closeup", d0 + 0.04, 13.0, 20.0, Vector3.ZERO, true],
			["culture_panel", d0 + 0.06, 40.0, 60.0, Vector3.ZERO, false],
			["culture_inspector", d0 + 0.08, 14.0, 30.0, Vector3.ZERO, true],
		]
		return
	shots = [
		["overview_morning", 0.32, 60.0, 35.0, Vector3.ZERO, false],
		["camp_closeup", 0.45, 16.0, 20.0, Vector3.ZERO, true],
		["wide_valley", 0.55, 95.0, 200.0, Vector3.ZERO, false],
		["building", 0.6, 22.0, 100.0, Vector3.ZERO, false],
		["evening", 0.76, 40.0, 60.0, Vector3.ZERO, false],
		["night", 0.95, 30.0, 60.0, Vector3.ZERO, false],
		["placement", 1.30, 30.0, 10.0, Vector3(8, 0, -10), false],
		["inspector", 3.4, 18.0, 30.0, Vector3.ZERO, true],
		["tribe_panel", 3.6, 40.0, 60.0, Vector3.ZERO, false],
		["chronicle", 3.8, 40.0, 60.0, Vector3.ZERO, false],
	]


func _process(_delta: float) -> void:
	frame += 1
	if frame < 10:
		return
	if _shot_index >= mini(shots.size(), int(get_meta("max_shots", 99))):
		get_tree().quit(0)
		return
	var shot: Array = shots[_shot_index]
	if _wait == 0:
		# Fast-forward the simulation for this shot.
		SimClock.set_time_scale(8.0)
		_wait = 1
		return
	var target_time: float = shot[1]
	var now := SimClock.get_time_of_day() + (SimClock.get_day() - 1)
	if now < target_time:
		return
	if _wait == 1:
		SimClock.set_time_scale(1.0)
		var cam := main.rts_camera
		cam._target_distance = shot[2]
		cam._target_yaw = deg_to_rad(shot[3])
		var focus: Vector3 = main.tribe.center + shot[4]
		if shot[0] == "building":
			for b in main.tribe.buildings:
				if b.def.id == &"hut":
					focus = b.global_position
		cam.focus_on(focus, true)
		if shot[5] and not main.tribe.villagers.is_empty():
			main.interaction.select(main.tribe.villagers[0])
		else:
			main.interaction.select(null)
		main.interaction.cancel_placement()
		var panels: SocietyPanels = main.hud.panels
		panels.inspect_mode = false
		panels._chronicle.visible = false
		panels._tribe.visible = false
		panels._culture.visible = false
		if shot[0] == "culture_village" or shot[0] == "culture_closeup":
			for b in main.tribe.buildings:
				if b.def.id in [&"gathering_circle", &"totem", &"memorial_stone"] and b.is_complete:
					focus = b.global_position
					break
			if shot[0] == "culture_closeup":
				# Show someone wearing the tribe's colours.
				for v in main.tribe.villagers:
					if v.adornment.has("sash"):
						focus = v.global_position
						main.interaction.select(v)
						break
			cam.focus_on(focus, true)
		match shot[0]:
			"inspector", "culture_inspector": panels.toggle_inspect()
			"culture_panel": panels.toggle_culture()
			"tribe_panel": panels.toggle_tribe()
			"chronicle": panels.toggle_chronicle()
		if shot[0] == "placement":
			main.interaction.begin_placement(BuildingCatalog.get_def(&"hut"))
			Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5)
		_wait = 2
		set_meta("frames", 0)
		return
	set_meta("frames", int(get_meta("frames")) + 1)
	if int(get_meta("frames")) < 20:
		return
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [out_dir, _shot_index, shot[0]]
	img.save_png(path)
	print("saved ", path, "  time ", SimClock.get_clock_string())
	_shot_index += 1
	_wait = 0
