class_name Hud
extends CanvasLayer
## Game interface. Built in code from a small style kit so it stays consistent.
## Reads state from the tribe / SimClock and listens to EventBus; the
## simulation never references the UI.

const C_PANEL := Color(0.09, 0.11, 0.10, 0.86)
const C_PANEL_BORDER := Color(0.85, 0.72, 0.45, 0.25)
const C_TEXT := Color(0.94, 0.92, 0.86)
const C_MUTED := Color(0.70, 0.70, 0.64)
const C_ACCENT := Color(0.93, 0.72, 0.36)
const C_BTN := Color(0.20, 0.23, 0.21, 0.95)
const C_BTN_HOVER := Color(0.29, 0.33, 0.29, 1.0)
const C_BTN_PRESSED := Color(0.62, 0.45, 0.22, 1.0)
const NOTIFY_SECONDS := 7.0
const MAX_NOTIFICATIONS := 6

var ctx: WorldContext
var interaction: WorldInteraction
var rts_camera: RtsCamera

var _theme := Theme.new()
var _root: Control
var _value_labels: Dictionary = {}
var _clock_label: Label
var _phase_label: Label
var _pause_button: Button
var _speed_buttons: Array[Button] = []
var _notify_box: VBoxContainer
var _build_hint: Label
var _auto_build_check: CheckBox
var _build_buttons: Dictionary = {}

# Selection panel
var _sel_panel: PanelContainer
var _sel_title: Label
var _sel_subtitle: Label
var _sel_bars: Dictionary = {}
var _sel_info: Label
var _sel_social: Label
var _sel_follow: Button
var _sel_cancel: Button
var _selected: Node3D
var _refresh_timer := 0.0
var _debug_label: Label
var panels: SocietyPanels
var _inspect_button: Button
var _culture_button: Button
var _chronicle_button: Button
var _tribe_button: Button


func setup(context: WorldContext, world_interaction: WorldInteraction, cam: RtsCamera) -> void:
	ctx = context
	interaction = world_interaction
	rts_camera = cam


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_theme()
	_root = Control.new()
	_root.name = "HudRoot"
	_root.theme = _theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_top_bar()
	_build_time_panel()
	_build_notifications()
	_build_selection_panel()
	_build_construction_panel()
	_build_help_hint()
	_build_debug_overlay()
	panels = SocietyPanels.new()
	panels.setup(ctx, interaction, _theme)
	_root.add_child(panels)
	var overlay := RelationshipOverlay.new()
	overlay.setup(ctx, interaction, panels)
	ctx.world_root.add_child(overlay)

	EventBus.stockpile_changed.connect(func(_a): _refresh_resources())
	EventBus.population_changed.connect(func(_c): _refresh_resources())
	EventBus.building_completed.connect(func(_b): _refresh_resources())
	EventBus.building_placed.connect(func(_b): _refresh_resources())
	EventBus.building_removed.connect(func(_b): _refresh_resources())
	EventBus.selection_changed.connect(_on_selection_changed)
	EventBus.notification_posted.connect(_add_notification)
	SimClock.speed_changed.connect(func(_s, _p): _refresh_speed_buttons())
	SimClock.day_started.connect(func(d): _add_notification("Day %d begins." % d, &"info"))
	interaction.placement_mode_changed.connect(_on_placement_mode_changed)
	_refresh_resources()
	_refresh_speed_buttons()
	_on_selection_changed(null)


# --------------------------------------------------------------------------
# Theme
# --------------------------------------------------------------------------

