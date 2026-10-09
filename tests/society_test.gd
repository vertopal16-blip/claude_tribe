extends Node
## Society tests: runs the real game at high speed, then checks each
## requirement both as an emergent outcome of the run and as a controlled
## mechanism test on the live world (real villagers, real systems).
##
##   godot --headless --path . res://tests/society_test.tscn --fixed-fps 60 -- --seed=1234 --days=30
##   ... -- --seed=1234 --days=8 --save=/tmp/tribe_save.txt        (save at the end)
##   ... -- --load=/tmp/tribe_save.txt                              (load and verify)

var main: Main
var seed_value := 1234
var days := 30.0
var save_path := ""
var load_path := ""
var failures: PackedStringArray = []
var _done := false


func _ready() -> void:
	get_tree().root.size = Vector2i(1600, 900)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.split("=")[1])
		elif arg.begins_with("--days="):
			days = float(arg.split("=")[1])
		elif arg.begins_with("--save="):
			save_path = arg.split("=")[1]
		elif arg.begins_with("--load="):
			load_path = arg.split("=")[1]
	var cfg: GameConfig = load("res://config/default_config.tres").duplicate()
	cfg.world_seed = seed_value
	if load_path != "":
		Main.pending_load = SaveSystem.read(load_path)
	main = load("res://scenes/main.tscn").instantiate()
	main.config = cfg
	add_child(main)
	SimClock.set_time_scale(8.0)


