class_name SocietyPanels
extends Control
## Observability for the social simulation, kept out of the normal HUD:
##   Inspector (I)  - everything about the selected villager, including the
##                    reasons behind their latest decision
##   Chronicle (C)  - the tribe's history
##   Tribe (T)      - government, culture, groups, professions, projects
##   Culture (K)    - the tribe's values, customs, memory, language and art,
##                    with the reasons behind each change
## Panels refresh a few times per second, not every frame.

const REFRESH := 0.5

var ctx: WorldContext
var interaction: WorldInteraction
var hud_theme: Theme
var inspect_mode := false

var _inspector: PanelContainer
var _inspector_text: RichTextLabel
var _chronicle: PanelContainer
var _chronicle_text: RichTextLabel
var _tribe: PanelContainer
var _tribe_text: RichTextLabel
var _culture: PanelContainer
var _culture_text: RichTextLabel
var _timer := 0.0


func setup(context: WorldContext, world_interaction: WorldInteraction, t: Theme) -> void:
	ctx = context
	interaction = world_interaction
	hud_theme = t


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = hud_theme
	_inspector = _make_panel(Vector2(430, 560))
	_inspector_text = _inspector.get_child(0)
	_inspector.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 12)
	_inspector.offset_top = 170
	_inspector.offset_left = -442
	_inspector.offset_right = -12
	_inspector.offset_bottom = 170 + 560
	_chronicle = _make_panel(Vector2(520, 460))
	_chronicle_text = _chronicle.get_child(0)
	_chronicle.position = Vector2(14, 110)
	_tribe = _make_panel(Vector2(520, 460))
	_tribe_text = _tribe.get_child(0)
	_tribe.position = Vector2(14, 110)
	_culture = _make_panel(Vector2(600, 620))
	_culture_text = _culture.get_child(0)
	_culture.position = Vector2(14, 110)
	for p in [_inspector, _chronicle, _tribe, _culture]:
		p.visible = false


