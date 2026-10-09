class_name RelationshipOverlay
extends MeshInstance3D
## In inspect mode, draws lines from the selected villager to the people who
## matter to them: partner (pink), family (green), friends (blue), rivals and
## enemies (red), crush (violet). Presentation only.

const COLORS := {&"partner": Color(1.0, 0.45, 0.75), &"kin": Color(0.45, 0.95, 0.5), &"friend": Color(0.45, 0.7, 1.0),
	&"rival": Color(1.0, 0.35, 0.25), &"crush": Color(0.75, 0.5, 1.0)}

var ctx: WorldContext
var interaction: WorldInteraction
var panels: SocietyPanels
var _mesh := ImmediateMesh.new()


func setup(context: WorldContext, world_interaction: WorldInteraction, p: SocietyPanels) -> void:
	ctx = context
	interaction = world_interaction
	panels = p


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	material_override = mat


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if ctx == null or panels == null or not panels.inspect_mode or not (interaction.selected is Villager):
		return
	var v := interaction.selected as Villager
	if not is_instance_valid(v):
		return
	var social := ctx.social
	var lines := []
	for o in ctx.tribe.villagers:
		if o == v:
			continue
		var kind: StringName = &""
		var g := social.graph
		if social.partner_of(v.villager_id) == o.villager_id:
			kind = &"partner"
		elif g.is_kin(v.villager_id, o.villager_id):
			kind = &"kin"
		elif g.has_tag(v.villager_id, o.villager_id, &"rival") or g.has_tag(v.villager_id, o.villager_id, &"enemy"):
			kind = &"rival"
		elif g.has_tag(v.villager_id, o.villager_id, &"friend"):
			kind = &"friend"
		elif social.romance.is_interested(v, o):
			kind = &"crush"
		if kind != &"":
			lines.append([o.get_visual_position(), COLORS[kind]])
	if lines.is_empty():
		return
	var from := v.get_visual_position() + Vector3(0, 1.6, 0)
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in lines:
		_mesh.surface_set_color(l[1])
		_mesh.surface_add_vertex(from)
		_mesh.surface_set_color(l[1])
		_mesh.surface_add_vertex(l[0] + Vector3(0, 1.6, 0))
	_mesh.surface_end()