func check(cond: bool, what: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", what])
	if not cond:
		failures.append(what)


func _process(_delta: float) -> void:
	if _done:
		return
	if load_path != "":
		if not has_meta("verified"):
			set_meta("verified", SimClock.sim_time)
			_verify_load()
			return
		# Keep playing after loading: the restored tribe must carry on normally.
		if SimClock.sim_time < float(get_meta("verified")) + 2.0 * SimClock.day_length:
			return
		_done = true
		check(main.tribe.population() > 0 and main.ctx.social.stats.conversations > 0,
				"16. The loaded tribe keeps living (population %d, %d conversations)" % [main.tribe.population(), main.ctx.social.stats.conversations])
		_finish()
		return
	if SimClock.sim_time < days * SimClock.day_length:
		return
	_done = true
	SimClock.set_paused(true)
	_emergent_checks()
	_summary()
	if OS.get_cmdline_user_args().has("--chronicle"):
		for e in main.ctx.society.history.entries:
			print("  [day %d] %s" % [e["day"], e["text"]])
	if save_path != "":
		SaveSystem.save_game(main, save_path)
		var f := FileAccess.open(save_path + ".fingerprint", FileAccess.WRITE)
		f.store_string(fingerprint())
		f.close()
		print("[society] saved to %s" % save_path)
	else:
		_mechanism_checks()
	_finish()


func _finish() -> void:
	print("[society] RESULT: %s (%d failures)" % ["OK" if failures.is_empty() else "FAILED", failures.size()])
	for f in failures:
		print("   - " + f)
	get_tree().quit(0 if failures.is_empty() else 1)


# --------------------------------------------------------------------------
# What happened on its own during the run
# --------------------------------------------------------------------------

func _emergent_checks() -> void:
	var soc := main.ctx.society
	var social := main.ctx.social
	print("[society] emergent behaviour over %d days (seed %d)" % [int(days), seed_value])
	check(social.stats.conversations >= 30, "1. Villagers start conversations on their own (%d)" % social.stats.conversations)
	check(social.stats.topics.size() >= 6, "   ...about many different things (%d topics)" % social.stats.topics.size())
	var friends := 0
	for v in main.tribe.villagers:
		friends += social.friends_of(v.villager_id).size()
	check(friends > 0, "2. Friendships emerge (%d friend links)" % friends)
	check(main.tribe.population() >= 8, "   The tribe survives and grows (population %d)" % main.tribe.population())
	check(soc.demographics.births >= 1, "5. Children are born (%d births)" % soc.demographics.births)
	if days >= 25:
		check(social.romance.couples_formed >= 1, "3. New couples form on their own (%d)" % social.romance.couples_formed)
		check(soc.history.count(&"discovery") >= 1, "   Discoveries are made (%d)" % soc.history.count(&"discovery"))
		# Projects need a reason: known techniques or a need for a shrine.
		var possible := soc.tech.tribe_knows(&"toolmaking") or soc.tech.tribe_knows(&"agriculture") \
				or (soc.tech.tribe_knows(&"carpentry") and main.tribe.population() >= 12) or soc.history.count(&"death") >= 2
		if possible:
			check(soc.proposals.completed >= 1, "11. Community projects are proposed and completed (%d)" % soc.proposals.completed)
		else:
			print("  [INFO] 11. No building-enabling discovery yet in this world; projects not expected")
		var closest := ""
		for v in main.tribe.villagers:
			for k in ProfessionSystem.TITLES:
				if v.skills.get_level(k) >= 15.0:
					closest += " %s:%s=%d/%.0f%%" % [v.villager_name, k, int(v.skills.get_level(k)), v.skills.recent_share(k) * 100.0]
		check(not soc.professions.known_professions.is_empty(), "12. Professions emerge %s%s" % [str(soc.professions.known_professions.keys()),
				"" if not soc.professions.known_professions.is_empty() else " (skills:" + closest + ")"])
		check(not soc.groups.groups.is_empty(), "10. Social groups form (%d)" % soc.groups.groups.size())


# --------------------------------------------------------------------------
# Controlled mechanism tests on the live world
# --------------------------------------------------------------------------

## Adults (youngest first), optionally of one sex. With fewer than six adults
## around, extra adults are added so every mechanism test has its cast.
func _adults(sex: StringName = &"") -> Array[Villager]:
	var out: Array[Villager] = []
	for v in main.tribe.villagers:
		if v.is_adult() and (sex == &"" or v.sex == sex):
			out.append(v)
	while sex == &"" and out.size() < 6:
		out.append(main.tribe.add_villager(main.tribe.center + Vector3(3, 0, 3), 24.0))
	out.sort_custom(func(a, b): return a.age_years < b.age_years)
	return out


func _mechanism_checks() -> void:
	var social := main.ctx.social
	var soc := main.ctx.society
	var g := social.graph
	print("[society] mechanism checks")

	# 2. Repeated positive interactions -> friendship
	var adults := _adults()
	var a: Villager = adults[0]
	var b: Villager = adults[1]
	g.set_tag(a.villager_id, b.villager_id, &"rival", false)
	g.set_opinion(a.villager_id, b.villager_id, 0.0, 0.5)
	g.set_opinion(b.villager_id, a.villager_id, 0.0, 0.5)
	for i in 12:
		social.remember(a, &"chatted", b.villager_id)
		social.remember(b, &"chatted", a.villager_id)
		social.remember(a, &"worked_together", b.villager_id)
		social.remember(b, &"worked_together", a.villager_id)
	check(g.has_tag(a.villager_id, b.villager_id, &"friend"), "2. Repeated good times make %s and %s friends" % [a.villager_name, b.villager_name])

	# 3+4. Romance: interest -> flirting -> courting -> proposal -> couple -> shared home
	var woman: Villager = null
	var man: Villager = null
	for w in _adults(&"female"):
		for m in _adults(&"male"):
			if not g.is_kin(w.villager_id, m.villager_id):
				woman = w
				man = m
				break
		if woman != null:
			break
	check(woman != null, "   Found an unrelated woman and man for the romance test")
	if woman != null:
		for v in [woman, man]:
			var p := social.partner_of(v.villager_id)
			if p >= 0:
				social.romance.break_up(v, social.get_villager(p), "test setup")
		social.romance.split_on.erase(RelationshipGraph._bond_key(woman.villager_id, man.villager_id))
		g.set_field(woman.villager_id, man.villager_id, "resentment", 0.0)
		g.set_field(man.villager_id, woman.villager_id, "resentment", 0.0)
		g.set_field(woman.villager_id, man.villager_id, "attraction", 0.8)
		g.set_field(man.villager_id, woman.villager_id, "attraction", 0.8)
		g.set_opinion(woman.villager_id, man.villager_id, 0.6, 0.7)
		g.set_opinion(man.villager_id, woman.villager_id, 0.6, 0.7)
		check(social.romance.is_interested(man, woman), "3. %s is interested in %s" % [man.villager_name, woman.villager_name])
		for i in 3:
			var o := social.conversations.decide(man, woman, &"flirt")
			if o.validate(social):
				o.apply(social)
		check(g.has_tag(man.villager_id, woman.villager_id, &"courting"), "3. Welcomed flirting turns into courting")
		var formed := false
		for i in 8:
			var o := social.conversations.decide(man, woman, &"propose_partnership")
			if o.validate(social):
				o.apply(social)
			if social.partner_of(man.villager_id) == woman.villager_id:
				formed = true
				break
		check(formed, "3. The proposal is accepted: %s and %s are a couple" % [man.villager_name, woman.villager_name])
		# Household
		var hut: Building = null
		for bld in main.tribe.buildings:
			if bld.def.id == &"hut" and bld.is_complete:
				hut = bld
				break
		hut.owner_ids.assign([woman.villager_id])
		social.romance._join_households(woman, man)
		check(man.home == hut and hut.owner_ids.has(man.villager_id), "4. The couple share a household")

		# 5. Reproduction needs suitable conditions
		main.tribe.stockpile.take(ResourceType.FOOD, 100000)
		woman.needs.hunger = 10.0
		man.needs.hunger = 10.0
		woman.needs.health = 100.0
		man.needs.health = 100.0
		woman.last_birth_day = -100
		woman.pregnancy_days = -1.0
		woman.pregnancy_partner = -1
		woman.age_years = 25.0
		man.age_years = 27.0
		woman.home = hut
		for o in main.tribe.villagers:
			if o.home == hut and o != woman and o != man:
				o.home = null
		check(soc.demographics.conception_blocker(woman) == "the tribe's food stores are too low",
				"5. No children while food is scarce (%s)" % soc.demographics.conception_blocker(woman))
		main.tribe.stockpile.add(ResourceType.FOOD, main.tribe.population() * 10)
		check(soc.demographics.can_conceive(woman), "5. With food and a home, conception is possible (%s)" % soc.demographics.conception_blocker(woman))
		soc.demographics.conceive(woman)
		var pop := main.tribe.population()
		var child := soc.demographics.give_birth(woman)
		check(main.tribe.population() == pop + 1 and child.parent_ids.has(woman.villager_id) and child.parent_ids.has(man.villager_id),
				"5. A child is born as a real villager with both parents")
		check(g.is_kin(child.villager_id, woman.villager_id) and soc.demographics.children_of(man.villager_id).has(child.villager_id),
				"5. Family links are recorded")
		check(child.age_years < 1.0 and child.is_child() and child.work_capacity() == 0.0, "6. Newborns are children who don't work")
		# 6. Growing up
		child.age_years = soc.ctx.config.youth_age - 0.001
		child.sim_tick(10.0)
		soc.demographics._track_stage(child)
		check(child.life_stage() == &"youth" and child.work_capacity() > 0.0, "6. Children grow into youths who can help")
		var small: float = 0.0
		child.age_years = 2.0
		child.update_age_visual()
		small = child._body.scale.x
		child.age_years = 20.0
		child.update_age_visual()
		check(small < child._body.scale.x, "6. Children are visibly smaller than adults")

	# 7. Memories change later behaviour
	var x: Villager = adults[2]
	var y: Villager = adults[3]
	g.set_opinion(x.villager_id, y.villager_id, 0.2, 0.6)
	g.set_field(x.villager_id, y.villager_id, "resentment", 0.0)
	var before_w := social.conversations.topic_weights(x, y)
	for i in 3:
		social.remember(x, &"was_refused", y.villager_id)
		social.remember(x, &"misled", y.villager_id, -1, -1, "food")
	var after_w := social.conversations.topic_weights(x, y)
	check(not before_w.has(&"accuse") and after_w.has(&"accuse"), "7. After being wronged, %s wants to confront %s" % [x.villager_name, y.villager_name])
	check(g.trust(x.villager_id, y.villager_id) < 0.6, "7. ...and trusts them less (%.2f)" % g.trust(x.villager_id, y.villager_id))

	# 8. Emotions change decisions
	var e: Villager = adults[4]
	e.emotions = Emotions.new()
	var calm := e.brain.score_goals()
	e.emotions.values[&"grief"] = 0.95
	var grieving := e.brain.score_goals()
	var work := [&"gather_food", &"gather_wood", &"gather_stone"]
	var calm_w := 0.0
	var grief_w := 0.0
	for k in work:
		calm_w += calm.get(k, 0.0)
		grief_w += grieving.get(k, 0.0)
	check(grief_w < calm_w and grieving.get(&"socialize", 0.0) >= calm.get(&"socialize", 0.0),
			"8. Grief makes %s work less and seek company (work %.2f -> %.2f)" % [e.villager_name, calm_w, grief_w])
	e.emotions.values[&"grief"] = 0.0

	# 9. Learning by practice and by teaching
	var learner: Villager = adults[adults.size() - 1]
	var lvl0 := learner.skills.get_level(&"woodcutting")
	var eff0 := learner.skills.efficiency(&"woodcutting")
	learner.practice(&"woodcutting", 400.0)
	check(learner.skills.get_level(&"woodcutting") > lvl0 + 5.0 and learner.skills.efficiency(&"woodcutting") > eff0,
			"9. Practice improves skill and real work speed (%.0f -> %.0f)" % [lvl0, learner.skills.get_level(&"woodcutting")])
	var teacher: Villager = a if a != learner else b
	teacher.skills.levels[&"building"] = 80.0
	learner.skills.levels[&"building"] = 5.0
	var to := social.conversations.decide(teacher, learner, &"teach")
	to.success = true
	to.teaching = [[teacher.villager_id, learner.villager_id, &"building", 0.08]]
	if to.validate(social):
		to.apply(social)
	check(learner.skills.get_level(&"building") > 5.0, "9. Being taught raises skill (building %.1f)" % learner.skills.get_level(&"building"))

	# 10. Groups influence decisions
	var props := soc.proposals
	var proposer: Villager = a
	var p := props._new_proposal(proposer, &"shrine", "building", "test")
	var friend_member := b
	var outsider: Villager = null
	for v in _adults():
		if soc.groups.alignment(v.villager_id, proposer.villager_id) <= 0.0 and v != proposer:
			outsider = v
	soc.groups._membership[proposer.villager_id] = [9999]
	soc.groups._membership[friend_member.villager_id] = [9999]
	g.set_opinion(friend_member.villager_id, proposer.villager_id, 0.0, 0.5)
	var with_group: float = props.evaluate(friend_member, p)[0]
	soc.groups._membership[friend_member.villager_id] = []
	var without_group: float = props.evaluate(friend_member, p)[0]
	check(with_group > without_group, "10. Group members back each other's proposals (%.2f vs %.2f)" % [with_group, without_group])

	# 11. Proposal -> decision -> construction -> outcome
	soc.politics._set_government(&"none", [] as Array[int], "test")
	for v in main.tribe.villagers:
		if v.is_adult():
			props.set_stance(p["id"], v.villager_id, 1)
	main.tribe.stockpile.add(ResourceType.STONE, 100)
	main.tribe.stockpile.add(ResourceType.WOOD, 100)
	props._decide(p)
	check(p["state"] == "approved" and p["site"] > 0, "11. A supported proposal is approved and its site placed")
	var site: Building = null
	for bld in main.tribe.buildings:
		if bld.entity_id == p["site"]:
			site = bld
	if site != null:
		var prestige0 := proposer.prestige
		for k in site.def.costs:
			site.delivered[k] = site.def.costs[k]
		site.add_work(1000.0, proposer.villager_id)
		check(p["state"] == "completed" and proposer.prestige > prestige0, "11. Completing it raises the proposer's prestige")

	# 12. Professions emerge from practice
	var pro: Villager = adults[1]
	pro.profession = &""
	pro.skills.recent.clear()
	pro.skills.levels[&"stonework"] = 45.0
	pro.skills.recent[&"stonework"] = 300.0
	soc.professions._evaluate(pro)
	check(pro.profession == &"Stoneworker", "12. Steady practice makes %s a stoneworker" % pro.villager_name)

	# 13. Leadership emerges and changes
	soc.politics._set_government(&"none", [] as Array[int], "test")
	var cand: Villager = adults[0]
	var rival_c: Villager = adults[1]
	cand.personality.values[&"ambition"] = 0.9
	cand.personality.values[&"status_desire"] = 0.9
	cand.prestige = 40.0
	rival_c.personality.values[&"ambition"] = 0.9
	rival_c.personality.values[&"status_desire"] = 0.9
	rival_c.prestige = 40.0
	soc.politics.endorsements.clear()
	for v in main.tribe.villagers:
		if v.is_adult() and v != cand:
			soc.politics.endorse(v.villager_id, cand.villager_id)
			main.ctx.social.graph.set_opinion(v.villager_id, cand.villager_id, 0.3, 0.6)
	# Small tribes only pick a chief in hard times: make it a food crisis.
	main.tribe.stockpile.take(ResourceType.FOOD, 100000)
	soc.politics._update_government()
	check(soc.politics.government == &"chief" and soc.politics.primary_leader() == cand.villager_id,
			"13. With majority backing, %s is chosen as chief" % cand.villager_name)
	for v in main.tribe.villagers:
		if v != cand:
			g.set_opinion(v.villager_id, cand.villager_id, -0.8, 0.1)
			if v != rival_c and v.is_adult():
				soc.politics.endorse(v.villager_id, rival_c.villager_id)
	main.tribe.stockpile.take(ResourceType.FOOD, 100000)
	soc.politics._update_government()
	check(soc.politics.primary_leader() == rival_c.villager_id, "13. An unpopular chief is replaced by %s" % rival_c.villager_name)

	# 14. Disputes reduce cooperation and shape the settlement
	var p2 := props._new_proposal(rival_c, &"shrine", "building", "test 2")
	var foe: Villager = adults[2]
	g.set_opinion(foe.villager_id, rival_c.villager_id, 0.2, 0.6)
	var before_fight: float = props.evaluate(foe, p2)[0]
	var fight := social.conversations.decide(foe, rival_c, &"insult")
	fight.style = &"fight"
	fight.add_memory(foe.villager_id, &"fought", rival_c.villager_id)
	fight.add_memory(foe.villager_id, &"fought", rival_c.villager_id)
	if fight.validate(social):
		fight.apply(social)
	g.set_tag(foe.villager_id, rival_c.villager_id, &"rival", true)
	var after_fight: float = props.evaluate(foe, p2)[0]
	check(after_fight < before_fight, "14. After a fight, %s opposes %s's plans (%.2f -> %.2f)" % [foe.villager_name, rival_c.villager_name, before_fight, after_fight])
	var hut_of_rival: Building = null
	for bld in main.tribe.buildings:
		if bld.def.id == &"hut" and bld.is_complete:
			hut_of_rival = bld
			bld.owner_ids.assign([rival_c.villager_id])
			break
	var hut_def := BuildingCatalog.get_def(&"hut")
	var near := hut_of_rival.global_position + Vector3(6, 0, 0)
	var as_rival := main.tribe.planner.score_site(hut_def, near, foe)
	g.set_tag(foe.villager_id, rival_c.villager_id, &"rival", false)
	g.set_opinion(foe.villager_id, rival_c.villager_id, 0.6, 0.6)
	var as_friend := main.tribe.planner.score_site(hut_def, near, foe)
	check(as_rival < as_friend, "14. %s would rather not live next to a rival (%.2f vs %.2f as friends)" % [foe.villager_name, as_rival, as_friend])

	# Inspection & chronicle produce real content
	var panels := main.hud.panels
	main.interaction.select(a)
	var text := panels.inspect_text(a)
	check(text.contains("Latest decision") and text.contains("Emotions") and text.contains("Relationships"),
			"17. The inspector explains a villager (decision, emotions, relationships)")
	check(panels.chronicle_text().contains("Day"), "17. The chronicle lists the tribe's history")
	check(panels.tribe_text().contains("Government"), "17. The tribe panel shows government and culture")


# --------------------------------------------------------------------------
# Save / load
# --------------------------------------------------------------------------

func fingerprint() -> String:
	var parts: PackedStringArray = []
	parts.append("day=%d tick=%d" % [SimClock.get_day(), SimClock.tick_count])
	for v in main.tribe.villagers:
		parts.append("%d:%s:%s:%.2f:%s:%d" % [v.villager_id, v.villager_name, v.sex, v.age_years, v.profession,
			v.parent_ids.size()])
	parts.append(str(main.tribe.stockpile.amounts()))
	var bl: PackedStringArray = []
	for b in main.tribe.buildings:
		bl.append("%s@%d" % [b.def.id, b.entity_id])
	parts.append(",".join(bl))
	parts.append(var_to_str(main.ctx.social.graph.to_dict()))
	parts.append(var_to_str(main.ctx.society.to_dict()))
	return "\n".join(parts)


func _verify_load() -> void:
	print("[society] verifying loaded game from %s" % load_path)
	var f := FileAccess.open(load_path + ".fingerprint", FileAccess.READ)
	var expected := f.get_as_text()
	f.close()
	var got := fingerprint()
	if got != expected:
		var a := expected.split("\n")
		var b := got.split("\n")
		for i in mini(a.size(), b.size()):
			if a[i] != b[i]:
				print("    first difference at line %d:\n      saved:  %s\n      loaded: %s" % [i, a[i].left(200), b[i].left(200)])
				break
	check(got == expected, "16. Loading restores villagers, families, relationships, institutions and history exactly")
	check(main.tribe.population() > 0 and main.ctx.society.history.entries.size() > 0, "16. The loaded tribe is alive and has its history")


func _summary() -> void:
	var soc := main.ctx.society
	var social := main.ctx.social
	var buildings := {}
	for b in main.tribe.buildings:
		buildings[String(b.def.id)] = int(buildings.get(String(b.def.id), 0)) + 1
	print("[summary] seed=%d pop=%d births=%d couples=%d breakups=%d gov=%s discoveries=%s professions=%s groups=%d traditions=%s projects=%d buildings=%s" % [
		seed_value, main.tribe.population(), soc.demographics.births, social.romance.couples_formed, social.romance.breakups,
		soc.politics.government, str(soc.tech.discovered.keys()), str(soc.professions.known_professions.keys()),
		soc.groups.groups.size(), str(soc.culture.traditions.keys()), soc.proposals.completed, str(buildings)])