func _box(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT, pad: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb


func _build_theme() -> void:
	_theme.default_font_size = 15
	_theme.set_stylebox("panel", "PanelContainer", _box(C_PANEL, 12, C_PANEL_BORDER, 12))
	_theme.set_color("font_color", "Label", C_TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var col := C_BTN
		match state:
			"hover": col = C_BTN_HOVER
			"pressed", "hover_pressed": col = C_BTN_PRESSED
			"disabled": col = Color(0.15, 0.16, 0.15, 0.8)
			"focus": col = Color(0, 0, 0, 0)
		var sb := _box(col, 7, Color(1, 1, 1, 0.06) if state != "focus" else Color.TRANSPARENT, 7)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		_theme.set_stylebox(state, "Button", sb)
	_theme.set_color("font_color", "Button", C_TEXT)
	_theme.set_color("font_hover_color", "Button", Color.WHITE)
	_theme.set_color("font_pressed_color", "Button", Color.WHITE)
	_theme.set_color("font_disabled_color", "Button", C_MUTED)
	_theme.set_color("font_color", "CheckBox", C_TEXT)
	_theme.set_color("font_hover_color", "CheckBox", Color.WHITE)
	_theme.set_color("font_pressed_color", "CheckBox", C_TEXT)
	_theme.set_stylebox("normal", "CheckBox", _box(Color(0, 0, 0, 0), 6, Color.TRANSPARENT, 4))
	_theme.set_stylebox("hover", "CheckBox", _box(Color(1, 1, 1, 0.05), 6, Color.TRANSPARENT, 4))
	_theme.set_stylebox("pressed", "CheckBox", _box(Color(0, 0, 0, 0), 6, Color.TRANSPARENT, 4))
	_theme.set_stylebox("hover_pressed", "CheckBox", _box(Color(1, 1, 1, 0.05), 6, Color.TRANSPARENT, 4))
	_theme.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	_theme.set_stylebox("background", "ProgressBar", _box(Color(1, 1, 1, 0.08), 4, Color.TRANSPARENT, 0))


func _label(text: String, size: int = 15, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, callback: Callable, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b


func _swatch(color: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(12, 12)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", _box(color, 6, Color.TRANSPARENT, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _anchor(c: Control, preset: int, margin: float) -> void:
	_root.add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(margin))
	match preset:
		Control.PRESET_TOP_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_LEFT:
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_BOTTOM:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN


# --------------------------------------------------------------------------
# Top bar: tribe resources
# --------------------------------------------------------------------------

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)
	var title := _label(ctx.tribe.tribe_name, 17, C_ACCENT)
	row.add_child(title)
	_add_stat(row, &"population", "Population", Color(0.95, 0.85, 0.65))
	_add_stat(row, &"food", "Food", ResourceType.color(ResourceType.FOOD))
	_add_stat(row, &"wood", "Wood", ResourceType.color(ResourceType.WOOD))
	_add_stat(row, &"stone", "Stone", ResourceType.color(ResourceType.STONE))
	_add_stat(row, &"tools", "Tools", ResourceType.color(ResourceType.TOOLS))
	_add_stat(row, &"housing", "Beds", Color(0.85, 0.71, 0.40))
	_anchor(panel, Control.PRESET_TOP_LEFT, 12)


func _add_stat(row: HBoxContainer, key: StringName, caption: String, color: Color) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_swatch(color))
	box.add_child(_label(caption, 13, C_MUTED))
	var value := _label("0", 17)
	value.custom_minimum_size.x = 30
	box.add_child(value)
	_value_labels[key] = value
	row.add_child(box)


func _refresh_resources() -> void:
	if ctx == null or ctx.tribe == null or _value_labels.is_empty():
		return
	var s := ctx.tribe.stockpile
	_value_labels[&"population"].text = str(ctx.tribe.population())
	_value_labels[&"food"].text = str(s.get_amount(ResourceType.FOOD))
	_value_labels[&"wood"].text = str(s.get_amount(ResourceType.WOOD))
	_value_labels[&"stone"].text = str(s.get_amount(ResourceType.STONE))
	_value_labels[&"tools"].text = str(s.get_amount(ResourceType.TOOLS))
	_value_labels[&"housing"].text = "%d/%d" % [ctx.tribe.housing_capacity(), ctx.tribe.population()]


# --------------------------------------------------------------------------
# Time & speed
# --------------------------------------------------------------------------

func _build_time_panel() -> void:
	var panel := PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 10)
	_clock_label = _label("Day 1  07:00", 17)
	_phase_label = _label("Morning", 14, C_ACCENT)
	time_row.add_child(_clock_label)
	time_row.add_child(_phase_label)
	col.add_child(time_row)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	_pause_button = _button("Pause", func(): SimClock.toggle_pause(), "Pause / resume (Space)")
	_pause_button.custom_minimum_size.x = 78
	speed_row.add_child(_pause_button)
	for i in SimClock.SPEED_STEPS.size():
		var spd: float = SimClock.SPEED_STEPS[i]
		var b := _button("%dx" % int(spd), func(): _set_speed(spd), "Simulation speed %dx (%d)" % [int(spd), i + 1])
		b.toggle_mode = true
		_speed_buttons.append(b)
		speed_row.add_child(b)
	col.add_child(speed_row)
	col.add_child(_button("Return to camp", _focus_home, "Center the camera on the settlement (H)"))
	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 4)
	_chronicle_button = _button("Chronicle", func(): panels.toggle_chronicle(); _refresh_view_buttons(), "Tribe history (C)")
	_tribe_button = _button("Tribe", func(): panels.toggle_tribe(); _refresh_view_buttons(), "Government, culture, groups (T)")
	_inspect_button = _button("Inspect", func(): panels.toggle_inspect(); _refresh_view_buttons(), "Detailed villager inspector (I)")
	_culture_button = _button("Culture", func(): panels.toggle_culture(); _refresh_view_buttons(), "Values, customs, memory, language and art (K)")
	for b in [_chronicle_button, _tribe_button, _culture_button, _inspect_button]:
		b.toggle_mode = true
		view_row.add_child(b)
	col.add_child(view_row)
	_anchor(panel, Control.PRESET_TOP_RIGHT, 12)


