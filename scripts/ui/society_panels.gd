class_name SocietyPanels
extends Control
## Observability for the social simulation, kept out of the normal HUD:
##   Inspector (I)  - everything about the selected villager, including the
##                    reasons behind their latest decision
##   Chronicle (C)  - the tribe's history
##   Tribe (T)      - government, culture, groups, professions, projects
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
	for p in [_inspector, _chronicle, _tribe]:
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
	_refresh()


func toggle_tribe() -> void:
	_tribe.visible = not _tribe.visible
	_chronicle.visible = false
	_refresh()


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
	t.append("Traditions: %s" % (", ".join(trads) if not trads.is_empty() else "none yet"))
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
