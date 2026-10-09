class_name RomanceSystem
extends RefCounted
## Courtship and couples.
##
## Attraction (directional) comes from a stable personal "spark" between two
## people, temperament compatibility, respect and closeness in age; it only
## exists where orientation allows. Interest leads to flirting; repeated
## mutual success leads to courting; courting leads to a proposal, which the
## other may accept or refuse. Couples share a home, can become long-term
## spouses, and can break up when affection turns sour. Jealous partners react
## to flirting they witness. Nobody is paired automatically; some stay single.

const INTEREST := 0.45
const PROPOSE_ATTRACTION := 0.5
const SPOUSE_AFTER_DAYS := 6
const CHECK_INTERVAL := 30.0
## Days before former partners can rekindle anything.
const EX_COOLDOWN_DAYS := 10
## Grudges this strong kill romantic interest.
const RESENTMENT_BLOCK := 0.4

var social: SocialSystem
var couples_formed := 0
var breakups := 0
## Day a couple formed: Vector2i(min, max) -> day.
var together_since: Dictionary = {}
## Day a couple split: Vector2i(min, max) -> day.
var split_on: Dictionary = {}
## Villager id -> &"straight" / &"open" (attracted to any sex).
var orientation: Dictionary = {}
var _timer := 0.0


func _init(s: SocialSystem) -> void:
	social = s


func register(v: Villager) -> void:
	if orientation.has(v.villager_id):
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash([social.social_seed(), v.villager_id, "orientation"])
	orientation[v.villager_id] = &"open" if r.randf() < 0.1 else &"straight"


func _drawn_to(a: Villager, b: Villager) -> bool:
	return orientation.get(a.villager_id, &"straight") == &"open" or a.sex != b.sex


func eligible(v: Villager) -> bool:
	return v != null and not v.is_dead and v.age_years >= social.ctx.config.adult_age


## Stable chemistry between two people, the same in both directions.
func spark(a: int, b: int) -> float:
	return float(hash([social.social_seed(), mini(a, b), maxi(a, b), "spark"]) % 1000) / 1000.0


## a's attraction to b, computed the first time they matter to each other.
func attraction(a: Villager, b: Villager) -> float:
	var g := social.graph
	var ia := a.villager_id
	var ib := b.villager_id
	var current := g.attraction(ia, ib)
	if current > 0.0:
		return current
	if not eligible(a) or not eligible(b) or not _drawn_to(a, b) or g.is_kin(ia, ib):
		return 0.0
	var age_gap := absf(a.age_years - b.age_years)
	var value := spark(ia, ib) * 0.6 + a.personality.compatibility(b.personality) * 0.25 \
			+ clampf(g.respect(ia, ib), 0.0, 1.0) * 0.1 + (1.0 - clampf(age_gap / 25.0, 0.0, 1.0)) * 0.15 - 0.05
	# Big age gaps rarely spark romance (an elder and a youth of sixteen).
	value *= 1.0 - clampf((age_gap - 12.0) / 25.0, 0.0, 0.75)
	value = clampf(value, 0.001, 1.0)
	g.set_field(ia, ib, "attraction", value)
	return value


## Good times together slowly turn into attraction between free adults.
func on_good_time(a: Villager, b: Villager) -> void:
	if eligible(a) and eligible(b) and attraction(a, b) > 0.0 and is_single(a.villager_id):
		social.graph.adjust_field(a.villager_id, b.villager_id, "attraction", 0.015 * (0.5 + spark(a.villager_id, b.villager_id)))


func is_single(id: int) -> bool:
	return social.partner_of(id) < 0


## Would `a` pursue `b` right now?
func is_interested(a: Villager, b: Villager) -> bool:
	if a == b or not eligible(a) or not eligible(b):
		return false
	if attraction(a, b) < interest_bar(a):
		return false
	if social.graph.resentment(a.villager_id, b.villager_id) > RESENTMENT_BLOCK:
		return false
	var split = split_on.get(RelationshipGraph._bond_key(a.villager_id, b.villager_id))
	if split != null and SimClock.get_day() - int(split) < EX_COOLDOWN_DAYS:
		return false
	if social.partner_of(a.villager_id) == b.villager_id:
		return true
	if not is_single(a.villager_id):
		# Straying needs a cooling relationship and a fickle heart.
		var p := social.partner_of(a.villager_id)
		return a.personality.get_trait(&"loyalty") < 0.3 and social.graph.affinity(a.villager_id, p) < 0.15
	return true