func _refresh_view_buttons() -> void:
	_chronicle_button.set_pressed_no_signal(panels.is_chronicle_open())
	_tribe_button.set_pressed_no_signal(panels.is_tribe_open())
	_inspect_button.set_pressed_no_signal(panels.inspect_mode)
	_culture_button.set_pressed_no_signal(panels.is_culture_open())


func _set_speed(value: float) -> void:
	SimClock.set_time_scale(value)
	SimClock.set_paused(false)


func _focus_home() -> void:
	rts_camera.focus_on(ctx.tribe.center)


func _refresh_speed_buttons() -> void:
	if _pause_button == null:
		return
	_pause_button.text = "Resume" if SimClock.paused else "Pause"
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(not SimClock.paused and is_equal_approx(SimClock.time_scale, SimClock.SPEED_STEPS[i]))


func _phase_name() -> String:
	var h := SimClock.get_time_of_day() * 24.0
	if h < 5.0 or h >= 21.0:
		return "Night"
	if h < 8.0:
		return "Dawn"
	if h < 12.0:
		return "Morning"
	if h < 17.0:
		return "Afternoon"
	return "Evening"


# --------------------------------------------------------------------------
# Notifications
# --------------------------------------------------------------------------

func _build_notifications() -> void:
	_notify_box = VBoxContainer.new()
	_notify_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notify_box.add_theme_constant_override("separation", 4)
	_root.add_child(_notify_box)
	_notify_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_notify_box.position = Vector2(14, 70)


func _add_notification(text: String, kind: StringName) -> void:
	if _notify_box == null:
		return
	var color := C_TEXT
	match kind:
		&"warning": color = Color(1.0, 0.75, 0.4)
		&"death": color = Color(1.0, 0.5, 0.45)
		&"build": color = Color(0.7, 0.95, 0.6)
		&"social": color = Color(0.85, 0.72, 1.0)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.06, 0.7), 8, Color.TRANSPARENT, 6))
	panel.add_child(_label(text, 14, color))
	panel.set_meta("age", 0.0)
	_notify_box.add_child(panel)
	while _notify_box.get_child_count() > MAX_NOTIFICATIONS:
		var old := _notify_box.get_child(0)
		_notify_box.remove_child(old)
		old.queue_free()


func _update_notifications(delta: float) -> void:
	for child in _notify_box.get_children():
		var age: float = child.get_meta("age", 0.0) + delta
		child.set_meta("age", age)
		child.modulate.a = clampf((NOTIFY_SECONDS - age) / 1.0, 0.0, 1.0)
		if age >= NOTIFY_SECONDS:
			child.queue_free()


