class_name ResourceNode
extends StaticBody3D
## A harvestable resource in the world (tree, rock or berry bush).
##
## Depletes when harvested; trees and bushes regrow over time. Reservations
## stop several villagers from walking to the same single-worker node.

signal depleted(node: ResourceNode)
signal harvested(node: ResourceNode)

const COLLISION_LAYER := 4  # bit 3 -> "resources"

enum Kind { TREE, ROCK, BUSH }

var kind: int = Kind.TREE
## Stable id from WorldContext.allocate_entity_id().
var entity_id: int = 0
var resource_type: int = ResourceType.WOOD
var amount: int = 0
var max_amount: int = 0
var obstacle_radius: float = 0.5
## Distance from the node center at which a villager can work on it.
var interact_radius: float = 1.3
var max_reservations: int = 1
var reservations: int = 0
var regrows: bool = false
var regrow_interval: float = 0.0
## Navigation region from which the node is reachable (refreshed by the registry).
var region_id: int = -1
var variant: int = 0
var display_label: String = ""

var _regrow_timer: float = 0.0
var _visual: MeshInstance3D
var _extra_visual: MeshInstance3D
var _base_scale: float = 1.0
var _shake_tween: Tween
var _visual_stage := -1


func setup_tree(total: int, regrow_time: float, variant_index: int, pine: bool, scale_value: float) -> void:
	kind = Kind.TREE
	resource_type = ResourceType.WOOD
	max_amount = total
	amount = total
	regrows = true
	regrow_interval = regrow_time
	obstacle_radius = 0.45
	interact_radius = 1.6
	max_reservations = 1
	variant = variant_index
	display_label = "Pine Tree" if pine else "Oak Tree"
	_base_scale = scale_value
	_visual = _add_mesh(MeshFactory.pine_tree(variant_index) if pine else MeshFactory.round_tree(variant_index))
	_add_collision(CylinderShape3D.new(), 0.45, 3.0)


func setup_rock(total: int, variant_index: int, scale_value: float) -> void:
	kind = Kind.ROCK
	resource_type = ResourceType.STONE
	max_amount = total
	amount = total
	regrows = false
	obstacle_radius = 0.9 * scale_value
	interact_radius = 1.0 * scale_value + 1.2
	max_reservations = 2
	variant = variant_index
	display_label = "Stone Deposit"
	_base_scale = scale_value
	_visual = _add_mesh(MeshFactory.rock(variant_index))
	_add_collision(CylinderShape3D.new(), 1.0, 1.2)


func setup_bush(total: int, regrow_time: float, variant_index: int, scale_value: float) -> void:
	kind = Kind.BUSH
	resource_type = ResourceType.FOOD
	max_amount = total
	amount = total
	regrows = true
	regrow_interval = regrow_time
	obstacle_radius = 0.4
	interact_radius = 1.4
	max_reservations = 1
	variant = variant_index
	display_label = "Berry Bush"
	_base_scale = scale_value
	_visual = _add_mesh(MeshFactory.bush(variant_index))
	_extra_visual = _add_mesh(MeshFactory.berries(variant_index))
	_add_collision(CylinderShape3D.new(), 0.8, 1.1)


func _ready() -> void:
	collision_layer = COLLISION_LAYER
	collision_mask = 0
	scale = Vector3.ONE * _base_scale
	_update_visual()


func _add_mesh(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	return mi


func _add_collision(shape: CylinderShape3D, radius: float, h: float) -> void:
	shape.radius = radius
	shape.height = h
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = h * 0.5
	add_child(cs)


# --------------------------------------------------------------------------
# Gameplay API
# --------------------------------------------------------------------------

func is_harvestable() -> bool:
	return amount > 0 and is_inside_tree()


func is_available() -> bool:
	return is_harvestable() and reservations < max_reservations


## Claims a work slot. Does not require stock: a villager acting on old
## knowledge may claim and walk to a node that turns out to be empty.
func reserve() -> bool:
	if reservations >= max_reservations or not is_inside_tree():
		return false
	reservations += 1
	return true


func release() -> void:
	reservations = maxi(0, reservations - 1)


## Removes up to `requested` units. Returns the amount actually taken.
func harvest(requested: int) -> int:
	var taken := mini(requested, amount)
	if taken <= 0:
		return 0
	amount -= taken
	_shake()
	_update_visual()
	harvested.emit(self)
	if amount == 0:
		_regrow_timer = 0.0
		depleted.emit(self)
	return taken


## Called by the registry on simulation ticks for regrowing nodes.
func sim_tick(dt: float) -> void:
	if not regrows or amount >= max_amount:
		return
	_regrow_timer += dt
	match kind:
		Kind.TREE:
			# Trees regrow as a whole after the stump has had time to sprout.
			if amount == 0 and _regrow_timer >= regrow_interval:
				amount = max_amount
				_regrow_timer = 0.0
				_update_visual()
			elif amount == 0:
				# Only touch the visual when the sapling's growth stage changes.
				var stage := int(get_regrow_progress() * 10.0)
				if stage != _visual_stage:
					_visual_stage = stage
					_update_visual()
		_:
			if _regrow_timer >= regrow_interval:
				_regrow_timer = 0.0
				amount = mini(max_amount, amount + 1)
				_update_visual()


func needs_regrowth() -> bool:
	return regrows and amount < max_amount


func get_regrow_progress() -> float:
	if regrow_interval <= 0.0:
		return 0.0
	return clampf(_regrow_timer / regrow_interval, 0.0, 1.0)


func describe() -> String:
	if amount <= 0:
		if kind == Kind.TREE:
			return "Felled - regrowing (%d%%)" % int(get_regrow_progress() * 100.0)
		return "Depleted"
	return "%d / %d %s" % [amount, max_amount, ResourceType.display_name(resource_type).to_lower()]


# --------------------------------------------------------------------------
# Visuals
# --------------------------------------------------------------------------

func _update_visual() -> void:
	if _visual == null:
		return
	match kind:
		Kind.TREE:
			if amount > 0:
				_visual.mesh = MeshFactory.pine_tree(variant) if display_label == "Pine Tree" else MeshFactory.round_tree(variant)
				_visual.scale = Vector3.ONE
			else:
				# A sapling grows out of the stump while the tree regrows.
				var p := get_regrow_progress()
				if p < 0.35:
					_visual.mesh = MeshFactory.stump()
					_visual.scale = Vector3.ONE
				else:
					_visual.mesh = MeshFactory.pine_tree(variant) if display_label == "Pine Tree" else MeshFactory.round_tree(variant)
					_visual.scale = Vector3.ONE * lerpf(0.2, 0.8, (p - 0.35) / 0.65)
		Kind.ROCK:
			var f := float(amount) / maxf(1.0, max_amount)
			_visual.scale = Vector3.ONE * lerpf(0.45, 1.0, f)
			visible = amount > 0
		Kind.BUSH:
			if _extra_visual:
				var f := float(amount) / maxf(1.0, max_amount)
				_extra_visual.visible = amount > 0
				_extra_visual.scale = Vector3.ONE * lerpf(0.6, 1.0, f)


func _shake() -> void:
	if _visual == null or not is_inside_tree():
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_visual.rotation = Vector3.ZERO
	_shake_tween = create_tween()
	_shake_tween.tween_property(_visual, "rotation:z", 0.06, 0.06)
	_shake_tween.tween_property(_visual, "rotation:z", -0.04, 0.08)
	_shake_tween.tween_property(_visual, "rotation:z", 0.0, 0.08)
