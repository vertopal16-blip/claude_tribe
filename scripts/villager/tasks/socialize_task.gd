class_name SocializeTask
extends VillagerTask
## Seeking company. Walks up to someone this villager likes (even if they are
## busy) and asks to talk; the other decides based on their own personality
## and feelings. With nobody suitable around, waits by the campfire for the
## ConversationSystem to pair them with another idle villager.

const WAIT_TIME := 15.0
const APPROACH_RANGE := 2.8
const REPATH_INTERVAL := 2.0
const SEARCH_RADIUS := 35.0

var target: Villager
var _waiting := false
var _timer := 0.0
var _repath_timer := 0.0


func start() -> bool:
	villager.set_state(VillagerState.SOCIALIZING)
	target = _pick_target()
	if target != null:
		return villager.movement.move_to(target.global_position, 3)
	var a := villager.brain.rng.randf() * TAU
	var dest := ctx.tribe.campfire.global_position + Vector3(cos(a), 0, sin(a)) * 3.5
	if villager.global_position.distance_to(dest) < 2.5 or not villager.movement.move_to(dest, 3):
		_waiting = true
	return true


func _pick_target() -> Villager:
	var social := ctx.social
	var best: Villager = null
	var best_score := -0.1
	for o in ctx.tribe.villagers_near(villager.global_position, SEARCH_RADIUS):
		if o == villager or not approachable(o):
			continue
		var d := villager.global_position.distance_to(o.global_position)
		if d > SEARCH_RADIUS:
			continue
		var score := social.closeness(villager.villager_id, o.villager_id) - d * 0.01
		if social.romance.is_interested(villager, o):
			# Someone free is worth seeking out; someone taken, only from afar.
			var free := 1.0 if social.romance.is_single(o.villager_id) or social.partner_of(villager.villager_id) == o.villager_id else 0.25
			score += social.romance.attraction(villager, o) * (0.4 + villager.personality.get_trait(&"courage") * 0.6) * free
			# Single people looking for a mate seek out others who are free,
			# the more so the longer they have been alone.
			if social.romance.is_single(villager.villager_id) and social.romance.is_single(o.villager_id):
				score += 0.25 + 0.5 * social.romance.longing(villager)
		score += social.ctx.society.groups.alignment(villager.villager_id, o.villager_id) * 0.15
		# Mood of the moment: people don't always seek out the same friend.
		score += social.rng.randf() * 0.3
		if score > best_score:
			best_score = score
			best = o
	return best


## Someone who could be talked to right now.
static func approachable(o: Villager) -> bool:
	if o.is_dead or o.is_hidden() or o.state == VillagerState.RESTING or o.needs.is_starving():
		return false
	var t := o.current_task
	return t == null or (t.is_interruptible() and not (t is ConverseTask) and not (t is HelpTask))


func tick(dt: float) -> int:
	villager.activity = 0.3
	if target != null:
		return _approach(dt)
	if not _waiting:
		match villager.movement.status:
			VillagerMovement.ARRIVED, VillagerMovement.FAILED, VillagerMovement.IDLE:
				_waiting = true
		return Status.RUNNING
	_timer += dt
	# Simply being around others by the fire eases loneliness a little.
	villager.needs.social = maxf(0.0, villager.needs.social - dt * 0.3)
	return Status.SUCCEEDED if _timer >= WAIT_TIME else Status.RUNNING


func _approach(dt: float) -> int:
	_timer += dt
	if not is_instance_valid(target) or not approachable(target) or _timer > 40.0:
		return _fail("They were busy")
	if villager.global_position.distance_to(target.global_position) <= APPROACH_RANGE:
		var social := ctx.social
		var willing := 0.35 + 0.45 * target.personality.get_trait(&"sociability") \
				+ 0.3 * social.closeness(target.villager_id, villager.villager_id)
		if social.rng.randf() < willing:
			if not social.conversations.start(villager, target):  # replaces this task
				return _fail("They were busy")
			return Status.RUNNING
		villager.say("Never mind...")
		return _fail("Not now")
	_repath_timer += dt
	if _repath_timer >= REPATH_INTERVAL or villager.movement.status != VillagerMovement.MOVING:
		_repath_timer = 0.0
		if not villager.movement.move_to(target.global_position, 3):
			return _fail("Can't reach them")
	return Status.RUNNING


func _on_finish() -> void:
	villager.movement.stop()


func describe() -> String:
	if target != null and is_instance_valid(target):
		return "Going to talk with %s" % target.villager_name
	return "Hoping someone wants to talk" if _waiting else "Looking for company"
