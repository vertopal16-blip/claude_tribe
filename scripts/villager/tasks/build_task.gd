class_name BuildTask
extends VillagerTask
## Construction: haul missing materials from the stockpile to the site, then
## work on the site once all materials are there.

enum Step { TO_STOCKPILE, TO_SITE_WITH_MATERIAL, TO_SITE_TO_WORK, WORKING }

var site: Building
var step: int = Step.TO_SITE_TO_WORK
var material_type: int = ResourceType.NONE
## Units reserved on the site for this trip (in hand or about to be picked up).
var _reserved_amount := 0
var _is_builder := false


func start() -> bool:
	var job := ctx.tribe.find_build_job(villager)
	if job.is_empty():
		return false
	site = job["site"]
	material_type = job["material"]
	if material_type == ResourceType.NONE:
		return _go_work()
	var stock := ctx.tribe.stockpile.get_amount(material_type)
	var amount := mini(mini(villager.inventory.capacity, site.unassigned_need(material_type)), stock)
	if amount <= 0 or not villager.inventory.is_empty():
		return false
	_reserved_amount = amount
	site.reserve_delivery(material_type, amount)
	step = Step.TO_STOCKPILE
	villager.set_state(VillagerState.RETURNING)
	return _go_to_stockpile()


func _go_work() -> bool:
	if site.builders >= site.def.max_builders:
		return false
	site.builders += 1
	_is_builder = true
	step = Step.TO_SITE_TO_WORK
	villager.set_state(VillagerState.RETURNING)
	if _near_building(site):
		_start_working()
		return true
	return _move_to_site()


func _move_to_site() -> bool:
	return villager.movement.move_to(site.global_position, int(ceil(site.def.footprint_radius)) + 3)


func _start_working() -> void:
	step = Step.WORKING
	villager.movement.stop()
	villager.set_state(VillagerState.BUILDING)
	villager.face_towards(site.global_position)


func tick(dt: float) -> int:
	if not is_instance_valid(site) or site.is_queued_for_deletion():
		site = null
		return _fail("Construction site removed")
	match step:
		Step.TO_STOCKPILE:
			match villager.movement.status:
				VillagerMovement.ARRIVED:
					var taken := ctx.tribe.stockpile.take(material_type, _reserved_amount)
					if taken < _reserved_amount:
						site.cancel_delivery(material_type, _reserved_amount - taken)
						_reserved_amount = taken
					if taken <= 0:
						return _fail("Stockpile ran out of %s" % ResourceType.display_name(material_type).to_lower())
					villager.inventory.add(material_type, taken)
					step = Step.TO_SITE_WITH_MATERIAL
					villager.set_state(VillagerState.DELIVERING)
					if not _move_to_site():
						return _fail("Can't reach the construction site")
				VillagerMovement.FAILED:
					return _fail("Can't reach the stockpile")
		Step.TO_SITE_WITH_MATERIAL:
			villager.activity = 0.9
			match villager.movement.status:
				VillagerMovement.ARRIVED:
					var carried := villager.inventory.amount
					var used := site.complete_delivery(material_type, carried)
					villager.inventory.remove(used)
					_reserved_amount = 0
					villager.record_event(&"delivered_materials", {"building_id": site.entity_id,
							"building_type": site.def.id, "resource_type": material_type, "amount": used})
					if site.materials_complete() and site.builders < site.def.max_builders:
						site.builders += 1
						_is_builder = true
						_start_working()
					else:
						return Status.SUCCEEDED
				VillagerMovement.FAILED:
					return _fail("Can't reach the construction site")
		Step.TO_SITE_TO_WORK:
			match villager.movement.status:
				VillagerMovement.ARRIVED:
					_start_working()
				VillagerMovement.FAILED:
					return _fail("Can't reach the construction site")
		Step.WORKING:
			villager.activity = 1.0
			if site.is_complete:
				return Status.SUCCEEDED
			if site.add_work(ctx.config.build_rate * villager.needs.performance() * dt):
				villager.record_event(&"completed_building", {"building_id": site.entity_id, "building_type": site.def.id})
				return Status.SUCCEEDED
	return Status.RUNNING


func _on_finish() -> void:
	if site != null and is_instance_valid(site):
		if _reserved_amount > 0:
			site.cancel_delivery(material_type, _reserved_amount)
		if _is_builder:
			site.builders = maxi(0, site.builders - 1)
	_reserved_amount = 0
	_is_builder = false
	villager.movement.stop()


func describe() -> String:
	var name := site.def.display_name.to_lower() if site != null and is_instance_valid(site) else "building"
	match step:
		Step.TO_STOCKPILE: return "Fetching %s for a %s" % [ResourceType.display_name(material_type).to_lower(), name]
		Step.TO_SITE_WITH_MATERIAL: return "Hauling %s to a %s site" % [ResourceType.display_name(material_type).to_lower(), name]
		Step.TO_SITE_TO_WORK: return "Heading to build a %s" % name
		Step.WORKING: return "Building a %s" % name
	return super()
