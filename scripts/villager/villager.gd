class_name Villager
extends CharacterBody3D
## A single member of the tribe.
##
## The villager is a composition root: needs, inventory, movement and the
## brain are separate objects, and the current activity is a VillagerTask.
## Villagers never talk to the UI; they expose state and emit EventBus events.

signal died(villager: Villager, cause: String)
signal state_changed(villager: Villager, state: int)

const COLLISION_LAYER := 2  # bit 2 -> "villagers"

var villager_id: int = 0
var villager_name: String = "Villager"
var age_years: float = 20.0
## &"female" or &"male" (used by the reproduction model).
var sex: StringName = &"female"
## Parent villager ids (empty for founders).
var parent_ids: Array[int] = []
## Day of birth inside the simulation (founders: -1).
var born_day: int = -1
var tunic_color := Color(0.7, 0.3, 0.25)
var hair_color := MeshFactory.C_HAIR

var ctx: WorldContext
var needs: VillagerNeeds
var inventory: VillagerInventory
var knowledge: VillagerKnowledge
var movement: VillagerMovement
var brain: VillagerBrain
var personality: Personality
var memory := VillagerMemory.new()
var emotions := Emotions.new()
var skills: VillagerSkills
## Social standing (0..100): earned through skill, success, help and leadership.
var prestige := 10.0
## Emergent occupation (&"" until one develops), see ProfessionSystem.
var profession: StringName = &""
## Pregnancy progress in days (-1 = not pregnant), and the other parent.
var pregnancy_days := -1.0
var pregnancy_partner := -1
var last_birth_day := -1000
## Tools carried for work (durability in work-seconds left, 0 = none).
var tool_durability := 0.0
## Last things said and heard, for the inspector ("Aru -> Bela: ...").
var conversation_log: Array[String] = []

var state: int = VillagerState.IDLE
var current_task: VillagerTask
## Hut where this villager sleeps (claimed on first rest).
var home: Building
var is_dead := false
## Set by the active task: 0 = resting .. 1 = hard work. Drives energy use.
var activity := 0.5
## > 0 while resting; multiplies energy recovery.
var rest_multiplier := 0.0

var _visual_root: Node3D
var _body: MeshInstance3D
var _carry: MeshInstance3D
var _anim_time := 0.0
var _yaw := 0.0
var _hidden := false
## Positions at the previous and current sim tick; the model is drawn between them.
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _bubble: Label3D
var _bubble_time := 0.0


func setup(context: WorldContext, id: int, display_name: String, age: float, tunic: Color, hair: Color,
		villager_sex: StringName = &"female", inherited: Personality = null, inherited_skills: VillagerSkills = null) -> void:
	ctx = context
	sex = villager_sex
	villager_id = id
	villager_name = display_name
	age_years = age
	tunic_color = tunic
	hair_color = hair
	needs = VillagerNeeds.new(ctx.config)
	inventory = VillagerInventory.new(ctx.config.carry_capacity)
	movement = VillagerMovement.new(self, ctx.nav, ctx.terrain, ctx.config.move_speed)
	knowledge = VillagerKnowledge.new(self)
	var prng := RandomNumberGenerator.new()
	prng.seed = hash([ctx.social.social_seed() if ctx.social else ctx.world_seed, id, "personality"])
	personality = inherited if inherited != null else Personality.generate(prng)
	needs.social_rate_mult = lerpf(0.4, 1.8, personality.get_trait(&"social_need"))
	skills = inherited_skills if inherited_skills != null else VillagerSkills.generate(prng, age)
	brain = VillagerBrain.new(self)
	brain.add_modifier(HabitModifier.new())
	brain.add_modifier(PersonalityModifier.new())
	brain.add_modifier(SocialModifier.new())
	brain.add_modifier(EmotionModifier.new())
	brain.add_modifier(ProfessionModifier.new())


func _ready() -> void:
	collision_layer = COLLISION_LAYER
	collision_mask = 0
	name = "Villager_%d" % villager_id
	_visual_root = Node3D.new()
	_visual_root.name = "Visual"
	add_child(_visual_root)
	_body = MeshInstance3D.new()
	_body.mesh = MeshFactory.villager_body(tunic_color, hair_color)
	_visual_root.add_child(_body)
	update_age_visual()
	_carry = MeshInstance3D.new()
	_carry.position = Vector3(0, 1.05, 0.32)
	_carry.visible = false
	_visual_root.add_child(_carry)
	inventory.changed.connect(_update_carry_visual)
	_anim_time = randf() * 10.0
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.font_size = 44
	_bubble.outline_size = 12
	_bubble.pixel_size = 0.006
	_bubble.modulate = Color(1, 0.98, 0.9)
	_bubble.outline_modulate = Color(0.1, 0.08, 0.06, 0.9)
	_bubble.width = 420.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.visible = false
	add_child(_bubble)


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------