## How strongly `a` must be drawn to someone to pursue them. People who have
## been alone a long time - especially those who crave company - grow less
## choosy, so moderate chemistry can still become a couple.
func interest_bar(a: Villager) -> float:
	return INTEREST - 0.15 * longing(a)


## 0..1: how much a single person wants a partner after time alone.
func longing(a: Villager) -> float:
	if not is_single(a.villager_id):
		return 0.0
	var cfg := social.ctx.config
	# Day they came of age (founders: the start of the game) or last split up.
	var free_since := maxf(0.0, SimClock.get_day() - (a.age_years - cfg.adult_age) * cfg.days_per_year)
	for k: Vector2i in split_on:
		if k.x == a.villager_id or k.y == a.villager_id:
			free_since = maxf(free_since, float(split_on[k]))
	var days_alone := maxf(0.0, SimClock.get_day() - free_since)
	var want: float = clampf(days_alone / 20.0, 0.0, 1.0) * lerpf(0.6, 1.3, a.personality.get_trait(&"social_need")) \
			+ 0.3 * a.emotions.get_value(&"loneliness")
	return clampf(want, 0.0, 1.0)


## The person `a` is most drawn to among those they know, or null.
func crush_of(a: Villager) -> Villager:
	var best: Villager = null
	var best_v := interest_bar(a)
	for id in social.graph.known_by(a.villager_id):
		var b := social.get_villager(id)
		if b == null or not is_interested(a, b):
			continue
		var v := attraction(a, b) + (0.15 if is_single(id) else -0.35)
		if v > best_v:
			best_v = v
			best = b
	return best


# --------------------------------------------------------------------------
# Courtship steps (called from conversation outcomes)
# --------------------------------------------------------------------------

## Chance the listener welcomes a flirt.
func flirt_reception(s: Villager, l: Villager) -> float:
	var g := social.graph
	var p := attraction(l, s) * 0.85 + g.affinity(l.villager_id, s.villager_id) * 0.3 \
			+ l.personality.get_trait(&"sociability") * 0.1 - 0.15
	var lp := social.partner_of(l.villager_id)
	if lp >= 0 and lp != s.villager_id:
		p -= 0.5 * l.personality.get_trait(&"loyalty")
	return clampf(p, 0.02, 0.95)


func on_flirt_success(s: Villager, l: Villager) -> void:
	var g := social.graph
	g.adjust_field(s.villager_id, l.villager_id, "attraction", 0.06)
	g.adjust_field(l.villager_id, s.villager_id, "attraction", 0.08)
	_witness_flirt(s, l)
	if g.has_tag(s.villager_id, l.villager_id, &"courting") or social.partner_of(s.villager_id) == l.villager_id:
		return
	var flirts := 0
	for r in s.memory.about(l.villager_id):
		if r.kind == &"flirted":
			flirts += r.count
	if flirts >= 2 and attraction(s, l) >= interest_bar(s) + 0.05 and attraction(l, s) >= interest_bar(l):
		g.set_tag(s.villager_id, l.villager_id, &"courting", true)
		social.remember(s, &"courting", l.villager_id)
		social.remember(l, &"courting", s.villager_id)
		social.ctx.society.history.add(&"romance", "%s and %s are courting." % [s.villager_name, l.villager_name],
				[s.villager_id, l.villager_id])