# --------------------------------------------------------------------------
# Selection panel
# --------------------------------------------------------------------------

func _build_selection_panel() -> void:
	_sel_panel = PanelContainer.new()
	_sel_panel.custom_minimum_size = Vector2(330, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_sel_panel.add_child(col)
	_sel_title = _label("", 19, C_ACCENT)
	_sel_subtitle = _label("", 13, C_MUTED)
	col.add_child(_sel_title)
	col.add_child(_sel_subtitle)
	for key in [&"health", &"satiety", &"energy", &"company", &"amount", &"progress"]:
		var row := HBoxContainer.new()
		var cap := _label(String(key).capitalize(), 13, C_MUTED)
		cap.custom_minimum_size.x = 70
		row.add_child(cap)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(220, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 100.0
		var fill_color := Color(0.45, 0.8, 0.45)
		match key:
			&"satiety": fill_color = Color(0.92, 0.6, 0.35)
			&"energy": fill_color = Color(0.45, 0.7, 0.95)
			&"company": fill_color = Color(0.75, 0.55, 0.9)
			&"amount": fill_color = Color(0.85, 0.75, 0.45)
			&"progress": fill_color = Color(0.9, 0.72, 0.36)
		bar.add_theme_stylebox_override("fill", _box(fill_color, 4, Color.TRANSPARENT, 0))
		row.add_child(bar)
		col.add_child(row)
		_sel_bars[key] = {"row": row, "bar": bar}
	_sel_info = _label("", 14)
	_sel_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_info.custom_minimum_size.x = 300
	col.add_child(_sel_info)
	_sel_social = _label("", 13, Color(0.86, 0.82, 0.95))
	_sel_social.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_social.custom_minimum_size.x = 300
	col.add_child(_sel_social)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_sel_follow = _button("Follow", _toggle_follow, "Camera follows this villager (F)")
	_sel_cancel = _button("Cancel construction", _cancel_selected_site, "Remove the site and refund delivered materials")
	buttons.add_child(_sel_follow)
	buttons.add_child(_sel_cancel)
	buttons.add_child(_button("Close", func(): interaction.select(null)))
	col.add_child(buttons)
	_anchor(_sel_panel, Control.PRESET_BOTTOM_LEFT, 12)


func _on_selection_changed(target: Node) -> void:
	_selected = target as Node3D
	_sel_panel.visible = _selected != null
	if _selected == null and rts_camera and rts_camera.is_following():
		rts_camera.follow(null)
	_refresh_selection()


func _set_bar(key: StringName, visible_bar: bool, value: float = 0.0) -> void:
	var entry: Dictionary = _sel_bars[key]
	entry["row"].visible = visible_bar
	entry["bar"].value = value


func _refresh_selection() -> void:
	if _selected == null:
		return
	if not is_instance_valid(_selected):
		interaction.select(null)
		return
	for k in _sel_bars:
		_set_bar(k, false)
	_sel_follow.visible = false
	_sel_cancel.visible = false
	_sel_social.visible = false
	if _selected is Villager:
		var v := _selected as Villager
		_sel_title.text = v.villager_name
		_sel_subtitle.text = "%s, %d years (%s)%s%s" % ["Woman" if v.sex == &"female" else "Man", int(v.age_years), v.life_stage(),
				"  ·  " + String(v.profession) if v.profession != &"" else "", "  ·  expecting a child" if v.pregnancy_days >= 0.0 else ""]
		_set_bar(&"health", true, v.needs.health)
		_set_bar(&"satiety", true, 100.0 - v.needs.hunger)
		_set_bar(&"energy", true, v.needs.energy)
		_set_bar(&"company", true, 100.0 - v.needs.social)
		var home := "Campfire"
		if v.home != null and is_instance_valid(v.home):
			home = "Own hut" if v.home.owner_ids.has(v.villager_id) else "Hut"
		_sel_social.text = _social_summary(v)
		_sel_social.visible = true
		_sel_info.text = "State: %s\nActivity: %s\nCarrying: %s (capacity %d)\nSleeps at: %s" % [
			VillagerState.label(v.state), v.get_task_description(), v.inventory.describe(), v.inventory.capacity, home]
		_sel_follow.visible = true
		_sel_follow.text = "Unfollow" if rts_camera.is_following() else "Follow"
	elif _selected is ResourceNode:
		var r := _selected as ResourceNode
		_sel_title.text = r.display_label
		_sel_subtitle.text = "Source of %s%s" % [ResourceType.display_name(r.resource_type).to_lower(), "  ·  renewable" if r.regrows else ""]
		_set_bar(&"amount", true, 100.0 * r.amount / maxf(1.0, r.max_amount))
		var workers := "%d / %d gatherers" % [r.reservations, r.max_reservations]
		_sel_info.text = "%s\n%s" % [r.describe(), workers]
	elif _selected is Building:
		var b := _selected as Building
		_sel_title.text = b.def.display_name + ("" if b.is_complete else " (site)")
		_sel_subtitle.text = b.def.description
		if not b.is_complete:
			_set_bar(&"progress", true, 100.0 * (b.material_progress() * 0.5 + b.work_progress() * 0.5))
			_sel_cancel.visible = true
		var extra := ""
		if b.def.is_storage:
			var s := ctx.tribe.stockpile
			extra = "\nFood %d  ·  Wood %d  ·  Stone %d" % [s.get_amount(ResourceType.FOOD), s.get_amount(ResourceType.WOOD), s.get_amount(ResourceType.STONE)]
		elif not b.is_complete:
			extra = "\nBuilders working: %d / %d" % [b.builders, b.def.max_builders]
		if not b.owner_ids.is_empty():
			extra += "\nHome of: %s" % _names(b.owner_ids)
		_sel_info.text = b.describe_status() + extra


func _names(ids: Array) -> String:
	var out: PackedStringArray = []
	for id in ids:
		out.append(ctx.social.name_of(id))
	return ", ".join(out) if not out.is_empty() else "none"


func _social_summary(v: Villager) -> String:
	var social := ctx.social
	var id := v.villager_id
	var lines: PackedStringArray = []
	lines.append("Personality: " + "  ·  ".join(v.personality.descriptors()))
	var feelings: PackedStringArray = []
	for pair in v.emotions.dominant(3):
		feelings.append(String(pair[0]))
	lines.append("Mood: %s%s" % [SocialSystem.mood_label(v.emotions.mood()), ("  (" + ", ".join(feelings) + ")") if not feelings.is_empty() else ""])
	var partner := social.partner_of(id)
	var family := social.kin_of(id)
	var rel := "Partner: %s" % (social.name_of(partner) if partner >= 0 else "none")
	if not family.is_empty():
		rel += "   Family: %s" % _names(family)
	lines.append(rel)
	lines.append("Friends: %s   Rivals: %s" % [_names(social.friends_of(id)), _names(social.rivals_of(id))])
	lines.append("Knows %d places" % v.knowledge.store.size())
	var notable := v.memory.notable(3)
	if not notable.is_empty():
		lines.append("Remembers:")
		for r in notable:
			lines.append("  • " + MemoryPolicy.describe(r, social.name_of))
	return "\n".join(lines)


func _toggle_follow() -> void:
	if rts_camera.is_following():
		rts_camera.follow(null)
	elif _selected is Villager:
		rts_camera.follow(_selected)
	_refresh_selection()


func _cancel_selected_site() -> void:
	if _selected is Building:
		ctx.tribe.cancel_construction(_selected as Building)


# --------------------------------------------------------------------------
# Construction panel
# --------------------------------------------------------------------------

func _build_construction_panel() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(_label("Construction", 17, C_ACCENT))
	for def in BuildingCatalog.buildable():
		var b := _button("%s   (%s)" % [def.display_name, def.cost_string()], func(): _start_placing(def),
				def.description + "\nShortcut: B")
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_build_buttons[def.id] = b
		col.add_child(b)
	_build_hint = _label("Left click: place  ·  Shift: place more  ·  Right click / Esc: cancel", 12, C_MUTED)
	_build_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_hint.custom_minimum_size.x = 250
	_build_hint.visible = false
	col.add_child(_build_hint)
	_auto_build_check = CheckBox.new()
	_auto_build_check.text = "Tribe builds huts on its own"
	_auto_build_check.focus_mode = Control.FOCUS_NONE
	_auto_build_check.button_pressed = ctx.tribe.auto_build
	_auto_build_check.toggled.connect(func(on: bool): ctx.tribe.auto_build = on)
	col.add_child(_auto_build_check)
	_anchor(panel, Control.PRESET_BOTTOM_RIGHT, 12)


func _start_placing(def: BuildingDef) -> void:
	if interaction.is_placing() and interaction.placing_def == def:
		interaction.cancel_placement()
	else:
		interaction.begin_placement(def)


func _on_placement_mode_changed(active: bool, def: BuildingDef) -> void:
	_build_hint.visible = active
	for id in _build_buttons:
		_build_buttons[id].set_pressed_no_signal(active and def != null and def.id == id)


func _build_help_hint() -> void:
	var l := _label("WASD move  ·  Wheel zoom  ·  Middle mouse / Q E rotate  ·  Left click select  ·  Space pause  ·  1-4 speed  ·  H camp  ·  I inspect  ·  C chronicle  ·  T tribe  ·  K culture", 12, Color(1, 1, 1, 0.55))
	_anchor(l, Control.PRESET_CENTER_BOTTOM, 10)


func _build_debug_overlay() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label = _label("", 13, C_MUTED)
	panel.add_child(_debug_label)
	panel.visible = false
	_anchor(panel, Control.PRESET_CENTER_TOP, 12)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _update_debug_overlay() -> void:
	var panel := _debug_label.get_parent() as Control
	if not panel.visible:
		return
	var t := ctx.tribe
	_debug_label.text = "FPS %d   ·   sim tick %.2f ms (avg %.2f, max %.2f)   ·   villagers %d   ·   speed %.0fx" % [
		Engine.get_frames_per_second(), t.perf_last_tick_ms, t.perf_avg_tick_ms, t.perf_max_tick_ms,
		t.population(), SimClock.time_scale]


# --------------------------------------------------------------------------
# Frame update & shortcuts
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock_label.text = "Day %d   %s" % [SimClock.get_day(), SimClock.get_clock_string()]
	_phase_label.text = _phase_name() + ("  (paused)" if SimClock.paused else "")
	_update_notifications(delta)
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.2
		_refresh_selection()
		_update_debug_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"toggle_pause"):
		SimClock.toggle_pause()
	elif event.is_action_pressed(&"speed_1"):
		_set_speed(SimClock.SPEED_STEPS[0])
	elif event.is_action_pressed(&"speed_2"):
		_set_speed(SimClock.SPEED_STEPS[1])
	elif event.is_action_pressed(&"speed_3"):
		_set_speed(SimClock.SPEED_STEPS[2])
	elif event.is_action_pressed(&"speed_4"):
		_set_speed(SimClock.SPEED_STEPS[3])
	elif event.is_action_pressed(&"focus_home"):
		_focus_home()
	elif event.is_action_pressed(&"build_hut"):
		_start_placing(BuildingCatalog.get_def(&"hut"))
	elif event.is_action_pressed(&"quick_save"):
		var main := get_parent() as Main
		if main:
			main.save_game()
	elif event.is_action_pressed(&"quick_load"):
		var main := get_parent() as Main
		if main:
			main.load_game()
	elif event.is_action_pressed(&"toggle_inspect"):
		panels.toggle_inspect()
		_refresh_view_buttons()
	elif event.is_action_pressed(&"toggle_chronicle"):
		panels.toggle_chronicle()
		_refresh_view_buttons()
	elif event.is_action_pressed(&"toggle_tribe"):
		panels.toggle_tribe()
		_refresh_view_buttons()
	elif event.is_action_pressed(&"toggle_culture"):
		panels.toggle_culture()
		_refresh_view_buttons()
	elif event.is_action_pressed(&"toggle_debug"):
		var panel := _debug_label.get_parent() as Control
		panel.visible = not panel.visible
	elif event.is_action_pressed(&"follow_selected"):
		if _selected is Villager:
			_toggle_follow()