func sim_tick(dt: float) -> void:
	if is_dead:
		return
	needs.tick(dt, activity, rest_multiplier)
	var old_age := int(age_years)
	age_years += dt / maxf(1.0, ctx.config.day_length_seconds * ctx.config.days_per_year)
	if int(age_years) != old_age:
		update_age_visual()
	if needs.is_dead():
		die("starvation" if needs.hunger >= 100.0 else "exhaustion")
		return
	movement.sim_check(dt)
	brain.tick(dt)
	if current_task != null:
		var task := current_task
		var status := task.tick(dt)
		# A task may hand over to another one mid-tick (e.g. starting a conversation).
		if status != VillagerTask.Status.RUNNING and current_task == task:
			_end_current_task()
	# Movement runs in fixed sim steps (deterministic); _process only interpolates.
	_prev_pos = _cur_pos
	movement.update(dt, needs.performance())
	_cur_pos = global_position


## Teleports without interpolation (spawning, loading).
func place_at(pos: Vector3) -> void:
	global_position = pos
	_prev_pos = pos
	_cur_pos = pos


## Where the model is drawn this frame (between sim ticks).
func get_visual_position() -> Vector3:
	return _prev_pos.lerp(_cur_pos, SimClock.get_tick_alpha())


## Replaces the current task. The new task must already be started, so callers
## should end the old task first (set_task(null)) if starting has side effects
## the old task's cleanup could undo.
func set_task(task: VillagerTask) -> void:
	_end_current_task()
	current_task = task


func _end_current_task() -> void:
	if current_task == null:
		return
	var t := current_task
	current_task = null
	t.finish()
	activity = 0.5
	rest_multiplier = 0.0
	set_hidden(false)
	if state != VillagerState.DEAD:
		set_state(VillagerState.IDLE)


func set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(self, s)


# --------------------------------------------------------------------------
# Life stages
# --------------------------------------------------------------------------

func life_stage() -> StringName:
	var cfg := ctx.config
	if age_years < cfg.youth_age:
		return &"child"
	if age_years < cfg.adult_age:
		return &"youth"
	if age_years < cfg.elder_age:
		return &"adult"
	return &"elder"


func is_child() -> bool:
	return age_years < ctx.config.youth_age


func is_adult() -> bool:
	return age_years >= ctx.config.adult_age


## Children don't work; youths and elders work at reduced capacity.
func work_capacity() -> float:
	match life_stage():
		&"child": return 0.0
		&"youth": return 0.65
		&"elder": return 0.75
	return 1.0


## Work speed for an activity: skill, tools, life stage, stress.
func work_efficiency(skill: StringName) -> float:
	var e := skills.efficiency(skill) * maxf(0.3, work_capacity()) * needs.performance()
	if tool_durability > 0.0 and VillagerSkills.TOOL_SKILLS.has(skill):
		e *= 1.35
	e *= 1.0 - 0.25 * emotions.get_value(&"stress")
	if ctx.society:
		e *= ctx.society.groups.guild_bonus(self)
	return e


## Practising a skill: improves it and wears down tools.
func practice(skill: StringName, seconds: float) -> void:
	var before := int(skills.get_level(skill))
	skills.practice(skill, seconds, personality)
	if tool_durability > 0.0 and VillagerSkills.TOOL_SKILLS.has(skill):
		tool_durability = maxf(0.0, tool_durability - seconds)
	var after := int(skills.get_level(skill))
	if ctx.society and before < VillagerSkills.MASTERY and after >= VillagerSkills.MASTERY:
		ctx.society.on_skill_mastered(self, skill)


func get_region() -> int:
	return ctx.nav.access_region(global_position)


func get_task_description() -> String:
	if current_task == null:
		return VillagerState.label(state)
	return current_task.describe()