## Partners who see their partner flirt with someone else get jealous.
func _witness_flirt(s: Villager, l: Villager) -> void:
	for flirter in [s, l]:
		var other: Villager = l if flirter == s else s
		var pid := social.partner_of(flirter.villager_id)
		if pid < 0 or pid == other.villager_id:
			continue
		var partner := social.get_villager(pid)
		if partner == null or partner.global_position.distance_to(flirter.global_position) > 18.0:
			continue
		if partner.personality.get_trait(&"jealousy") < 0.25:
			continue
		social.remember(partner, &"jealous_of", other.villager_id)
		social.remember(partner, &"partner_unfaithful", flirter.villager_id, other.villager_id)
		social.ctx.society.history.add(&"romance", "%s saw %s flirting with %s." % [partner.villager_name,
				flirter.villager_name, other.villager_name], [partner.villager_id, flirter.villager_id, other.villager_id])


func ready_to_propose(s: Villager, l: Villager) -> bool:
	return social.graph.has_tag(s.villager_id, l.villager_id, &"courting") \
			and attraction(s, l) >= PROPOSE_ATTRACTION - (INTEREST - interest_bar(s)) \
			and is_single(s.villager_id)


## Would `l` accept `s` as a partner? Family opinion matters.
func accepts_partnership(s: Villager, l: Villager) -> bool:
	var g := social.graph
	var lid := l.villager_id
	var sid := s.villager_id
	var score := attraction(l, s) * 0.6 + g.affinity(lid, sid) * 0.5 + g.trust(lid, sid) * 0.2 - 0.45 \
			- g.resentment(lid, sid) * 0.8
	if not is_single(lid):
		var p := social.partner_of(lid)
		score -= 0.4 * l.personality.get_trait(&"loyalty") + 0.4 * maxf(0.0, g.affinity(lid, p))
	var family_view := 0.0
	var kin := social.kin_of(lid)
	for k in kin:
		family_view += g.affinity(k, sid)
	if not kin.is_empty():
		score += 0.2 * family_view / kin.size()
	return social.rng.randf() < clampf(score + 0.5, 0.02, 0.97)


func form_couple(a: Villager, b: Villager) -> void:
	var g := social.graph
	for v in [a, b]:
		var old := social.partner_of(v.villager_id)
		if old >= 0:
			break_up(v, social.get_villager(old), "%s left for %s" % [v.villager_name, (b if v == a else a).villager_name])
	g.set_tag(a.villager_id, b.villager_id, &"courting", false)
	g.set_tag(a.villager_id, b.villager_id, &"ex_partner", false)
	g.set_tag(a.villager_id, b.villager_id, &"partner", true)
	together_since[RelationshipGraph._bond_key(a.villager_id, b.villager_id)] = SimClock.get_day()
	couples_formed += 1
	social.stats.partnerships += 1
	social.remember(a, &"became_partners", b.villager_id)
	social.remember(b, &"became_partners", a.villager_id)
	social.ctx.society.history.add(&"romance", "%s and %s became a couple." % [a.villager_name, b.villager_name],
			[a.villager_id, b.villager_id])
	EventBus.notify("%s and %s became a couple!" % [a.villager_name, b.villager_name], &"social")
	_join_households(a, b)


## Couples live together: whoever owns a home takes the other in.
func _join_households(a: Villager, b: Villager) -> void:
	var tribe := social.ctx.tribe
	for pair in [[a, b], [b, a]]:
		var owner: Villager = pair[0]
		var mover: Villager = pair[1]
		for bld in tribe.buildings:
			if bld.owner_ids.has(owner.villager_id) and bld.def.housing > 0:
				if not bld.owner_ids.has(mover.villager_id):
					bld.owner_ids.append(mover.villager_id)
				# The mover gives up their own home if they had one (it stays theirs to reuse later).
				tribe.assign_home(mover, bld)
				social.remember(mover, &"moved_in_with", owner.villager_id)
				for child_id in social.ctx.society.demographics.children_of(mover.villager_id):
					var c := social.get_villager(child_id)
					if c != null and c.is_child():
						c.home = bld
				return


