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
var tunic_color := Color(0.7, 0.3, 0.25)
var hair_color := MeshFactory.C_HAIR

var ctx: WorldContext
var needs: VillagerNeeds
var inventory: VillagerInventory
var knowledge: VillagerKnowledge
var movement: VillagerMovement
var brain: VillagerBrain

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


func setup(context: WorldContext, id: int, display_name: String, age: float, tunic: Color, hair: Color) -> void:
	ctx = context
	villager_id = id
	villager_name = display_name
	age_years = age
	tunic_color = tunic
	hair_color = hair
	needs = VillagerNeeds.new(ctx.config)
	inventory = VillagerInventory.new(ctx.config.carry_capacity)
	movement = VillagerMovement.new(self, ctx.nav, ctx.terrain, ctx.config.move_speed)
	knowledge = VillagerKnowledge.new(self)
	brain = VillagerBrain.new(self)
	brain.add_modifier(HabitModifier.new())


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
	_carry = MeshInstance3D.new()
	_carry.position = Vector3(0, 1.05, 0.32)
	_carry.visible = false
	_visual_root.add_child(_carry)
	inventory.changed.connect(_update_carry_visual)
	_anim_time = randf() * 10.0


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------

func sim_tick(dt: float) -> void:
	if is_dead:
		return
	needs.tick(dt, activity, rest_multiplier)
	age_years += dt / maxf(1.0, ctx.config.day_length_seconds * ctx.config.days_per_year)
	if needs.is_dead():
		die("starvation" if needs.hunger >= 100.0 else "exhaustion")
		return
	movement.sim_check(dt)
	brain.tick(dt)
	if current_task != null:
		var status := current_task.tick(dt)
		if status != VillagerTask.Status.RUNNING:
			_end_current_task()


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
	var sd := SimClock.scaled_delta(delta)
	if sd <= 0.0:
		return
	movement.update(sd, needs.performance())
	_animate(sd)


func _animate(dt: float) -> void:
	_anim_time += dt
	var target := movement.facing_target
	if target != Vector3.INF:
		var to := target - global_position
		to.y = 0.0
		if to.length_squared() > 0.0004:
			var desired := atan2(-to.x, -to.z)
			_yaw = lerp_angle(_yaw, desired, clampf(dt * 10.0, 0.0, 1.0))
	var pos := Vector3.ZERO
	var rot := Vector3(0, _yaw, 0)
	if movement.is_moving():
		pos.y = absf(sin(_anim_time * 11.0)) * 0.08
		rot.z = sin(_anim_time * 11.0) * 0.06
	elif state == VillagerState.GATHERING or state == VillagerState.BUILDING:
		# Chopping / hammering motion.
		var s := sin(_anim_time * 9.0)
		rot.x = -maxf(0.0, s) * 0.35
		pos.y = maxf(0.0, -s) * 0.03
	elif state == VillagerState.EATING:
		rot.x = sin(_anim_time * 6.0) * 0.08 - 0.1
	elif state == VillagerState.RESTING:
		# Lying down beside the campfire.
		rot.x = -PI * 0.5
		pos.y = 0.18
	_visual_root.position = pos
	_visual_root.rotation = rot


func _update_carry_visual() -> void:
	if inventory.is_empty():
		_carry.visible = false
		return
	_carry.mesh = MeshFactory.carried_item(inventory.carried_type)
	_carry.visible = true