## Reports a meaningful action. `data` must hold plain values only (ids, numbers,
## strings, vectors) - never nodes - so the event can be remembered or saved.
func record_event(event_name: StringName, data: Dictionary = {}) -> void:
	var payload := data.duplicate()
	payload["villager_id"] = villager_id
	payload["time"] = SimClock.sim_time
	payload["day"] = SimClock.get_day()
	payload["position"] = global_position
	EventBus.villager_event.emit(self, event_name, payload)


## Children are smaller; hair greys in old age.
func update_age_visual() -> void:
	if _body == null:
		return
	var growth := clampf(age_years / ctx.config.adult_age, 0.0, 1.0)
	_body.scale = Vector3.ONE * lerpf(0.5, 1.0, growth)
	var hair := hair_color
	if age_years >= ctx.config.elder_age:
		hair = hair_color.lerp(Color(0.82, 0.82, 0.8), clampf((age_years - ctx.config.elder_age) / 12.0, 0.3, 1.0))
		hair = Color(snappedf(hair.r, 0.1), snappedf(hair.g, 0.1), snappedf(hair.b, 0.1))
	_body.mesh = MeshFactory.villager_body(tunic_color, hair)


## Speech bubble above the head (presentation only).
func say(text: String, seconds: float = 3.5, color: Color = Color(1, 0.98, 0.9)) -> void:
	if _bubble == null or text == "":
		return
	_bubble.text = text
	_bubble.modulate = color
	_bubble.visible = true
	_bubble_time = seconds


func remember_line(line: String, other_name: String) -> void:
	if line == "":
		return
	conversation_log.append("to %s: \"%s\"" % [other_name, line])
	if conversation_log.size() > 6:
		conversation_log.pop_front()


func die(cause: String) -> void:
	if is_dead:
		return
	is_dead = true
	_end_current_task()
	set_state(VillagerState.DEAD)
	if home != null and is_instance_valid(home):
		home.release_bed(self)
	died.emit(self, cause)


# --------------------------------------------------------------------------
# Presentation
# --------------------------------------------------------------------------

func set_hidden(value: bool) -> void:
	_hidden = value
	if _visual_root:
		_visual_root.visible = not value


func is_hidden() -> bool:
	return _hidden


func face_towards(p: Vector3) -> void:
	movement.facing_target = p


func _process(delta: float) -> void:
	if is_dead:
		return
	_animate(SimClock.scaled_delta(delta))


func _animate(dt: float) -> void:
	_anim_time += dt
	var target := movement.facing_target
	if target != Vector3.INF:
		var to := target - global_position
		to.y = 0.0
		if to.length_squared() > 0.0004:
			var desired := atan2(-to.x, -to.z)
			_yaw = lerp_angle(_yaw, desired, clampf(dt * 10.0, 0.0, 1.0))
	var pos := get_visual_position() - global_position
	var rot := Vector3(0, _yaw, 0)
	if movement.is_moving():
		pos.y += absf(sin(_anim_time * 11.0)) * 0.08
		rot.z = sin(_anim_time * 11.0) * 0.06
	elif state == VillagerState.GATHERING or state == VillagerState.BUILDING:
		# Chopping / hammering motion.
		var s := sin(_anim_time * 9.0)
		rot.x = -maxf(0.0, s) * 0.35
		pos.y += maxf(0.0, -s) * 0.03
	elif current_task is ConverseTask:
		var st: StringName = (current_task as ConverseTask).style
		if st == &"fight":
			var f := sin(_anim_time * 14.0)
			rot.x = -maxf(0.0, f) * 0.5
			pos.y += absf(f) * 0.06
		elif st == &"argue":
			rot.z = sin(_anim_time * 7.0) * 0.08
		elif st == &"romance":
			rot.x = 0.08
			pos.y += absf(sin(_anim_time * 2.0)) * 0.02
	elif state == VillagerState.EATING:
		rot.x = sin(_anim_time * 6.0) * 0.08 - 0.1
	elif state == VillagerState.RESTING:
		# Lying down beside the campfire.
		rot.x = -PI * 0.5
		pos.y += 0.18
	_visual_root.position = pos
	_visual_root.rotation = rot
	if _bubble_time > 0.0:
		_bubble_time -= dt
		_bubble.position = get_visual_position() - global_position + Vector3(0, 2.2, 0)
		_bubble.visible = _bubble_time > 0.0 and not _hidden


func _update_carry_visual() -> void:
	if inventory.is_empty():
		_carry.visible = false
		return
	_carry.mesh = MeshFactory.carried_item(inventory.carried_type)
	_carry.visible = true
