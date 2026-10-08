class_name VillagerBrain
extends RefCounted
## Utility-based decision making.
##
## 1. score every goal from needs, time of day and tribe demand
## 2. pass scores through DecisionModifiers (personality hooks)
## 3. try goals from best to worst until a task can actually start
##
## Running tasks are only interrupted for urgent needs, which avoids the
## classic "endlessly switching between tasks" problem.

const GOAL_DELIVER := &"deliver"
const GOAL_EAT := &"eat"
const GOAL_REST := &"rest"
const GOAL_BUILD := &"build"
const GOAL_GATHER_FOOD := &"gather_food"
const GOAL_GATHER_WOOD := &"gather_wood"
const GOAL_GATHER_STONE := &"gather_stone"
const GOAL_IDLE := &"idle"

const GATHER_GOALS := {
	GOAL_GATHER_FOOD: ResourceType.FOOD,
	GOAL_GATHER_WOOD: ResourceType.WOOD,
	GOAL_GATHER_STONE: ResourceType.STONE,
}

const BLACKLIST_SECONDS := 60.0

var villager: Villager
var modifiers: Array[DecisionModifier] = []
## Last productive goal chosen (used by HabitModifier, shown in UI).
var last_work_goal: StringName = &""
## Scores from the last decision, for inspection / debugging.
var last_scores: Dictionary = {}

var _blacklist: Dictionary = {}  # instance_id -> expiry sim time
var _think_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _init(v: Villager) -> void:
	villager = v
	_rng.seed = hash(v.villager_id * 7919)
	_think_timer = _rng.randf_range(0.0, 0.6)  # stagger decisions across villagers


func add_modifier(m: DecisionModifier) -> void:
	modifiers.append(m)


func tick(dt: float) -> void:
	_think_timer -= dt
	if _think_timer > 0.0:
		return
	var task := villager.current_task
	if task == null:
		if not villager.ctx.tribe.try_consume_decision():
			_think_timer = 0.0  # over budget this tick: try again next tick
			return
		_think_timer = 0.5
		villager.set_task(choose_task())
		return
	_think_timer = 1.0
	if task.is_interruptible() and _should_interrupt(task) and villager.ctx.tribe.try_consume_decision():
		villager.set_task(choose_task())


func _should_interrupt(task: VillagerTask) -> bool:
	var needs := villager.needs
	var g := task.goal_id
	if needs.is_starving() and g != GOAL_EAT:
		return _can_eat_somewhere()
	if needs.is_exhausted() and g != GOAL_REST and g != GOAL_EAT:
		return true
	if g == GOAL_IDLE:
		# Idling is a filler: drop it as soon as anything useful scores higher.
		var scores := score_goals()
		for k in scores:
			if k != GOAL_IDLE and scores[k] > 0.2:
				return true
	return false


func _can_eat_somewhere() -> bool:
	if villager.inventory.carried_type == ResourceType.FOOD:
		return true
	if villager.ctx.tribe.stockpile.get_amount(ResourceType.FOOD) > 0:
		return true
	return villager.ctx.resources.find_best(ResourceType.FOOD, villager.global_position,
			villager.get_region(), get_blacklist()) != null


# --------------------------------------------------------------------------
# Scoring
# --------------------------------------------------------------------------

func score_goals() -> Dictionary:
	var cfg := villager.ctx.config
	var needs := villager.needs
	var tribe := villager.ctx.tribe
	var night := SimClock.is_night()
	var scores := {}

	if not villager.inventory.is_empty():
		scores[GOAL_DELIVER] = 0.9

	if needs.is_starving():
		scores[GOAL_EAT] = 1.0
	elif needs.is_hungry():
		scores[GOAL_EAT] = 0.6 + (needs.hunger - cfg.hungry_threshold) / maxf(1.0, 100.0 - cfg.hungry_threshold) * 0.35
	elif night and needs.hunger > 30.0:
		scores[GOAL_EAT] = 0.66  # a meal before bed
	else:
		scores[GOAL_EAT] = 0.0

	if needs.is_exhausted():
		scores[GOAL_REST] = 0.97
	elif needs.is_tired():
		scores[GOAL_REST] = 0.72
	elif night and needs.energy < 92.0:
		scores[GOAL_REST] = 0.64
	else:
		scores[GOAL_REST] = 0.0

	scores[GOAL_BUILD] = 0.58 if tribe.has_build_job_for(villager) else 0.0

	for goal: StringName in GATHER_GOALS:
		var demand := tribe.get_demand(GATHER_GOALS[goal])
		scores[goal] = demand * 0.5 + _rng.randf() * 0.06

	scores[GOAL_IDLE] = 0.02

	for m in modifiers:
		m.modify_scores(villager, scores)
	return scores


func choose_task() -> VillagerTask:
	var scores := score_goals()
	last_scores = scores
	var order: Array = scores.keys()
	order.sort_custom(func(a, b): return scores[a] > scores[b])
	for goal: StringName in order:
		if scores[goal] <= 0.0:
			continue
		var task := _create_task(goal)
		if task == null:
			continue
		if task.start():
			if GATHER_GOALS.has(goal) or goal == GOAL_BUILD:
				last_work_goal = goal
			return task
		task.finish()
	var idle := IdleTask.new(villager, GOAL_IDLE)
	idle.start()
	return idle


func _create_task(goal: StringName) -> VillagerTask:
	match goal:
		GOAL_DELIVER: return DeliverTask.new(villager, goal)
		GOAL_EAT: return EatTask.new(villager, goal)
		GOAL_REST: return RestTask.new(villager, goal)
		GOAL_BUILD: return BuildTask.new(villager, goal)
		GOAL_IDLE: return IdleTask.new(villager, goal)
	if GATHER_GOALS.has(goal):
		return GatherTask.new(villager, goal, GATHER_GOALS[goal])
	push_warning("Unknown goal %s" % goal)
	return null


# --------------------------------------------------------------------------
# Short-term memory of unreachable targets
# --------------------------------------------------------------------------

func mark_unreachable(target: Object, seconds: float = BLACKLIST_SECONDS) -> void:
	if target == null:
		return
	_blacklist[target.get_instance_id()] = SimClock.sim_time + seconds


func get_blacklist() -> Dictionary:
	var now := SimClock.sim_time
	for k in _blacklist.keys():
		if _blacklist[k] < now:
			_blacklist.erase(k)
	return _blacklist
