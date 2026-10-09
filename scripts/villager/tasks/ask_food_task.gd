class_name AskFoodTask
extends VillagerTask
## Hungry with an empty stockpile: walk up to someone carrying food and ask
## them for some. Whether they give is decided in the conversation, by their
## personality and how they feel about the asker.

const ASK_RANGE := 2.6
const SIGHT := 30.0
const REPATH_INTERVAL := 2.0

var target: Villager
var _repath_timer := 0.0


## Someone in sight carrying food, preferring people who like us.
static func find_food_carrier(v: Villager) -> Villager:
	var best: Villager = null
	var best_score := -INF
	for o in v.ctx.tribe.villagers_near(v.global_position, SIGHT):
		if o == v or o.inventory.carried_type != ResourceType.FOOD or not SocializeTask.approachable(o):
			continue
		var d := v.global_position.distance_to(o.global_position)
		if d > SIGHT:
			continue
		var score := v.ctx.social.closeness(o.villager_id, v.villager_id) - d * 0.02
		if score > best_score:
			best_score = score
			best = o
	return best


func start() -> bool:
	target = find_food_carrier(villager)
	if target == null:
		return false
	villager.set_state(VillagerState.SEARCHING_FOOD)
	return villager.movement.move_to(target.global_position, 3)


func tick(dt: float) -> int:
	if not is_instance_valid(target) or target.inventory.carried_type != ResourceType.FOOD or not SocializeTask.approachable(target):
		return _fail("They no longer have food")
	if villager.global_position.distance_to(target.global_position) <= ASK_RANGE:
		ctx.social.conversations.start(villager, target, &"ask_food")  # replaces this task
		return Status.RUNNING
	_repath_timer += dt
	if _repath_timer >= REPATH_INTERVAL or villager.movement.status != VillagerMovement.MOVING:
		_repath_timer = 0.0
		if not villager.movement.move_to(target.global_position, 3):
			return _fail("Can't reach them")
	return Status.RUNNING


func _on_finish() -> void:
	villager.movement.stop()


func is_interruptible() -> bool:
	return false


func describe() -> String:
	return "Asking %s for food" % (target.villager_name if is_instance_valid(target) else "someone")