func break_up(a: Villager, b: Villager, reason: String) -> void:
	if a == null or b == null:
		return
	var g := social.graph
	g.set_tag(a.villager_id, b.villager_id, &"partner", false)
	g.set_tag(a.villager_id, b.villager_id, &"spouse", false)
	g.set_tag(a.villager_id, b.villager_id, &"ex_partner", true)
	together_since.erase(RelationshipGraph._bond_key(a.villager_id, b.villager_id))
	split_on[RelationshipGraph._bond_key(a.villager_id, b.villager_id)] = SimClock.get_day()
	g.set_tag(a.villager_id, b.villager_id, &"courting", false)
	g.adjust_field(a.villager_id, b.villager_id, "attraction", -0.2)
	g.adjust_field(b.villager_id, a.villager_id, "attraction", -0.2)
	breakups += 1
	social.remember(a, &"broke_up", b.villager_id)
	social.remember(b, &"broke_up", a.villager_id)
	# The one with the weaker claim to the home moves out.
	var tribe := social.ctx.tribe
	for bld in tribe.buildings:
		if bld.owner_ids.has(a.villager_id) and bld.owner_ids.has(b.villager_id):
			var leaver: Villager = b if bld.owner_ids[0] == a.villager_id else a
			bld.owner_ids.erase(leaver.villager_id)
			if leaver.home == bld:
				bld.release_bed(leaver)
				leaver.home = null
	social.ctx.society.history.add(&"romance", "%s and %s separated (%s)." % [a.villager_name, b.villager_name, reason],
			[a.villager_id, b.villager_id])
	EventBus.notify("%s and %s have separated." % [a.villager_name, b.villager_name], &"social")


# --------------------------------------------------------------------------
# Couples over time
# --------------------------------------------------------------------------

func tick(dt: float) -> void:
	_timer += dt
	if _timer < CHECK_INTERVAL:
		return
	_timer -= CHECK_INTERVAL
	var g := social.graph
	var seen := {}
	for v in social.ctx.tribe.villagers:
		var pid := social.partner_of(v.villager_id)
		if pid < 0 or seen.has(pid):
			continue
		seen[v.villager_id] = true
		var p := social.get_villager(pid)
		if p == null:
			continue
		var key := RelationshipGraph._bond_key(v.villager_id, pid)
		if not together_since.has(key):
			together_since[key] = SimClock.get_day()
		var mutual := (g.affinity(v.villager_id, pid) + g.affinity(pid, v.villager_id)) * 0.5
		var grudge := maxf(g.resentment(v.villager_id, pid), g.resentment(pid, v.villager_id))
		# Living together slowly deepens a healthy bond.
		if grudge < 0.3:
			g.adjust_opinion(v.villager_id, pid, 0.01, 0.005)
			g.adjust_opinion(pid, v.villager_id, 0.01, 0.005)
		if mutual > 0.5 and SimClock.get_day() - int(together_since[key]) >= SPOUSE_AFTER_DAYS \
				and g.set_tag(v.villager_id, pid, &"spouse", true):
			social.ctx.society.history.add(&"romance", "%s and %s are now lifelong partners." % [v.villager_name, p.villager_name],
					[v.villager_id, pid])
		if (mutual < -0.05 or grudge > 0.65) and social.rng.randf() < 0.5:
			break_up(v, p, "too much bad blood" if grudge > 0.65 else "they grew apart")


func to_dict() -> Dictionary:
	var ts := []
	for k: Vector2i in together_since:
		ts.append([k.x, k.y, together_since[k]])
	var sp := []
	for k: Vector2i in split_on:
		sp.append([k.x, k.y, split_on[k]])
	var ori := {}
	for id in orientation:
		ori[str(id)] = String(orientation[id])
	return {"couples": couples_formed, "breakups": breakups, "together": ts, "split": sp, "orientation": ori}


func load_dict(d: Dictionary) -> void:
	couples_formed = int(d["couples"])
	breakups = int(d["breakups"])
	together_since.clear()
	for row in d["together"]:
		together_since[Vector2i(int(row[0]), int(row[1]))] = int(row[2])
	split_on.clear()
	for row in d.get("split", []):
		split_on[Vector2i(int(row[0]), int(row[1]))] = int(row[2])
	for id in d["orientation"]:
		orientation[int(id)] = StringName(d["orientation"][id])
