extends Node
## Cultural evolution test.
##
## Lets the tribe live on its own for N days, prints its culture (values,
## customs, stories, words, art), checks that culture emerged from what
## happened, then exercises each mechanism directly.
## Run:  godot --headless --path . res://tests/culture_test.tscn --fixed-fps 60 -- --seed=42 --days=40
## Options: --report-only (no mechanism checks), --chronicle (print culture history)

var main: Main
var seed_value := 42
var days := 40.0
var failures: Array[String] = []
var _done := false
var report_only := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.split("=")[1])
		elif arg.begins_with("--days="):
			days = float(arg.split("=")[1])
		elif arg == "--report-only":
			report_only = true
	var cfg: GameConfig = load("res://config/default_config.tres").duplicate()
	cfg.world_seed = seed_value
	main = load("res://scenes/main.tscn").instantiate()
	main.config = cfg
	add_child(main)
	SimClock.set_time_scale(8.0)


func check(cond: bool, what: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", what])
	if not cond:
		failures.append(what)


func _process(_delta: float) -> void:
	if _done or SimClock.sim_time < days * SimClock.day_length:
		return
	_done = true
	SimClock.set_paused(true)
	report()
	if OS.get_cmdline_user_args().has("--chronicle"):
		for e in main.ctx.society.history.entries:
			if e["category"] == "culture":
				print("  [day %d] %s" % [e["day"], e["text"]])
	_emergent_checks()
	if not report_only:
		_mechanism_checks()
	print("[culture] RESULT: %s (%d failures)" % ["OK" if failures.is_empty() else "FAILED", failures.size()])
	for f in failures:
		print("   - " + f)
	get_tree().quit(0 if failures.is_empty() else 1)


func report() -> void:
	var c := main.ctx.society.culture
	print("[culture] seed=%d day=%d pop=%d name=%s" % [seed_value, SimClock.get_day(), main.tribe.population(), main.tribe.tribe_name])
	print("[culture] values: %s" % c.describe())
	var pats := []
	for p in c.patterns:
		pats.append("%s=%d" % [p, c.patterns[p]["count"]])
	print("[culture] patterns: %s" % ", ".join(pats))
	for cu in c.customs.values():
		print("[culture] custom %s (%s, %s) status=%s support=%d%% opp=%d%% young=%d%% old=%d%% practiced=%d scope=%s form=%s" % [
				cu["word"], cu["kind"], cu["gloss"], cu["status"], int(cu["support"] * 100), int(cu["opposition"] * 100),
				int(cu["young"] * 100), int(cu["old"] * 100), cu["practiced"], cu["scope_name"] if int(cu["scope"]) >= 0 else "tribe", cu["form"]])
	for e in c.lore.living(true):
		print("[culture] lore #%d %s day %d knowers=%d retold=%d lost=%s: %s" % [e["id"], e["kind"], e["day"], e["knowers"].size(),
				e["retold"], e["lost"], c.lore.render(e, 0, main.ctx.social)])
	var words := []
	for k in c.language.lexicon:
		words.append(c.language.display(k))
	print("[culture] lexicon (%d): %s" % [c.language.size(), ", ".join(words)])
	print("[culture] art level %d motif %s palette %s eras %s" % [c.aesthetics.art_level, c.aesthetics.motif,
			c.aesthetics.palette.map(func(p): return p["name"]), c.aesthetics.eras.map(func(e): return e["name"])])
	print("[culture] movements %d, changes %d, legacies %d" % [c.movements.size(), c.changes.size(), c.legacies.size()])


func _emergent_checks() -> void:
	var c := main.ctx.society.culture
	print("[culture] emergent checks after %d days" % int(days))
	var any := 0
	for cu in c.customs.values():
		any += 1
	check(any >= 1, "A. Customs arose from what happened (%d)" % any)
	var origins_ok := true
	for cu in c.customs.values():
		if not String(cu["origin"]).begins_with("after") and not String(cu["origin"]).begins_with("as") \
				and not String(cu["origin"]).begins_with("when") and not String(cu["origin"]).begins_with("to keep"):
			origins_ok = false
	check(origins_ok, "A. Every custom records the events it came from")
	check(not c.dominant_values(3).is_empty(), "B. The tribe holds shared values: %s" % c.describe())
	check(c.lore.living(true).size() >= 1, "H. The tribe remembers events (%d stories)" % c.lore.living(true).size())
	check(c.language.size() >= 1, "E. The tribe has coined words of its own (%d)" % c.language.size())


func _adults() -> Array:
	var out := main.tribe.villagers.filter(func(v): return v.is_adult())
	out.sort_custom(func(a, b): return a.villager_id < b.villager_id)
	return out


func _set_values(v: Villager, vals: Dictionary) -> void:
	var cv := main.ctx.society.culture.values_of(v)
	for k in CulturalValues.VALUES:
		cv.values[k] = float(vals.get(k, 0.0))


func _mechanism_checks() -> void:
	var soc := main.ctx.society
	var c := soc.culture
	var social := main.ctx.social
	var adults := _adults()
	print("[culture] mechanism checks")
	if adults.size() < 4:
		check(false, "Need at least 4 adults for the mechanism checks (%d)" % adults.size())
		return
	var a: Villager = adults[0]
	var b: Villager = adults[1]
	var d: Villager = adults[2]
	var e: Villager = adults[3]
	var saved_customs := c.customs.duplicate(true)
	var saved_patterns := c.patterns.duplicate(true)

	# --- A. The same hardship gives different customs to different people ---
	c.customs.clear()
	for v in [a, b, d]:
		_set_values(v, {&"cooperation": 0.6, &"generosity": 0.6})
	c.patterns = {"hardship": {"count": 10, "who": {a.villager_id: 3, b.villager_id: 3, d.villager_id: 3}, "first_day": 1,
		"notes": ["%s fed the starving %s" % [a.villager_name, b.villager_name]], "help": 6, "refused": 1}}
	c._update_tribe_values()
	c._check_patterns()
	var born := c.customs.values()
	check(born.size() == 1 and born[0]["kind"] == "sharing_custom",
			"A. A cooperative tribe that shared through hard times develops a sharing custom (%s)" % (born[0]["kind"] if not born.is_empty() else "none"))
	check(not born.is_empty() and String(born[0]["origin"]).contains(a.villager_name),
			"A. The custom's origin names the real event: \"%s\"" % (born[0]["origin"] if not born.is_empty() else ""))
	c.customs.clear()
	for v in [a, b, d]:
		_set_values(v, {&"hierarchy": 0.6, &"independence": 0.4})
	c.patterns = {"hardship": {"count": 10, "who": {a.villager_id: 3, b.villager_id: 3, d.villager_id: 3}, "first_day": 1,
		"notes": ["%s refused to feed the starving %s" % [b.villager_name, a.villager_name]], "help": 1, "refused": 6}}
	c._update_tribe_values()
	c._check_patterns()
	born = c.customs.values()
	check(born.size() == 1 and born[0]["kind"] == "strict_rationing",
			"A. A hierarchical tribe that turned the hungry away develops strict rationing instead (%s)" % (born[0]["kind"] if not born.is_empty() else "none"))
	c.customs.clear()
	c.patterns = {"evening_talk": {"count": 3, "who": {a.villager_id: 3}, "first_day": 1, "notes": [], "help": 0, "refused": 0}}
	for v in [a, b, d]:
		_set_values(v, {&"cooperation": 0.6})
	c._check_patterns()
	check(c.customs.is_empty(), "A. A behaviour seen only a few times is not yet a custom")
	c.patterns = {"evening_talk": {"count": 40, "who": {a.villager_id: 20, b.villager_id: 20}, "first_day": 1, "notes": [], "help": 0, "refused": 0}}
	for v in main.tribe.villagers:
		_set_values(v, {})
	c._update_tribe_values()
	c._check_patterns()
	check(c.customs.is_empty(), "A. Without shared beliefs to give it meaning, repetition alone makes no custom")

	# --- A. One experience, different lessons ---
	_set_values(a, {&"hierarchy": 0.4})
	_set_values(b, {&"independence": 0.3})
	b.personality.values[&"status_desire"] = 0.2
	b.personality.values[&"empathy"] = 0.2
	var rec := {"other": d.villager_id, "subject": -1, "detail": ""}
	c.on_social_event(a, &"was_refused", rec)
	c.on_social_event(b, &"was_refused", rec)
	check(c.value(a, &"hierarchy") > 0.4 and c.value(b, &"independence") > 0.3,
			"A. Being refused food teaches %s to want order (%.2f) and %s to rely on themselves (%.2f)" % [
			a.villager_name, c.value(a, &"hierarchy"), b.villager_name, c.value(b, &"independence")])

	# --- B. Values influence decisions, economy and politics ---
	# The belief modifier on its own, on the same base scores.
	var mod := CultureModifier.new()
	var base := {&"explore": 0.2, &"help": 0.3, &"craft": 0.3, &"gather_wood": 0.3, &"ceremony": 0.2}
	_set_values(a, {})
	var plain := base.duplicate()
	mod.modify_scores(a, plain)
	_set_values(a, {&"curiosity": 0.8, &"courage": 0.6, &"cooperation": 0.8, &"generosity": 0.6})
	var keen := base.duplicate()
	mod.modify_scores(a, keen)
	check(keen[&"explore"] > plain[&"explore"] and keen[&"help"] > plain[&"help"],
			"B. Valuing curiosity, courage and cooperation makes %s keener to explore (%.2f -> %.2f) and help (%.2f -> %.2f)" % [
			a.villager_name, plain[&"explore"], keen[&"explore"], plain[&"help"], keen[&"help"]])
	_set_values(a, {&"craftsmanship": 0.8, &"spirituality": 0.7})
	var maker := base.duplicate()
	mod.modify_scores(a, maker)
	check(maker[&"craft"] > plain[&"craft"] and maker[&"ceremony"] > plain[&"ceremony"],
			"B. Valuing craft and the spiritual draws them to the workshop (%.2f) and to ceremonies (%.2f)" % [maker[&"craft"], maker[&"ceremony"]])
	_set_values(a, {&"achievement": 0.9, &"nature": 0.8, &"curiosity": 0.8})
	a.brain.score_goals()
	var traced := false
	for g in a.brain.last_trace:
		for step in a.brain.last_trace[g]:
			if String(step).begins_with("Beliefs"):
				traced = true
	check(traced, "B. The inspector's decision trace shows the effect of beliefs")
	for v in main.tribe.villagers:
		_set_values(v, {&"cooperation": 0.6, &"generosity": 0.5})
	c._update_tribe_values()
	var communal := soc.economy.is_communal()
	for v in main.tribe.villagers:
		_set_values(v, {&"independence": 0.7})
	c._update_tribe_values()
	check(communal and not soc.economy.is_communal(), "B. A cooperative culture keeps tools in common; an independent one keeps them private")
	for v in main.tribe.villagers:
		_set_values(v, {&"equality": 0.7})
	c._update_tribe_values()
	var eq_share := c.election_share()
	for v in main.tribe.villagers:
		_set_values(v, {&"hierarchy": 0.7})
	c._update_tribe_values()
	check(eq_share > c.election_share(), "B. An egalitarian culture demands broader backing for a chief (%d%% vs %d%%)" % [
			int(eq_share * 100), int(c.election_share() * 100)])
	var elder: Villager = null
	for v in main.tribe.villagers:
		if v.life_stage() == &"elder":
			elder = v
	if elder == null:
		elder = e
		elder.age_years = soc.ctx.config.elder_age + 2.0
	for v in main.tribe.villagers:
		_set_values(v, {})
	c._update_tribe_values()
	var inf_plain := soc.politics.influence(elder)
	for v in main.tribe.villagers:
		_set_values(v, {&"elders": 0.7})
	c._update_tribe_values()
	check(soc.politics.influence(elder) > inf_plain + 5.0, "B. Where elders are respected, %s's voice weighs more (%d -> %d)" % [
			elder.villager_name, int(inf_plain), int(soc.politics.influence(elder))])
	_set_values(a, {&"tradition": 0.8})
	check(c.project_attitude(a, &"totem", true) < c.project_attitude(a, &"totem", false),
			"B. A traditional person is warier of a kind of building the tribe has never had")

	# --- C. Ceremonies: who comes, who stays away, what it does ---
	for v in main.tribe.villagers:
		_set_values(v, {&"spirituality": 0.5, &"tradition": 0.4})
	c._update_tribe_values()
	c.customs.clear()
	c.patterns = {"death": {"count": 5, "who": {a.villager_id: 2, b.villager_id: 2, d.villager_id: 1}, "first_day": 1,
		"notes": ["the death of someone"], "help": 0, "refused": 0}}
	c._check_patterns()
	var rite: Dictionary = c.customs.values()[0] if not c.customs.is_empty() else {}
	check(not rite.is_empty() and rite["kind"] == "funeral_rites", "C. Deaths among a spiritual people become funeral rites (%s)" % rite.get("kind", "none"))
	if not rite.is_empty():
		c._set_devotion(a.villager_id, rite["id"], 0.8)
		c._set_devotion(e.villager_id, rite["id"], -0.7)
		a.brain.suggestions.clear()
		c.start_ceremony(rite, "test rite", main.tribe.campfire.global_position, 30.0)
		var cer: Dictionary = c.ceremonies.back()
		check(a.brain.suggestions.has(&"ceremony") and cer["boycott"].has(e.villager_id),
				"C. %s, who keeps the rite, is drawn to it; %s, who rejects it, stays away" % [a.villager_name, e.villager_name])
		c.attend(cer, a)
		c.attend(cer, b)
		social.graph.set_opinion(a.villager_id, b.villager_id, 0.1, 0.5)
		var aff_before := social.graph.affinity(a.villager_id, b.villager_id)
		var dev_before := c.devotion_of(b.villager_id, rite["id"])
		cer["until"] = SimClock.sim_time - 1.0
		rite["status"] = "central"
		var resp_before := social.graph.respect(a.villager_id, e.villager_id)
		c._close_ceremonies()
		check(social.graph.affinity(a.villager_id, b.villager_id) > aff_before and c.devotion_of(b.villager_id, rite["id"]) > dev_before,
				"C. Taking part together brings people closer and deepens their attachment to the custom")
		check(social.graph.respect(a.villager_id, e.villager_id) < resp_before,
				"C. Staying away from a central custom costs respect among its keepers")

	# --- C. Social expectations: breaking the sharing custom ---
	c.customs.clear()
	for v in main.tribe.villagers:
		_set_values(v, {&"generosity": 0.6, &"cooperation": 0.5})
	c._update_tribe_values()
	var r_before := social.graph.respect(b.villager_id, a.villager_id)
	var shame_before := a.emotions.get_value(&"shame")
	c.on_social_event(a, &"refused", {"other": b.villager_id, "subject": -1, "detail": ""})
	check(social.graph.respect(b.villager_id, a.villager_id) < r_before and a.emotions.get_value(&"shame") > shame_before,
			"C. In a generous culture, refusing food costs respect and brings shame")

	# --- D. Transmission between generations ---
	var child: Villager = null
	for v in main.tribe.villagers:
		if v.is_child() and not v.parent_ids.is_empty():
			child = v
			break
	if child == null:
		var mom: Villager = a if a.sex == &"female" else b
		child = main.tribe.add_villager(mom.global_position, 3.0, &"male", null, null, [a.villager_id, b.villager_id] as Array[int], "Testchild")
	var parents: Array = child.parent_ids.map(func(id): return social.get_villager(id)).filter(func(x): return x != null)
	for p in parents:
		_set_values(p, {&"family": 0.8, &"spirituality": 0.6})
	_set_values(child, {})
	for i in 12:
		c._enculturate()
	check(c.value(child, &"family") > 0.15, "D. %s absorbs their parents' values while growing up (family %+.2f)" % [child.villager_name, c.value(child, &"family")])
	# Young rebels push back sometimes.
	var rebel: Villager = d
	rebel.personality.values[&"independence"] = 0.95
	rebel.personality.values[&"curiosity"] = 0.95
	var old_age := rebel.age_years
	rebel.age_years = soc.ctx.config.adult_age + 1.0
	var rejected := false
	for i in 40:
		_set_values(rebel, {&"tradition": 0.3})
		var before_t := c.value(rebel, &"tradition")
		for o in main.tribe.villagers:
			if o != rebel:
				_set_values(o, {&"tradition": 0.8})
		c._enculturate()
		if c.value(rebel, &"tradition") < before_t:
			rejected = true
			break
	rebel.age_years = old_age
	check(rejected, "D. A restless young person can turn away from what their elders hold dear")
	# Legacy outlives the founder.
	c.customs.clear()
	for v in main.tribe.villagers:
		_set_values(v, {&"cooperation": 0.6, &"hospitality": 0.4})
	c._update_tribe_values()
	c.patterns = {"evening_talk": {"count": 40, "who": {e.villager_id: 30, a.villager_id: 5, b.villager_id: 5}, "first_day": 1,
		"notes": [], "help": 0, "refused": 0}}
	c._check_patterns()
	var fire: Dictionary = c.customs.values()[0] if not c.customs.is_empty() else {}
	check(not fire.is_empty() and fire["kind"] == "evening_fire" and int(fire["founder"]) == e.villager_id,
			"D. Nightly gatherings by the fire become a custom, founded by %s" % e.villager_name)
	for i in 6:
		c._update_customs()
	e.prestige = 60.0
	e.die("test")
	for i in 6:
		c._update_customs()
	check(not fire.is_empty() and fire["status"] in CultureSystem.ACTIVE and float(fire["support"]) >= 0.3 and c.legacies.has(e.villager_id),
			"D. After %s's death their custom lives on (%d%% keep it) and their beliefs are remembered" % [e.villager_name, int(fire.get("support", 0.0) * 100)])
	# A custom nobody believes in fades away.
	for v in main.tribe.villagers:
		_set_values(v, {&"independence": 0.8, &"cooperation": -0.6, &"hospitality": -0.5})
		c._set_devotion(v.villager_id, fire["id"], -0.3)
	fire["day"] = SimClock.get_day() - 10
	for i in 12:
		c._update_customs()
	check(fire["status"] in ["fading", "abandoned"], "D. When people stop believing in it, the custom fades (%s)" % fire["status"])

	# --- E. Language ---
	var lang := c.language
	check(lang.root(&"fire") == lang.root(&"fire") and lang.compound(&"fire", &"together") == lang.compound(&"fire", &"together"),
			"E. Words are consistent: '%s' always means fire" % lang.root(&"fire"))
	var bad := []
	for k in lang.lexicon:
		if not lang.is_well_formed(lang.lexicon[k]["word"]):
			bad.append(lang.lexicon[k]["word"])
	var nm := lang.personal_name(soc.rng)
	check(bad.is_empty() and lang.is_well_formed(nm), "E. Every word and new name follows the tribe's sound system (e.g. %s) %s" % [nm, bad])
	var other_lang := TribalLanguage.new(12345)
	check(other_lang.root(&"fire") != lang.root(&"fire") or other_lang.root(&"water") != lang.root(&"water"),
			"E. Another tribe's language sounds different (%s vs %s)" % [other_lang.root(&"fire"), lang.root(&"fire")])

	# --- H. Collective memory ---
	var dead: Villager = adults[adults.size() - 1]
	var story := c._add_lore("first_leader", [dead.villager_id], [dead.villager_name], {&"hierarchy": 1.0}, 0.8,
			{"x": "chief", "epithet": "the wise"})
	var exact := c.lore.render(story, 0, social)
	check(exact.contains(dead.villager_name) and exact.contains("day"), "H. First-hand memory is exact: \"%s\"" % exact)
	dead.die("test")
	var myth := c.lore.render(story, 3, social)
	var vague := c.lore.render(story, 2, social)
	check(not vague.contains(dead.villager_name) and myth.contains("old days"),
			"H. Retold over generations it drifts: \"%s\" -> \"%s\"" % [vague, myth])
	var lover := CulturalValues.new()
	lover.values[&"hierarchy"] = 0.8
	var hater := CulturalValues.new()
	hater.values[&"equality"] = 0.8
	hater.values[&"hierarchy"] = -0.6
	check(c.lore.valence_for(story, lover) > 0.2 and c.lore.valence_for(story, hater) < -0.2,
			"H. The same story is a proud memory to some and a warning to others (%+.2f vs %+.2f)" % [
			c.lore.valence_for(story, lover), c.lore.valence_for(story, hater)])
	var newcomer: Villager = null
	for v in main.tribe.villagers:
		if not c.lore.knows(story, v.villager_id) and v.is_adult():
			newcomer = v
	var teller: Villager = null
	for v in main.tribe.villagers:
		if c.lore.knows(story, v.villager_id) and v != newcomer:
			teller = v
	if newcomer == null:
		newcomer = child
	if teller != null and newcomer != null:
		var o := ConversationOutcome.new()
		o.speaker_id = teller.villager_id
		o.listener_id = newcomer.villager_id
		c.resolve(&"tell_story", o, teller, newcomer, {"lore": story["id"]}, social.conversations)
		var ok := o.validate(social)
		if ok:
			o.apply(social)
		check(ok and c.lore.knows(story, newcomer.villager_id), "H. Stories pass on in conversation: %s told %s \"%s\"" % [
				teller.villager_name, newcomer.villager_name, o.line_speaker])
	for id in story["knowers"].keys():
		story["knowers"].erase(id)
	c._update_lore()
	check(story["lost"], "H. A story nobody alive remembers is lost")

	# --- F. Art and architecture ---
	var a2 := c.aesthetics
	if a2.palette.is_empty():
		a2.add_pigment("ochre")
	a2.art_level = 2
	if a2.motif == "":
		a2.motif = a2.choose_motif(c.tribe_values)
	if a2.eras.is_empty():
		a2.new_era("painted walls", "test", false)
	var hut: Building = null
	for bld in main.tribe.buildings:
		if bld.def.id == &"hut" and bld.is_complete:
			hut = bld
	c._style_building(hut)
	check(hut.style_era == a2.era_index() and hut._decor != null and hut._decor.visible,
			"F. Homes built in a decorated era are painted with the tribe's %s" % a2.motif)
	c.customs.clear()
	for v in main.tribe.villagers:
		_set_values(v, {&"cooperation": 0.6, &"hospitality": 0.4})
	c.patterns = {"evening_talk": {"count": 40, "who": {a.villager_id: 20, b.villager_id: 20}, "first_day": 1, "notes": [], "help": 0, "refused": 0}}
	c._check_patterns()
	if not c.customs.is_empty():
		var cu: Dictionary = c.customs.values()[0]
		c._set_devotion(a.villager_id, cu["id"], 0.9)
		c._set_devotion(b.villager_id, cu["id"], -0.5)
		a2.art_level = maxi(a2.art_level, 1)
		c._update_adornments()
		check(a.adornment.has("sash") and not b.adornment.has("sash"),
				"F. Those devoted to a custom wear its colour; those who reject it do not")
	var kids_plain := true
	for v in main.tribe.villagers:
		if v.is_child() and v.adornment.has("sash"):
			kids_plain = false
	check(kids_plain, "F. Children do not wear the sashes of customs")

	# --- G. Change and disagreement ---
	if not c.customs.is_empty():
		var cu2: Dictionary = c.customs.values()[0]
		cu2["status"] = "contested"
		var critic: Villager = b
		var reformer: Villager = a
		reformer.personality.values[&"creativity"] = 0.95
		reformer.personality.values[&"curiosity"] = 0.95
		c._set_devotion(reformer.villager_id, cu2["id"], 0.3)
		for v in main.tribe.villagers:
			if v != reformer:
				c._set_devotion(v.villager_id, cu2["id"], -0.4)
				_set_values(v, {&"strength": 0.7, &"courage": 0.5})
		var form_before: String = cu2["form"]
		c._maybe_reform(cu2)
		check(cu2["form"] != form_before and c.devotion_of(critic.villager_id, cu2["id"]) > -0.4,
				"G. An innovator reshapes a contested custom (%s -> %s) and wins critics over" % [form_before, cu2["form"]])

	# --- J. Inspection explains changes from data ---
	c.customs = saved_customs
	c.patterns = saved_patterns
	var panels: SocietyPanels = main.hud.panels
	var text := panels.culture_text()
	check(text.contains("Dominant values") and text.contains("Collective memory") and text.contains("How the culture changed"),
			"J. The culture panel shows values, customs, memory and changes")
	var explained := false
	for ch in c.changes:
		if String(ch["text"]).contains("Mostly because") or String(ch["text"]).contains("It began") or String(ch["text"]).contains("because"):
			explained = true
	check(explained, "J. Cultural changes are explained with their causes")

	# --- Save / load of the culture ---
	var dump := var_to_str(c.to_dict())
	var copy := CultureSystem.new(soc)
	copy.load_dict(str_to_var(dump))
	check(var_to_str(copy.to_dict()) == dump, "Save/load: the culture round-trips exactly")
