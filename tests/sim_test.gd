extends Node
## Automated gameplay test. Runs the real main scene at high simulation speed
## and checks the milestone acceptance criteria.
##
## Run:  godot --headless --path . res://tests/sim_test.tscn --fixed-fps 60 -- --seed=1234 --days=3

var main: Main
var seed_value := 1234
var days := 3.0
var frame := 0
var phase := "setup"
var failures: PackedStringArray = []
var stats := {
	"ate": 0, "delivered": {0: 0, 1: 0, 2: 0}, "buildings_completed": 0, "deaths": 0,
	"max_hunger": 0.0, "events": 0, "bad_events": 0, "min_energy": 100.0, "states_seen": {}, "night_sun_energy": -1.0, "day_sun_energy": -1.0,
}
var _last_positions := {}
var _distance := {}
var _idle_ticks := {}
var _sample_timer := 0.0
var _pause_sim_time := 0.0
var _start_day := 1
## Scenario: no food anywhere -> villagers must die cleanly.
var starve := false
## Scenario: food exists but is rare -> sharing, refusals, grief.
var scarce := false
## Stress test: spawn this many additional villagers and measure tick cost.
var extra_villagers := 0
var _frame_usec_total := 0
var _frame_count := 0
var _frame_start := 0
## Determinism mode: run without interaction and print a state hash at this tick.
var hash_at_tick := 0
var social_seed := 0
## Print where homes ended up (compare runs with different social seeds).
var print_layout := false
## Chronicle lines to print at the end.
var history_lines := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.split("=")[1])
		elif arg.begins_with("--days="):
			days = float(arg.split("=")[1])
		elif arg == "--starve":
			starve = true
		elif arg == "--scarce":
			scarce = true
		elif arg.begins_with("--extra-villagers="):
			extra_villagers = int(arg.split("=")[1])
		elif arg.begins_with("--hash-at-tick="):
			hash_at_tick = int(arg.split("=")[1])
		elif arg.begins_with("--social-seed="):
			social_seed = int(arg.split("=")[1])
		elif arg == "--layout":
			print_layout = true
		elif arg.begins_with("--history="):
			history_lines = int(arg.split("=")[1])
	# Headless windows default to 64x64, where the HUD would cover everything.
	get_tree().root.size = Vector2i(1600, 900)
	var cfg: GameConfig = load("res://config/default_config.tres").duplicate()
	cfg.world_seed = seed_value
	cfg.social_seed = social_seed
	if scarce:
		cfg.bush_count = 10
		cfg.start_area_bushes = 3
		cfg.starting_food = 0
		cfg.bush_regrow_interval = 60.0
	if starve:
		cfg.bush_count = 0
		cfg.start_area_bushes = 0
		cfg.starting_food = 0
	main = load("res://scenes/main.tscn").instantiate()
	main.config = cfg
	add_child(main)
	EventBus.villager_event.connect(_on_villager_event)
	if hash_at_tick > 0:
		SimClock.sim_tick.connect(_on_tick_for_hash)
	EventBus.building_completed.connect(func(_b): stats.buildings_completed += 1)
	EventBus.villager_died.connect(func(_v, _c): stats.deaths += 1)
	print("[test] seed=%d days=%.1f starve=%s extra=%d" % [seed_value, days, starve, extra_villagers])


func _on_villager_event(_v: Node, event_name: StringName, data: Dictionary) -> void:
	stats.events += 1
	# Memory/persistence contract: plain values only, with who/when/where.
	for key in ["villager_id", "time", "day", "position"]:
		if not data.has(key):
			stats.bad_events += 1
	for value in data.values():
		if typeof(value) == TYPE_OBJECT:
			stats.bad_events += 1
	match event_name:
		&"ate":
			stats.ate += 1
		&"delivered":
			stats.delivered[int(data["resource_type"])] += int(data["amount"])