func _make_panel(size_hint: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size_hint
	panel.size = size_hint
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = true
	text.custom_minimum_size = size_hint - Vector2(24, 24)
	text.add_theme_font_size_override("normal_font_size", 13)
	text.add_theme_font_size_override("bold_font_size", 14)
	text.add_theme_color_override("default_color", Color(0.92, 0.9, 0.84))
	panel.add_child(text)
	add_child(panel)
	return panel


func toggle_inspect() -> void:
	inspect_mode = not inspect_mode
	_refresh()


func toggle_chronicle() -> void:
	_chronicle.visible = not _chronicle.visible
	_tribe.visible = false
	_culture.visible = false
	_refresh()


func toggle_tribe() -> void:
	_tribe.visible = not _tribe.visible
	_chronicle.visible = false
	_culture.visible = false
	_refresh()


func toggle_culture() -> void:
	_culture.visible = not _culture.visible
	_chronicle.visible = false
	_tribe.visible = false
	_refresh()


func is_culture_open() -> bool:
	return _culture.visible


func is_chronicle_open() -> bool:
	return _chronicle.visible


func is_tribe_open() -> bool:
	return _tribe.visible


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		_refresh()


func _refresh() -> void:
	if ctx == null:
		return
	var v := interaction.selected as Villager if interaction.selected is Villager else null
	_inspector.visible = inspect_mode and v != null and is_instance_valid(v)
	if _inspector.visible:
		_inspector_text.text = inspect_text(v)
	if _chronicle.visible:
		_chronicle_text.text = chronicle_text()
	if _tribe.visible:
		_tribe_text.text = tribe_text()
	if _culture.visible:
		_culture_text.text = culture_text()


# --------------------------------------------------------------------------
# Texts (public so tests can check them)
# --------------------------------------------------------------------------

func _bar(value: float, width: int = 10) -> String:
	var n := clampi(int(round(value * width)), 0, width)
	return "[color=#e6b85c]" + "|".repeat(n) + "[/color][color=#555]" + "|".repeat(width - n) + "[/color]"


func inspect_text(v: Villager) -> String:
	var social := ctx.social
	var society := ctx.society
	var id := v.villager_id
	var t := PackedStringArray()
	t.append("[b]%s[/b]  #%d  ·  %s, %d (%s)%s" % [v.villager_name, id, v.sex, int(v.age_years), v.life_stage(),
			"  ·  [color=#f0a]expecting[/color]" if v.pregnancy_days >= 0.0 else ""])
	t.append("Profession: %s  ·  Prestige %d  ·  Influence %d%s" % [v.profession if v.profession != &"" else "none",
			int(v.prestige), int(society.politics.influence(v)), "  ·  [color=#fd6]%s[/color]" % society.politics.title() if society.politics.is_leader(v) else ""])
	t.append("Task: %s" % v.get_task_description())
	# Decision reasons
	t.append("\n[b]Latest decision:[/b] %s" % v.brain.last_choice)
	var ranked: Array = v.brain.last_scores.keys()
	ranked.sort_custom(func(a, b): return v.brain.last_scores[a] > v.brain.last_scores[b])
	for g in ranked.slice(0, 5):
		var trace: Array = v.brain.last_trace.get(g, [])
		t.append("  %s [color=#9c9]%.2f[/color]  [color=#999]%s[/color]" % [g, v.brain.last_scores[g], " → ".join(trace)])
	# Needs and emotions
	t.append("\n[b]Needs[/b]  health %d · hunger %d · energy %d · loneliness %d" % [v.needs.health, v.needs.hunger, v.needs.energy, v.needs.social])
	t.append("[b]Emotions[/b]  mood %+.2f" % v.emotions.mood())
	for pair in v.emotions.dominant(6, 0.08):
		var why := v.emotions.reasons_for(pair[0], 1)
		t.append("  %s %s  [color=#999]%s[/color]" % [_bar(pair[1]), pair[0], why[0] if not why.is_empty() else ""])
	# Personality
	var traits := PackedStringArray()
	for tr in Personality.TRAITS:
		traits.append("%s %d" % [String(tr).substr(0, 6), int(v.personality.get_trait(tr) * 100.0)])
	t.append("\n[b]Personality[/b]  %s" % "  ·  ".join(v.personality.descriptors(4)))
	t.append("[color=#aaa]%s[/color]" % ", ".join(traits))
	# Skills
	var sk := PackedStringArray()
	for k in VillagerSkills.LIST:
		var lvl := v.skills.get_level(k)
		if lvl >= 1.0:
			sk.append("%s %d" % [k, int(lvl)])
	t.append("\n[b]Skills[/b]  %s%s" % [", ".join(sk), "  ·  has a tool" if v.tool_durability > 0.0 else ""])
	var techs: Array = society.tech.known.get(id, {}).keys()
	if not techs.is_empty():
		t.append("Knows: %s" % ", ".join(techs.map(func(x): return TechSystem.TECHS[x]["label"])))
	# Family
	var demo := society.demographics
	t.append("\n[b]Family[/b]  partner: %s  ·  parents: %s  ·  children: %s  ·  siblings: %s" % [
		social.name_of(social.partner_of(id)) if social.partner_of(id) >= 0 else "none",
		_names(demo.parents_of(id)), _names(demo.children_of(id)), _names(demo.siblings_of(id))])
	if v.sex == &"female" and v.is_adult():
		var blocker := demo.conception_blocker(v)
		t.append("[color=#999]Children: %s[/color]" % ("possible" if blocker == "" else blocker))
	# Relationships
	t.append("\n[b]Relationships[/b]  (affection / trust / respect / attraction / resentment)")
	var others: Array = social.graph.known_by(id).filter(func(o): return social.is_alive(o))
	others.sort_custom(func(a, b): return absf(social.graph.affinity(id, a)) + social.graph.attraction(id, a) > absf(social.graph.affinity(id, b)) + social.graph.attraction(id, b))
	for o in others.slice(0, 8):
		var g := social.graph
		var tags := g.tags(id, o)
		t.append("  %s: %+.2f / %.2f / %+.2f / %.2f / %.2f %s" % [social.name_of(o), g.affinity(id, o), g.trust(id, o),
				g.respect(id, o), g.attraction(id, o), g.resentment(id, o), "[color=#fc8]" + ", ".join(tags) + "[/color]" if not tags.is_empty() else ""])
	var grps := society.groups.groups_of(id).map(func(gr): return gr["name"])
	t.append("Groups: %s" % (", ".join(grps) if not grps.is_empty() else "none"))
	# Beliefs, customs and stories
	var cul := society.culture
	var bel := PackedStringArray()
	for item in cul.values_of(v).strongest(5, false):
		if absf(item[1]) >= 0.05:
			bel.append("%s %+.2f" % [CulturalValues.LABELS[item[0]], item[1]])
	t.append("\n[b]Beliefs[/b]  %s" % (", ".join(bel) if not bel.is_empty() else "none strongly held yet"))
	var keeps := PackedStringArray()
	for c in cul.customs.values():
		if c["status"] in CultureSystem.ACTIVE:
			var d := cul.devotion_of(id, c["id"])
			if absf(d) >= 0.15:
				keeps.append("%s %s (%+.2f)" % ["keeps" if d > 0.0 else "rejects", String(c["word"]).capitalize(), d])
	if not keeps.is_empty():
		t.append("Customs: %s" % ", ".join(keeps))
	var stories := cul.lore.known_by(id)
	if not stories.is_empty():
		t.append("Knows %d stories, e.g. \"%s\"" % [stories.size(), cul.lore.text_for(stories[0], id, social)])
	# Memories and talk
	t.append("\n[b]Memories[/b]")
	for r in v.memory.notable(7):
		t.append("  %s %s" % ["[color=#9c9]+[/color]" if r.valence >= 0.0 else "[color=#e77]-[/color]", MemoryPolicy.describe(r, social.name_of)])
	if not v.conversation_log.is_empty():
		t.append("\n[b]Recently said[/b]")
		for line in v.conversation_log.slice(maxi(0, v.conversation_log.size() - 4)):
			t.append("  [color=#ccc]%s[/color]" % line)
	return "\n".join(t)


func _names(ids: Array) -> String:
	if ids.is_empty():
		return "none"
	return ", ".join(ids.map(func(i): return ctx.social.name_of(i) + ("" if ctx.social.is_alive(i) else "†")))


func chronicle_text() -> String:
	var t := PackedStringArray()
	t.append("[b]Chronicle of %s[/b]\n" % ctx.tribe.tribe_name)
	var colors := {"birth": "#9de", "death": "#e88", "romance": "#f9c", "leadership": "#fd6", "discovery": "#bf8",
		"proposal": "#acf", "construction": "#cda", "group": "#cbf", "culture": "#fca", "dispute": "#f96",
		"profession": "#ddb", "skill": "#ddb", "family": "#9de", "life": "#aaa", "economy": "#dc9"}
	var entries := ctx.society.history.entries
	for i in range(entries.size() - 1, maxi(-1, entries.size() - 120), -1):
		var e: Dictionary = entries[i]
		t.append("[color=#888]Day %d[/color]  [color=%s]%s[/color]" % [e["day"], colors.get(e["category"], "#ddd"), e["text"]])
	return "\n".join(t)


func tribe_text() -> String:
	var s := ctx.society
	var t := PackedStringArray()
	t.append("[b]%s[/b]  ·  population %d  ·  births %d  ·  deaths %d" % [ctx.tribe.tribe_name, ctx.tribe.population(),
			s.demographics.births, ctx.tribe.deaths])
	t.append("\n[b]Government[/b]  %s  (since day %d)" % [s.politics.government_label(), s.politics.since_day])
	var leader := ctx.social.get_villager(s.politics.primary_leader())
	if leader != null:
		t.append("Approval of %s: %+.2f" % [leader.villager_name, s.politics.approval(leader)])
	var candidates := {}
	for voter in s.politics.endorsements:
		var c: int = s.politics.endorsements[voter]
		candidates[c] = int(candidates.get(c, 0)) + 1
	for c in candidates:
		t.append("  %s is backed by %d" % [ctx.social.name_of(c), candidates[c]])
	t.append("\n[b]Culture[/b]  %s" % s.culture.describe())
	var trads := s.culture.tradition_names()
	t.append("Customs: %s  [color=#999](details: Culture panel, K)[/color]" % (", ".join(trads) if not trads.is_empty() else "none yet"))
	t.append("\n[b]Groups[/b]")
	for g in s.groups.groups.values():
		t.append("  %s (%s, %d members, since day %d)" % [g["name"], g["kind"], g["members"].size(), g["founded"]])
	if s.groups.rivalries.size() > 0:
		t.append("  [color=#f96]%d rivalries between groups[/color]" % s.groups.rivalries.size())
	t.append("\n[b]Professions[/b]")
	for title in ProfessionSystem.TITLES.values():
		var m := s.professions.members(title)
		if not m.is_empty():
			t.append("  %s: %s" % [title, ", ".join(m.map(func(v): return v.villager_name))])
	t.append("\n[b]Knowledge[/b]")
	for tech in TechSystem.TECHS:
		if s.tech.discovered.has(tech):
			var k := s.tech.knowers(tech)
			t.append("  %s: known by %d%s" % [TechSystem.TECHS[tech]["label"], k.size(), "  [color=#e88](lost)[/color]" if s.tech.lost.has(tech) else ""])
	t.append("\n[b]Projects[/b]  completed %d · failed %d" % [s.proposals.completed, s.proposals.failed])
	for p in s.proposals.proposals.values():
		if p["state"] in ["open", "approved"]:
			t.append("  %s (%s, by %s, support %+.2f)" % [s.proposals.label_of(p), p["state"], ctx.social.name_of(p["proposer"]),
					s.proposals.support(p)])
	t.append("\n[b]Economy[/b]  %s  ·  tools made %d · traded %d · gifted %d · %d%% of adults have tools" % [
			s.economy.mode_label(), s.economy.tools_made, s.economy.trades, s.economy.gifts, int(s.economy.tool_access() * 100.0)])
	return "\n".join(t)


## The tribe's culture, explained from the simulation's own records.
func culture_text() -> String:
	var c := ctx.society.culture
	var social := ctx.social
	var t := PackedStringArray()
	var own := c.language.display(&"people")
	t.append("[b]Culture of %s[/b]%s" % [ctx.tribe.tribe_name, ("  ·  " + own) if own != "" else ""])
	t.append("[color=#999]Shared words: %d  ·  customs kept: %d  ·  stories remembered: %d (%d lost)[/color]" % [
			c.language.size(), c.live_count(), c.lore.living().size(), c.lore.forgotten])
	# Values
	t.append("\n[b]Dominant values[/b]")
	var dom := c.dominant_values(6)
	if dom.is_empty():
		t.append("  The tribe does not yet share strong beliefs.")
	for item in dom:
		var tr := c.trend(item[0])
		var arrow := "[color=#9c9]rising[/color]" if tr > 0.03 else ("[color=#e88]falling[/color]" if tr < -0.03 else "steady")
		var w := c.language.word(StringName("value_" + String(item[0])))
		t.append("  %s %+.2f  %s%s" % [CulturalValues.LABELS[item[0]], item[1], arrow, ("  ([i]%s[/i])" % w.capitalize()) if w != "" else ""])
		var why := c.explain_value(item[0])
		if why != "":
			t.append("    [color=#aaa]%s[/color]" % why)
	# Customs
	t.append("\n[b]Customs and traditions[/b]")
	var any := false
	for status in ["central", "established", "contested", "emerging", "fading"]:
		for cu in c.customs.values():
			if cu["status"] != status:
				continue
			any = true
			var kind := CustomCatalog.get_kind(StringName(cu["kind"]))
			var scope: String = (" [color=#cbf](%s)[/color]" % cu["scope_name"]) if int(cu["scope"]) >= 0 else ""
			t.append("  [color=#fca]%s[/color] \"%s\" - %s, %s.%s  [color=#999]%s · %d%% keep it%s · practised %d×[/color]" % [
					String(cu["word"]).capitalize(), cu["gloss"], kind["describe"], cu["form"], scope, status, int(cu["support"] * 100),
					(", %d%% reject it" % int(cu["opposition"] * 100)) if float(cu["opposition"]) > 0.05 else "", cu["practiced"]])
			var founder: String = cu["founder_name"] + ("" if social.is_alive(int(cu["founder"])) else " (now dead)")
			t.append("    [color=#aaa]Began on day %d %s; first kept by %s.[/color]" % [cu["day"], cu["origin"], founder])
			if float(cu["young"]) >= 0.0 and float(cu["old"]) >= 0.0 and absf(float(cu["young"]) - float(cu["old"])) > 0.2:
				t.append("    [color=#aaa]Young %d%% vs old %d%%.[/color]" % [int(cu["young"] * 100), int(cu["old"] * 100)])
			for r in cu["reforms"]:
				t.append("    [color=#aaa]Day %d: %s changed it from %s to %s.[/color]" % [r["day"], r["by"], r["from"], r["to"]])
	if not any:
		t.append("  None yet - customs arise from what the tribe does again and again.")
	var gone := PackedStringArray()
	for cu in c.customs.values():
		if cu["status"] == "abandoned":
			gone.append("%s (day %d-%d)" % [String(cu["word"]).capitalize(), cu["day"], int(cu.get("ended", cu["day"]))])
	if not gone.is_empty():
		t.append("  [color=#999]Abandoned: %s[/color]" % ", ".join(gone))
	# Norms
	var norms := _norms(c)
	if not norms.is_empty():
		t.append("\n[b]Social expectations[/b]")
		for n in norms:
			t.append("  " + n)
	# Gaining / losing support
	var moving := PackedStringArray()
	for cu in c.customs.values():
		var h: Array = cu["support_hist"]
		if cu["status"] in CultureSystem.ACTIVE and h.size() >= 3:
			var d := float(cu["support"]) - float(h[0][1])
			if absf(d) >= 0.15:
				moving.append("%s %s (%+d%% since day %d)" % [String(cu["word"]).capitalize(), "gaining support" if d > 0.0 else "losing support",
						int(d * 100), h[0][0]])
	for m in c.movements:
		if m["outcome"] == "":
			var cu2: Dictionary = c.customs.get(m["custom"], {})
			moving.append("%s leads %d people against the %s%s" % [social.name_of(m["leader"]), m["members"].size(),
					String(cu2.get("word", "?")).capitalize(), (" (" + m["who"] + ")") if m["who"] != "" else ""])
	if not moving.is_empty():
		t.append("\n[b]Changing[/b]")
		for m in moving:
			t.append("  " + m)
	# Generations
	if int(c.cohort_values.get("n_young", 0)) >= 2 and int(c.cohort_values.get("n_old", 0)) >= 2:
		var diffs := []
		for k in CulturalValues.VALUES:
			diffs.append([k, float(c.cohort_values["young"][k]) - float(c.cohort_values["old"][k])])
		diffs.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
		var parts := PackedStringArray()
		for d in diffs.slice(0, 3):
			if absf(d[1]) >= 0.08:
				parts.append("%s %s (%+.2f vs %+.2f)" % [CulturalValues.LABELS[d[0]], "more" if d[1] > 0.0 else "less",
						c.cohort_values["young"][d[0]], c.cohort_values["old"][d[0]]])
		t.append("\n[b]Generations[/b]  The young (%d) value %s than the old (%d)." % [c.cohort_values["n_young"],
				", ".join(parts) if not parts.is_empty() else "much the same", c.cohort_values["n_old"]])
	# Groups
	var gl := PackedStringArray()
	for g in ctx.society.groups.groups.values():
		var members: Array = g["members"]
		if members.size() < 3:
			continue
		var avg := {}
		for id in members:
			var v := social.get_villager(id)
			if v == null:
				continue
			for k in CulturalValues.VALUES:
				avg[k] = float(avg.get(k, 0.0)) + c.value(v, k) / members.size()
		var best := ""
		var bd := 0.12
		for k in avg:
			var d: float = avg[k] - c.tribe_value(k)
			if absf(d) > bd:
				bd = absf(d)
				best = k
		if best != "":
			gl.append("%s: %s %s (%+.2f vs tribe %+.2f)" % [g["name"], "more" if avg[best] > c.tribe_value(best) else "less",
					String(CulturalValues.LABELS[StringName(best)]).to_lower(), avg[best], c.tribe_value(best)])
	if not gl.is_empty():
		t.append("\n[b]Differences between groups[/b]")
		for line in gl:
			t.append("  " + line)
	# Memory
	t.append("\n[b]Collective memory[/b]")
	var lore := c.lore.living()
	lore.sort_custom(func(a, b): return float(a["importance"]) > float(b["importance"]))
	if lore.is_empty():
		t.append("  Nothing yet.")
	for e in lore.slice(0, 6):
		var levels := {}
		for id in e["knowers"]:
			if social.is_alive(id):
				var l := int(e["knowers"][id][0])
				levels[l] = int(levels.get(l, 0)) + 1
		var common := 0
		var cn := -1
		for l in levels:
			if int(levels[l]) > cn:
				cn = int(levels[l])
				common = l
		var title := c.lore.title(e, common, social)
		var w: String = e["word"]
		t.append("  [color=#fd9]%s[/color]%s - day %d, known by %d%s" % [title.capitalize(), ("  ([i]%s[/i])" % w.capitalize()) if w != "" else "",
				e["day"], c.lore.living_knowers(e, social), "  [color=#999](told in %d versions)[/color]" % levels.size() if levels.size() > 1 else ""])
		t.append("    [color=#aaa]\"%s\"[/color]" % c.lore.render(e, common, social))
		var views := PackedStringArray()
		for g in ctx.society.groups.groups.values():
			if g["members"].size() < 3:
				continue
			var gv: Array = c.lore.group_valence(e, g["members"])
			if int(gv[1]) >= 2 and absf(float(gv[0])) > 0.2:
				views.append("%s remember it %s" % [g["name"], "proudly" if float(gv[0]) > 0.0 else "bitterly"])
		if not views.is_empty():
			t.append("    [color=#aaa]%s.[/color]" % "; ".join(views))
	# Figures
	var figs := c.influential_figures(5)
	if not figs.is_empty():
		t.append("\n[b]Influential figures[/b]  %s" % ", ".join(figs.map(func(f): return f[1] + ("" if social.is_alive(f[0]) else "†"))))
	# Art
	var a := c.aesthetics
	t.append("\n[b]Art and architecture[/b]  level %d - %s" % [a.art_level, ["no decoration yet", "body paint and sashes",
			"painted homes", "carving and monuments"][a.art_level]])
	for p in a.palette:
		t.append("  [color=#%s]■[/color] %s: %s (day %d)" % [TribalAesthetics.PIGMENTS[p["name"]][0].to_html(false), p["name"], p["reason"], p["day"]])
	if a.motif != "":
		t.append("  Motif: %s. [color=#aaa]%s[/color]" % [a.motif, a.motif_reason])
	for e in a.eras:
		t.append("  Since day %d: %s. [color=#aaa]%s[/color]" % [e["day"], e["name"], e["reason"]])
	# Language
	if c.language.size() > 0:
		var words := PackedStringArray()
		for k in c.language.lexicon:
			words.append(c.language.display(k))
		t.append("\n[b]Language[/b]  %s" % ", ".join(words))
	# Changes
	t.append("\n[b]How the culture changed[/b]")
	for i in range(c.changes.size() - 1, maxi(-1, c.changes.size() - 12), -1):
		t.append("  [color=#888]Day %d[/color]  %s" % [c.changes[i]["day"], c.changes[i]["text"]])
	return "\n".join(t)


## The expectations the tribe's customs and values place on its members.
func _norms(c: CultureSystem) -> PackedStringArray:
	var out := PackedStringArray()
	if c.strength(&"sharing_custom") >= 0.3 or c.tribe_value(&"generosity") >= 0.25:
		out.append("Refusing food to the hungry costs a person respect.")
	if c.ration_limit() < 99:
		out.append("No one takes more than %d food from the stores at a time." % c.ration_limit())
	if c.strength(&"peacekeeping") >= 0.35:
		out.append("Quarrels are taken to the respected to settle.")
	if c.strength(&"contest") >= 0.35:
		out.append("A fight ends a quarrel; grudges afterwards are frowned upon.")
	if c.strength(&"vows") >= 0.3 or c.tribe_value(&"loyalty") >= 0.3:
		out.append("Partners are expected to stay together.")
	if c.tribe_value(&"elders") >= 0.25:
		out.append("Elders' words carry extra weight in decisions.")
	if c.election_share() > 0.6:
		out.append("A chief needs the backing of %d%% of adults." % int(c.election_share() * 100))
	if c.tribe_value(&"nature") >= 0.3:
		out.append("Trees are not felled without need.")
	if c.tribe_value(&"hierarchy") >= 0.25:
		out.append("The leader's decisions are followed.")
	if c.tribe_value(&"independence") >= 0.25:
		out.append("Each household is expected to look after itself.")
	for cu in c.customs.values():
		if cu["status"] == "central":
			out.append("Everyone is expected to keep the %s; those who stay away are looked down on." % String(cu["word"]).capitalize())
	var recent := 0
	for vi in c.violations:
		if SimClock.get_day() - int(vi[1]) <= 5:
			recent += 1
	if recent > 0:
		out.append("[color=#e98]%d breaches of custom in the last days.[/color]" % recent)
	return out
