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
const GOAL_SOCIALIZE := &"socialize"
const GOAL_EXPLORE := &"explore"
const GOAL_HELP := &"help"
const GOAL_ASK_FOOD := &"ask_food"

const GATHER_GOALS := {
	GOAL_GATHER_FOOD: ResourceType.FOOD,
	GOAL_GATHER_WOOD: ResourceType.WOOD,
	GOAL_GATHER_STONE: ResourceType.STONE,
}

const BLACKLIST_SECONDS := 60.0
## Non-urgent choices are sampled among options scoring within this fraction
## of the best one, so traits and moods shift behaviour probabilistically.
const SAMPLE_BAND := 0.8
## Above this score a goal is urgent and always chosen deterministically.
const URGENT_SCORE := 0.8

var villager: Villager
var modifiers: Array[DecisionModifier] = []
## Last productive goal chosen (used by HabitModifier, shown in UI).
var last_work_goal: StringName = &""
## Scores from the last decision, for inspection / debugging.
var last_scores: Dictionary = {}

var _blacklist: Dictionary = {}  # instance_id -> expiry sim time
var _think_timer := 0.0
## Seeded per villager: decisions are random but reproducible.
var rng := RandomNumberGenerator.new()
## Resource the explore goal is searching for (set while scoring).
var _explore_type: int = ResourceType.NONE


func _init(v: Villager) -> void:
	villager = v
	# Seeded from the world seed so a replayed world makes the same choices.
	rng.seed = hash([v.ctx.world_seed, v.villager_id])
	_think_timer = rng.randf_range(0.0, 0.6)  # stagger decisions across villagers


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
		# End the old task BEFORE starting the new one: its cleanup (e.g. stopping
		# movement) must not undo what the new task just set up.
		villager.set_task(null)
		villager.set_task(choose_task())


func _should_interrupt(task: VillagerTask) -> bool:
	var needs := villager.needs
	var g := task.goal_id
	if needs.is_starving() and g != GOAL_EAT:
		return _can_eat_somewhere()
	if needs.is_exhausted() and g != GOAL_REST and g != GOAL_EAT:
		return true
	if g == GOAL_IDLE or g == GOAL_SOCIALIZE:
		# Idling is a filler: drop it as soon as anything useful scores higher.
		var scores := score_goals()
		for k in scores:
			if k != GOAL_IDLE and k != GOAL_SOCIALIZE and scores[k] > maxf(0.2, scores.get(g, 0.0) + 0.15):
				return true
	return false


func _can_eat_somewhere() -> bool:
	if villager.inventory.carried_type == ResourceType.FOOD:
		return true
	if villager.ctx.tribe.stockpile.get_amount(ResourceType.FOOD) > 0:
		return true
	return villager.knowledge.find_resource(ResourceType.FOOD) != null


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

	# Gathering needs a known location; otherwise the need drives exploration.
	_explore_type = ResourceType.NONE
	# Curiosity fades as the villager gets to know the valley.
	var familiarity := clampf(villager.knowledge.store.size() / 250.0, 0.0, 1.0)
	var explore := (0.04 + villager.personality.get_trait(&"curiosity") * 0.06) * (1.0 - familiarity)
	for goal: StringName in GATHER_GOALS:
		var type: int = GATHER_GOALS[goal]
		var demand := tribe.get_demand(type)
		if villager.knowledge.knows_available(type):
			scores[goal] = demand * 0.5 + rng.randf() * 0.06
		else:
			scores[goal] = 0.0
			var want := demand * 0.5 + 0.05
			if want > explore:
				explore = want
				_explore_type = type
	# Starving with no food anywhere we know of: search desperately.
	if needs.is_hungry() and not _can_eat_somewhere():
		explore = 0.92 if needs.is_starving() else 0.7
		_explore_type = ResourceType.FOOD
	scores[GOAL_EXPLORE] = 0.0 if night else explore

	# Loneliness; evenings by the fire are the social hour.
	var lonely := needs.social / 100.0
	var tod := SimClock.get_time_of_day()
	var evening := 0.2 if tod > 0.68 and tod < 0.8 else 0.0
	scores[GOAL_SOCIALIZE] = 0.0 if night else (lonely * 0.8 + evening if needs.social > 25.0 else evening * 0.5)

	scores[GOAL_HELP] = 0.0
	if villager.inventory.carried_type == ResourceType.FOOD:
		var needy := villager.ctx.social.find_person_to_help(villager)
		if needy != null:
			var close := villager.ctx.social.closeness(villager.villager_id, needy.villager_id)
			# Competes with delivering to the stockpile (0.9): caring or close villagers help.
			scores[GOAL_HELP] = minf(0.97, 0.72 + 0.2 * villager.personality.get_trait(&"empathy") + 0.12 * close)

	# Hungry, nothing in the stockpile: ask someone carrying food. Proud,
	# independent or suspicious villagers would rather fend for themselves.
	scores[GOAL_ASK_FOOD] = 0.0
	if needs.is_hungry() and tribe.stockpile.get_amount(ResourceType.FOOD) == 0 \
			and villager.inventory.carried_type != ResourceType.FOOD:
		if AskFoodTask.find_food_carrier(villager) != null:
			var p := villager.personality
			scores[GOAL_ASK_FOOD] = (0.95 if needs.is_starving() else 0.72) \
					* lerpf(1.15, 0.75, p.get_trait(&"independence")) * lerpf(0.85, 1.1, p.get_trait(&"trust"))

	scores[GOAL_IDLE] = 0.02

	for m in modifiers:
		m.modify_scores(villager, scores)
	return scores


func choose_task() -> VillagerTask:
	var scores := score_goals()
	last_scores = scores
	var order: Array = scores.keys()
	order.sort_custom(func(a, b): return scores[a] > scores[b])
	_sample_front(order, scores)
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


## Weighted random pick among near-best, non-urgent goals (moved to the front).
func _sample_front(order: Array, scores: Dictionary) -> void:
	if order.is_empty():
		return
	var best: float = scores[order[0]]
	if best >= URGENT_SCORE or best <= 0.0:
		return
	var pool: Array = []
	for g in order:
		if scores[g] >= best * SAMPLE_BAND and pool.size() < 3:
			pool.append(g)
	if pool.size() < 2:
		return
	var total := 0.0
	for g in pool:
		total += pow(scores[g], 3.0)
	var roll := rng.randf() * total
	for g in pool:
		roll -= pow(scores[g], 3.0)
		if roll <= 0.0:
			order.erase(g)
			order.push_front(g)
			return


func _create_task(goal: StringName) -> VillagerTask:
	match goal:
		GOAL_DELIVER: return DeliverTask.new(villager, goal)
		GOAL_EAT: return EatTask.new(villager, goal)
		GOAL_REST: return RestTask.new(villager, goal)
		GOAL_BUILD: return BuildTask.new(villager, goal)
		GOAL_IDLE: return IdleTask.new(villager, goal)
		GOAL_SOCIALIZE: return SocializeTask.new(villager, goal)
		GOAL_EXPLORE: return ExploreTask.new(villager, goal, _explore_type)
		GOAL_HELP: return HelpTask.new(villager, goal)
		GOAL_ASK_FOOD: return AskFoodTask.new(villager, goal)
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