func check(cond: bool, what: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", what])
	if not cond:
		failures.append(what)


func _process(delta: float) -> void:
	frame += 1
	match phase:
		"setup":
			if frame < 5:
				return
			if hash_at_tick > 0:
				SimClock.set_time_scale(8.0)
				phase = "hash_wait"
				return
			if extra_villagers > 0:
				_spawn_extra()
				phase = "run_setup"
				return
			if scarce:
				# Crisis: everyone starts hungry with nothing stored.
				for v in main.tribe.villagers:
					v.needs.hunger = 55.0 + v.villager_id * 3.0
			_initial_checks()
			_ui_checks()
			if not starve:
				_build_flow_checks()
			_input_checks()
			phase = "input_wait"
		"input_wait", "hash_wait":
			return
		"input_done":
			phase = "pause_test"
			_pause_sim_time = SimClock.sim_time
			SimClock.set_paused(true)
		"pause_test":
			if frame < 40:
				return
			check(is_equal_approx(SimClock.sim_time, _pause_sim_time), "Pause freezes simulation time")
			SimClock.set_paused(false)
			SimClock.set_time_scale(8.0)
			_start_day = SimClock.get_day()
			phase = "run"
		"run_setup":
			SimClock.set_time_scale(8.0)
			_start_day = SimClock.get_day()
			phase = "run"
		"run":
			if _frame_start > 0:
				_frame_usec_total += Time.get_ticks_usec() - _frame_start
				_frame_count += 1
			_frame_start = Time.get_ticks_usec()
			_sample(SimClock.scaled_delta(delta))
			if SimClock.sim_time >= days * SimClock.day_length:
				if extra_villagers > 0:
					_perf_report()
				elif starve:
					_starve_checks()
				elif scarce:
					_scarce_checks()
				else:
					_final_checks()
					_social_checks()
				if print_layout:
					_print_layout()
				_society_report()
				phase = "done"
				print("[test] RESULT: %s (%d failures)" % ["OK" if failures.is_empty() else "FAILED", failures.size()])
				for f in failures:
					print("   - " + f)
				get_tree().quit(0 if failures.is_empty() else 1)


func _initial_checks() -> void:
	var tribe := main.tribe
	print("[test] initial checks")
	check(main.terrain.get_node("TerrainMesh").mesh.get_faces().size() > 1000, "Terrain mesh is real 3D geometry")
	check(tribe.population() == 8, "Exactly eight villagers at start (got %d)" % tribe.population())
	var ids := {}
	for v in tribe.villagers:
		ids[v.villager_id] = true
	check(ids.size() == 8, "Villagers have unique ids")
	if not starve and not scarce:
		check(main.ctx.resources.get_nodes(ResourceType.FOOD).size() > 20, "Food sources exist")
	check(main.ctx.resources.get_nodes(ResourceType.WOOD).size() > 50, "Trees exist")
	check(main.ctx.resources.get_nodes(ResourceType.STONE).size() > 10, "Rocks exist")
	var near := {0: 0, 1: 0, 2: 0}
	for n in main.ctx.resources.all_nodes():
		if n.global_position.distance_to(tribe.center) < 35.0 and n.region_id == main.ctx.nav.access_region(tribe.center):
			near[n.resource_type] += 1
	check((starve or scarce or near[0] >= 8) and near[1] >= 10 and near[2] >= 4, "Start area has reachable food/wood/stone %s" % str(near))
	check(tribe.campfire != null and tribe.storage != null, "Campfire and stockpile exist")
	var entity_ids := {}
	for n in main.ctx.resources.all_nodes():
		entity_ids[n.entity_id] = true
	for b in tribe.buildings:
		entity_ids[b.entity_id] = true
	check(not entity_ids.has(0) and entity_ids.size() == main.ctx.resources.all_nodes().size() + tribe.buildings.size(),
			"World objects have unique stable entity ids")
	check(tribe.housing_capacity() >= 4, "Starting shelters exist (beds=%d)" % tribe.housing_capacity())

	# Camera: zoom / rotate / focus.
	var cam := main.rts_camera
	var d0 := cam._target_distance
	cam.zoom(-2.0)
	check(cam._target_distance < d0, "Camera zooms in")
	cam.zoom(50.0)
	check(is_equal_approx(cam._target_distance, cam.max_distance), "Camera zoom is clamped")
	cam.zoom(-50.0)
	check(is_equal_approx(cam._target_distance, cam.min_distance), "Camera zoom min clamped")
	var y0 := cam._target_yaw
	cam.rotate_yaw(0.5)
	check(not is_equal_approx(cam._target_yaw, y0), "Camera rotates")
	cam.focus_on(Vector3(1000, 0, 1000), true)
	cam._process(0.016)
	check(absf(cam.global_position.x) <= cam.bounds_half + 0.01, "Camera clamped to world bounds")
	cam.focus_on(tribe.center, true)
	cam.zoom(2.0)

	# Raycast selection of a villager through the real camera.
	var v: Villager = tribe.villagers[0]
	cam.focus_on(v.global_position, true)
	var screen := cam.camera.unproject_position(v.global_position + Vector3(0, 0.8, 0))
	var hit := main.interaction._pick(screen)
	check(hit["target"] == v, "Raycast picks the villager under the cursor")
	main.interaction.select(v)
	check(main.interaction.selected == v, "Villager can be selected")
	cam.focus_on(tribe.center, true)

	# Player placement validation.
	var hut := BuildingCatalog.get_def(&"hut")
	check(tribe.can_place(hut, tribe.campfire.global_position) != "", "Can't place a hut on top of the campfire")
	check(tribe.can_place(hut, main.terrain.snap_to_ground(Vector3(main.terrain.lake_center.x, 0, main.terrain.lake_center.y))) != "", "Can't place a hut in the lake")


func _sample(dt: float) -> void:
	var tribe := main.tribe
	for v in tribe.villagers:
		stats.max_hunger = maxf(stats.max_hunger, v.needs.hunger)
		stats.min_energy = minf(stats.min_energy, v.needs.energy)
		stats.states_seen[VillagerState.label(v.state)] = true
		var last: Vector3 = _last_positions.get(v.villager_id, v.global_position)
		_distance[v.villager_id] = float(_distance.get(v.villager_id, 0.0)) + last.distance_to(v.global_position)
		_last_positions[v.villager_id] = v.global_position
		if v.state == VillagerState.IDLE:
			_idle_ticks[v.villager_id] = int(_idle_ticks.get(v.villager_id, 0)) + 1
	var tod := SimClock.get_time_of_day()
	if absf(tod - 0.5) < 0.01:
		stats.day_sun_energy = main.day_night.sun.light_energy
	if tod < 0.02 or tod > 0.98:
		stats.night_sun_energy = main.day_night.sun.light_energy
	_sample_timer += dt
	if _sample_timer >= SimClock.day_length / 4.0:
		_sample_timer = 0.0
		var s := tribe.stockpile
		var hist := {}
		for v in tribe.villagers:
			var k := VillagerState.label(v.state)
			hist[k] = int(hist.get(k, 0)) + 1
		print("[test] day %d %s pop=%d food=%d wood=%d stone=%d beds=%d sites=%d states=%s" % [
			SimClock.get_day(), SimClock.get_clock_string(), tribe.population(), s.get_amount(0), s.get_amount(1),
			s.get_amount(2), tribe.housing_capacity(), tribe.construction_sites().size(), str(hist)])


func _final_checks() -> void:
	var tribe := main.tribe
	print("[test] final checks after %.0f sim seconds" % SimClock.sim_time)
	print("[test] stats: %s" % str(stats))
	check(stats.events > 0 and stats.bad_events == 0, "Villager events are serializable with who/when/where (%d events)" % stats.events)
	check(stats.ate > 0, "Hungry villagers found and ate food (%d meals)" % stats.ate)
	check(stats.delivered[ResourceType.FOOD] > 0, "Food gathered and delivered (%d)" % stats.delivered[ResourceType.FOOD])
	check(stats.delivered[ResourceType.WOOD] > 0, "Wood gathered and delivered (%d)" % stats.delivered[ResourceType.WOOD])
	check(stats.delivered[ResourceType.STONE] > 0, "Stone gathered and delivered (%d)" % stats.delivered[ResourceType.STONE])
	check(stats.buildings_completed >= 1, "At least one hut built (%d)" % stats.buildings_completed)
	check(stats.max_hunger > 20.0, "Hunger changes over time (max %.1f)" % stats.max_hunger)
	check(stats.min_energy < 90.0, "Energy changes over time (min %.1f)" % stats.min_energy)
	check(stats.states_seen.has("Resting"), "Villagers rest")
	check(stats.states_seen.has("Gathering"), "Villagers gather")
	check(stats.states_seen.has("Building"), "Villagers build")
	check(tribe.population() >= 7, "Tribe survives on its own (pop %d, deaths %d)" % [tribe.population(), stats.deaths])
	check(SimClock.get_day() > _start_day, "Days advance (day %d)" % SimClock.get_day())
	check(stats.day_sun_energy > 0.8 and stats.night_sun_energy >= 0.0 and stats.night_sun_energy < 0.05,
			"Sun bright at noon (%.2f) and off at midnight (%.2f)" % [stats.day_sun_energy, stats.night_sun_energy])
	var total_ticks := 0
	for v in tribe.villagers:
		var dist: float = _distance.get(v.villager_id, 0.0)
		check(dist > 100.0, "%s travelled %.0f m (not stuck)" % [v.villager_name, dist])
	var counted := {0: 0, 1: 0, 2: 0}
	var s := tribe.stockpile
	for k in ResourceType.ALL:
		counted[k] = s.total_delivered[k] - s.total_consumed[k]
	# Stockpile counters must equal initial + delivered - consumed (+ refunds, none expected).
	check(s.get_amount(0) == main.config.starting_food + counted[0], "Food counter consistent")
	check(s.get_amount(1) == main.config.starting_wood + counted[1], "Wood counter consistent")
	check(s.get_amount(2) == main.config.starting_stone + counted[2], "Stone counter consistent")


func _spawn_extra() -> void:
	var tribe := main.tribe
	for i in extra_villagers:
		var a := TAU * i / extra_villagers
		var p := tribe.center + Vector3(cos(a), 0, sin(a)) * (4.0 + (i % 5))
		var cell := main.ctx.nav.nearest_walkable_cell(main.ctx.nav.world_to_cell(p), 6)
		tribe.add_villager(main.ctx.nav.cell_to_world(cell), 25.0)
	print("[test] spawned %d extra villagers (population %d)" % [extra_villagers, tribe.population()])


func _perf_report() -> void:
	# Measure a few isolated simulation ticks for a precise number.
	var tribe := main.tribe
	var avg_frame := _frame_usec_total / maxf(1.0, _frame_count) / 1000.0
	print("[test] PERF population=%d  sim tick mean=%.2f ms max=%.2f ms  avg frame (8x speed, headless)=%.2f ms" % [
		tribe.population(), tribe.perf_mean_tick_ms(), tribe.perf_max_tick_ms, avg_frame])
	var sections: PackedStringArray = []
	for k in tribe.perf_sections:
		sections.append("%s=%.2f" % [k, tribe.perf_sections[k] / maxf(1.0, tribe.perf_ticks)])
	print("[test] PERF per-tick sections (ms): %s" % " ".join(sections))
	var maxes: PackedStringArray = []
	for k in tribe.perf_section_max:
		maxes.append("%s=%.1f" % [k, tribe.perf_section_max[k]])
	print("[test] PERF worst tick per section (ms): %s" % " ".join(maxes))
	print("[test] PERF worst culture step (ms): %s" % str(main.ctx.society.culture.step_max_ms))
	check(tribe.population() > 0, "Large population still alive")
	check(tribe.perf_mean_tick_ms() < 15.0, "Mean sim tick under 15 ms with %d villagers (%.2f ms)" % [tribe.population(), tribe.perf_mean_tick_ms()])


func _ui_checks() -> void:
	print("[test] UI checks (pressing the real HUD buttons)")
	var hud := main.hud
	hud._pause_button.pressed.emit()
	check(SimClock.paused, "Pause button pauses")
	hud._pause_button.pressed.emit()
	check(not SimClock.paused, "Pause button resumes")
	hud._speed_buttons[2].pressed.emit()
	check(is_equal_approx(SimClock.time_scale, 4.0) and hud._speed_buttons[2].button_pressed, "4x speed button")
	hud._speed_buttons[0].pressed.emit()
	check(is_equal_approx(SimClock.time_scale, 1.0), "1x speed button")
	main.rts_camera.focus_on(Vector3(30, 0, 30), true)
	hud._focus_home()
	check(main.rts_camera._target_pos.distance_to(Vector3(main.tribe.center.x, 0, main.tribe.center.z)) < 0.01, "Return-to-camp button recentres camera")
	var hut_button: Button = hud._build_buttons[&"hut"]
	hut_button.pressed.emit()
	check(main.interaction.is_placing(), "Hut button enters placement mode")
	check(hud._build_hint.visible, "Placement hint shown")
	hut_button.pressed.emit()
	check(not main.interaction.is_placing(), "Hut button again cancels placement")
	var auto := main.tribe.auto_build
	hud._auto_build_check.toggled.emit(not auto)
	check(main.tribe.auto_build == (not auto), "Auto-build checkbox toggles the planner")
	hud._auto_build_check.toggled.emit(auto)
	var v: Villager = main.tribe.villagers[1]
	main.interaction.select(v)
	check(hud._sel_panel.visible and hud._sel_title.text == v.villager_name, "Selection panel shows the villager")
	hud._sel_follow.pressed.emit()
	check(main.rts_camera.is_following(), "Follow button follows the villager")
	hud._sel_follow.pressed.emit()
	check(not main.rts_camera.is_following(), "Follow button toggles off")
	main.interaction.select(null)
	check(not hud._sel_panel.visible, "Selection panel hides on deselect")
	main.rts_camera.focus_on(main.tribe.center, true)


func _build_flow_checks() -> void:
	print("[test] player construction flow")
	var tribe := main.tribe
	var hut := BuildingCatalog.get_def(&"hut")
	var spot := tribe.find_build_spot(hut)
	check(spot != Vector3.INF, "Found a valid hut spot")
	var site := tribe.place_building(hut, spot, true)
	check(site != null and site.is_construction_site(), "Player can place a hut site")
	check(tribe.place_building(hut, spot, true) == null, "Overlapping hut is rejected")
	check(not main.ctx.nav.is_walkable(spot), "Site blocks navigation cells")
	# Cancel refunds delivered materials and frees the ground.
	var wood_before := tribe.stockpile.get_amount(ResourceType.WOOD)
	site.complete_delivery(ResourceType.WOOD, 0)
	tribe.cancel_construction(site)
	await get_tree().process_frame
	check(not is_instance_valid(site), "Cancelled site removed")
	check(main.ctx.nav.is_walkable(spot), "Cancelled site frees navigation")
	check(tribe.stockpile.get_amount(ResourceType.WOOD) == wood_before, "Cancel refunds exactly what was delivered")
	# Place again and leave it for the villagers.
	tribe.place_building(hut, spot, true)


func _starve_checks() -> void:
	print("[test] starvation scenario checks")
	print("[test] social stats: %s" % str(main.ctx.social.stats))
	check(stats.deaths > 0, "Villagers die when no food exists (%d deaths)" % stats.deaths)
	check(main.tribe.population() == 8 - stats.deaths, "Population counter matches deaths")
	var graves := 0
	for n in main.ctx.world_root.get_children():
		if n is MeshInstance3D and n.mesh == MeshFactory.grave_marker():
			graves += 1
	check(graves == stats.deaths, "A grave marks each death (%d)" % graves)
	for v in main.tribe.villagers:
		check(is_instance_valid(v) and not v.is_dead, "Surviving list holds only living villagers")


## Feeds real input events through the viewport / Input singleton.
func _input_checks() -> void:
	print("[test] real input events")
	var cam := main.rts_camera
	var vp := get_viewport()
	cam.focus_on(main.tribe.center, true)
	var start := cam._target_pos
	Input.action_press(&"cam_right")
	for i in 20:
		await get_tree().process_frame
	Input.action_release(&"cam_right")
	check(cam._target_pos.distance_to(start) > 1.0, "D key pans the camera (%.1f m)" % cam._target_pos.distance_to(start))
	cam.focus_on(main.tribe.center, true)

	var d0 := cam._target_distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = vp.get_visible_rect().size * 0.5
	vp.push_input(wheel)
	await get_tree().process_frame
	check(cam._target_distance < d0, "Mouse wheel zooms in")

	var yaw0 := cam._target_yaw
	var mmb := InputEventMouseButton.new()
	mmb.button_index = MOUSE_BUTTON_MIDDLE
	mmb.pressed = true
	mmb.position = vp.get_visible_rect().size * 0.5
	vp.push_input(mmb)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(120, 0)
	vp.push_input(motion)
	mmb = mmb.duplicate()
	mmb.pressed = false
	vp.push_input(mmb)
	await get_tree().process_frame
	check(not is_equal_approx(cam._target_yaw, yaw0), "Middle mouse drag rotates the camera")

	# A real left click on a villager selects it.
	SimClock.set_paused(true)
	var v: Villager = main.tribe.villagers[2]
	cam.focus_on(v.global_position, true)
	await get_tree().process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = cam.camera.unproject_position(v.global_position + Vector3(0, 0.8, 0))
	vp.push_input(click)
	await get_tree().process_frame
	if main.interaction.selected != v:
		print("    clicked ", main.interaction.selected, " pick=", main.interaction._pick(click.position), " villager hidden=", v.is_hidden(), " state=", VillagerState.label(v.state))
	check(main.interaction.selected == v, "Left click on a villager selects it")
	var rclick := click.duplicate()
	rclick.button_index = MOUSE_BUTTON_RIGHT
	vp.push_input(rclick)
	await get_tree().process_frame
	check(main.interaction.selected == null, "Right click deselects")
	SimClock.set_paused(false)
	cam.focus_on(main.tribe.center, true)
	phase = "input_done"


# --------------------------------------------------------------------------
# Social simulation
# --------------------------------------------------------------------------

func _social_checks() -> void:
	print("[test] social checks")
	var social := main.ctx.social
	var tribe := main.tribe
	print("[test] social stats: %s" % str(social.stats))
	check(social.stats.conversations >= 10, "Villagers hold conversations (%d)" % social.stats.conversations)
	check(social.stats.topics.size() >= 2, "Conversations cover several topics %s" % str(social.stats.topics))
	var bonds := 0
	for v in tribe.villagers:
		bonds += social.friends_of(v.villager_id).size() + social.rivals_of(v.villager_id).size()
		check(v.memory.short.size() <= VillagerMemory.SHORT_CAPACITY and v.memory.long.size() <= VillagerMemory.LONG_CAPACITY,
				"%s's memory stays bounded (%d short, %d long)" % [v.villager_name, v.memory.short.size(), v.memory.long.size()])
	check(bonds > 0 or social.stats.partnerships > 0, "Friendships or rivalries emerge (%d bond ends)" % bonds)
	var owned := 0
	for b in tribe.buildings:
		if b.def.id == &"hut" and not b.owner_ids.is_empty():
			owned += 1
	check(owned >= 3, "Homes belong to specific villagers (%d owned huts)" % owned)

	# Knowledge: a villager who knows nothing can't target anything.
	var v: Villager = tribe.villagers[0]
	var saved := v.knowledge.store
	v.knowledge.store = KnowledgeStore.new()
	var none_found := v.knowledge.find_resource(ResourceType.WOOD) == null and v.knowledge.find_resource(ResourceType.FOOD) == null
	v.knowledge.store = saved
	check(none_found, "Villagers can't use resources they don't know about")
	var unknown_ok := true
	for other in tribe.villagers:
		var r := other.knowledge.find_resource(ResourceType.WOOD)
		if r != null and other.knowledge.store.get_fact(r.entity_id) == null:
			unknown_ok = false
	check(unknown_ok, "Every resource a villager targets is one they know of")

	# Validation: outcomes can't create information or food from nothing.
	var a: Villager = tribe.villagers[0]
	var b: Villager = tribe.villagers[1]
	var o := ConversationOutcome.new()
	o.speaker_id = a.villager_id
	o.listener_id = b.villager_id
	o.facts_to_listener[999999] = {"type": 0, "pos": Vector3.ZERO, "amount": 5, "regrows": true, "time": 0.0, "source": -1}
	check(not o.validate(social), "Outcome sharing unknown information is rejected")
	o = ConversationOutcome.new()
	o.speaker_id = a.villager_id
	o.listener_id = b.villager_id
	o.food_giver = a.villager_id
	o.food_receiver = b.villager_id
	o.food_amount = 99
	check(not o.validate(social), "Outcome giving food nobody carries is rejected")

	# Personality biases decisions.
	var mod := PersonalityModifier.new()
	var p_saved := v.personality
	var hard := Personality.from_dict(p_saved.to_dict())
	var lazy := Personality.from_dict(p_saved.to_dict())
	hard.values[&"industriousness"] = 1.0
	lazy.values[&"industriousness"] = 0.0
	var s1 := {&"gather_wood": 0.4, &"idle": 0.1}
	var s2 := s1.duplicate()
	v.personality = hard
	mod.modify_scores(v, s1)
	v.personality = lazy
	mod.modify_scores(v, s2)
	v.personality = p_saved
	check(s1[&"gather_wood"] > s2[&"gather_wood"] and s1[&"idle"] < s2[&"idle"], "Industriousness changes work vs idle scores")

	# Helping in a crisis: a caring villager carrying food helps a starving friend.
	var giver: Villager = tribe.villagers[2]
	var needy: Villager = tribe.villagers[3]
	var gid := giver.villager_id
	var nid := needy.villager_id
	# Controlled setup: only `needy` is hungry, standing right next to the giver.
	for other in tribe.villagers:
		other.needs.hunger = 0.0
		other.set_hidden(false)
	needy.place_at(giver.global_position + Vector3(1.5, 0, 0))
	tribe._update_separation()  # refresh the proximity index for the new position
	needy.needs.hunger = 90.0
	needy.set_task(null)  # not already on the way to eat
	needy.inventory.take_all()
	giver.inventory.take_all()
	giver.inventory.add(ResourceType.FOOD, 5)
	social.graph.set_opinion(gid, nid, 0.6, 0.6)
	check(social.find_person_to_help(giver) == needy, "A starving friend is noticed by someone carrying food")
	social.graph.set_opinion(nid, gid, 0.0, 0.5)
	var aff_before := social.graph.affinity(nid, gid)
	var offer := social.conversations.decide(giver, needy, &"offer_food")
	check(offer.validate(social), "Food offer validates")
	offer.apply(social)
	check(needy.needs.hunger < 90.0 and giver.inventory.amount < 5, "Food changes hands (hunger %.0f)" % needy.needs.hunger)
	check(social.graph.affinity(nid, gid) > aff_before, "Being helped improves the opinion of the helper")
	var remembers := false
	for r in needy.memory.notable(10):
		if r.kind == &"was_helped" and r.other_id == gid:
			remembers = true
	check(remembers, "The helped villager remembers who helped them")
	giver.inventory.take_all()

	# Persistence: social state survives a save/load round trip.
	var before := var_to_str(social.to_dict())
	social.load_dict(str_to_var(before))
	check(var_to_str(social.to_dict()) == before, "Social state round-trips through to_dict/load_dict")


func _on_tick_for_hash(_dt: float) -> void:
	var every := OS.get_cmdline_user_args().has("--hash-every")
	if SimClock.tick_count != hash_at_tick and not (every and SimClock.tick_count % 5 == 0 and SimClock.tick_count > hash_at_tick - 80):
		return
	var parts: PackedStringArray = []
	for v in main.tribe.villagers:
		var p := v.global_position
		parts.append("%d:%.3f,%.3f,%.3f:%.3f:%.3f:%s" % [v.villager_id, p.x, p.y, p.z, v.needs.hunger, v.needs.energy,
			v.current_task.goal_id if v.current_task else "-"])
	parts.append(str(main.tribe.stockpile.amounts()))
	parts.append(var_to_str(main.ctx.social.to_dict()))
	print("[test] STATE_HASH tick=%d hash=%d" % [SimClock.tick_count, "|".join(parts).hash()])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hash-dump="):
			var f := FileAccess.open(arg.split("=")[1], FileAccess.WRITE)
			f.store_string("\n".join(parts) + "\n" + var_to_str(main.ctx.society.to_dict()))
			f.close()
	if SimClock.tick_count >= hash_at_tick:
		get_tree().quit(0)


func _print_layout() -> void:
	var homes: PackedStringArray = []
	for b in main.tribe.buildings:
		if b.def.id == &"hut":
			homes.append("(%.0f,%.0f)" % [b.global_position.x, b.global_position.z])
	print("[test] LAYOUT social_seed=%d huts=%s" % [social_seed, " ".join(homes)])


func _scarce_checks() -> void:
	print("[test] scarcity scenario checks")
	var st := main.ctx.social.stats
	print("[test] social stats: %s  deaths=%d" % [str(st), stats.deaths])
	check(st.conversations > 0, "Villagers still talk during scarcity")
	check(main.tribe.population() >= 6, "Most of the tribe survives scarcity (pop %d)" % main.tribe.population())


func _society_report() -> void:
	var soc := main.ctx.society
	var social := main.ctx.social
	print("[report] population=%d births=%d natural_deaths=%d deaths_total=%d" % [main.tribe.population(),
			soc.demographics.births, soc.demographics.natural_deaths, stats.deaths])
	print("[report] couples formed=%d breakups=%d current couples=%d" % [social.romance.couples_formed, social.romance.breakups,
			_current_couples()])
	print("[report] professions=%s" % str(soc.professions.known_professions.keys()))
	print("[report] discoveries=%s lost=%s" % [str(soc.tech.discovered.keys()), str(soc.tech.lost.keys())])
	print("[report] government=%s transitions=%d mediations=%d" % [soc.politics.government_label(), soc.politics.transitions, soc.politics.mediations])
	var gnames := []
	for g in soc.groups.groups.values():
		gnames.append("%s(%d)" % [g["name"], g["members"].size()])
	print("[report] groups=%s rivalries=%d" % [str(gnames), soc.groups.rivalries.size()])
	print("[report] culture=%s traditions=%s" % [soc.culture.describe(), str(soc.culture.tradition_names())])
	print("[report] proposals: completed=%d failed=%d open=%d  tools made=%d mode=%s" % [soc.proposals.completed, soc.proposals.failed,
			soc.proposals.open_count(), soc.economy.tools_made, soc.economy.mode_label()])
	var buildings := {}
	for b in main.tribe.buildings:
		buildings[String(b.def.id)] = int(buildings.get(String(b.def.id), 0)) + 1
	print("[report] buildings=%s" % str(buildings))
	print("[report] history counts=%s" % str(soc.history.counts))
	print("[report] topics=%s" % str(social.stats.topics))
	print("[report] promises kept=%d broken=%d" % [social.promises.kept, social.promises.broken])
	if OS.get_cmdline_user_args().has("--romance"):
		_romance_debug()
	for e in soc.history.entries.slice(maxi(0, soc.history.entries.size() - history_lines)):
		print("  [day %d] %s" % [e["day"], e["text"]])


func _romance_debug() -> void:
	var social := main.ctx.social
	var r := social.romance
	for a in main.tribe.villagers:
		if not r.eligible(a):
			continue
		var line := "%s(%s,%d,%s,partner=%s):" % [a.villager_name, a.sex, int(a.age_years), r.orientation.get(a.villager_id),
				social.name_of(social.partner_of(a.villager_id))]
		for b in main.tribe.villagers:
			if b == a or not r.eligible(b):
				continue
			var at := social.graph.attraction(a.villager_id, b.villager_id)
			if at > 0.0:
				var flirts := 0
				for m in a.memory.about(b.villager_id):
					if m.kind == &"flirted":
						flirts += m.count
				line += " %s=%.2f/f%d%s" % [b.villager_name, at, flirts, "C" if social.graph.has_tag(a.villager_id, b.villager_id, &"courting") else ""]
		print("[romance] " + line)


func _current_couples() -> int:
	var n := 0
	for v in main.tribe.villagers:
		if main.ctx.social.partner_of(v.villager_id) > v.villager_id:
			n += 1
	return n
