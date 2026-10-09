class_name SaveSystem
extends RefCounted
## Saving and loading a running tribe.
##
## The terrain and the original resource layout are regenerated exactly from
## the world seed; the save stores everything that changed since: resource
## amounts, buildings and construction progress, every villager (body, needs,
## family, skills, emotions, memories, knowledge, relationships) and all
## tribe-level systems (romance, promises, demographics, discoveries, projects,
## government, groups, culture, economy, chronicle). Running tasks are not
## saved - villagers simply decide again after loading.

## Binary Variant encoding: exact floats and types (text encoding rounds floats).
const PATH := "user://tribal_save.dat"
const VERSION := 1


static func save_game(main: Main, path: String = PATH) -> bool:
	var data := capture(main)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save file %s" % path)
		return false
	f.store_var(data)
	f.close()
	return true


static func read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var()
	f.close()
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		push_error("Save file is missing or from an incompatible version.")
		return {}
	return data


static func capture(main: Main) -> Dictionary:
	var ctx := main.ctx
	var tribe := main.tribe
	var resources := {}
	for n in ctx.resources.all_nodes():
		resources[str(n.entity_id)] = [n.amount, n._regrow_timer]
	var buildings := []
	for b in tribe.buildings:
		buildings.append({"def": String(b.def.id), "pos": [b.global_position.x, b.global_position.z], "id": b.entity_id,
			"complete": b.is_complete, "delivered": b.delivered.duplicate(), "work": b.work_done, "owners": b.owner_ids.duplicate(),
			"contributors": b.contributor_ids.duplicate(), "project": b.project_id, "crop": b.crop_growth, "harvests": b.harvests,
			"player": b.placed_by_player, "style": b.style_era, "honours": int(b.get_meta("honours", -1))})
	var villagers := []
	for v in tribe.villagers:
		villagers.append({"id": v.villager_id, "name": v.villager_name, "sex": String(v.sex), "age": v.age_years,
			"pos": [v.global_position.x, v.global_position.z], "health": v.needs.health, "hunger": v.needs.hunger,
			"energy": v.needs.energy, "carry": [v.inventory.carried_type, v.inventory.amount], "parents": v.parent_ids.duplicate(),
			"home": v.home.entity_id if v.home != null and is_instance_valid(v.home) else -1, "born": v.born_day,
			"prestige": v.prestige, "profession": String(v.profession), "pregnancy": [v.pregnancy_days, v.pregnancy_partner, v.last_birth_day],
			"tool": v.tool_durability, "skills": v.skills.to_dict(), "emotions": v.emotions.to_dict(),
			"last_work": String(v.brain.last_work_goal)})
	return {
		"version": VERSION, "world_seed": main.world_seed, "social_seed": main.config.social_seed,
		"sim_time": SimClock.sim_time, "tick": SimClock.tick_count, "next_entity": ctx._next_entity_id,
		"next_villager": tribe._next_villager_id, "stock": tribe.stockpile.amounts(),
		"stock_totals": [tribe.stockpile.total_delivered.duplicate(), tribe.stockpile.total_consumed.duplicate()],
		"tribe": {"auto_build": tribe.auto_build, "deaths": tribe.deaths, "name": tribe.tribe_name},
		"resources": resources, "buildings": buildings, "villagers": villagers,
		"social": ctx.social.to_dict(), "society": ctx.society.to_dict(),
	}


## Applies a save onto a freshly generated world with the same seed. Called by
## Main after terrain, settlement and resources exist but before villagers.
static func restore(main: Main, data: Dictionary) -> void:
	var ctx := main.ctx
	var tribe := main.tribe
	# Resources: amounts and regrowth; nodes missing from the save were used up.
	var saved_res: Dictionary = data["resources"]
	for n in ctx.resources.all_nodes():
		var row = saved_res.get(str(n.entity_id))
		if row == null:
			ctx.resources.unregister(n)
			ctx.nav.remove_obstacle(n.global_position, n.obstacle_radius)
			n.queue_free()
			continue
		n.amount = int(row[0])
		n._regrow_timer = float(row[1])
		n._update_visual()
		ctx.resources.notify_harvested(n)
	# Buildings: replace the default camp with the saved settlement.
	for b in tribe.buildings.duplicate():
		tribe._remove_building(b)
	var by_id := {}
	for bd in data["buildings"]:
		var def := BuildingCatalog.get_def(StringName(bd["def"]))
		var b := tribe._spawn_building(def, Vector3(bd["pos"][0], 0, bd["pos"][1]), bool(bd["complete"]), int(bd["id"]))
		for k in bd["delivered"]:
			b.delivered[int(k)] = int(bd["delivered"][k])
		b.work_done = float(bd["work"])
		b.owner_ids.assign(bd["owners"])
		b.contributor_ids.assign(bd["contributors"])
		b.project_id = int(bd["project"])
		b.crop_growth = float(bd["crop"])
		b.harvests = int(bd["harvests"])
		b.placed_by_player = bool(bd["player"])
		b.style_era = int(bd.get("style", -1))
		if int(bd.get("honours", -1)) >= 0:
			b.set_meta("honours", int(bd["honours"]))
		b._refresh_visuals()
		by_id[b.entity_id] = b
		if def.is_campfire:
			tribe.campfire = b
		elif def.is_storage:
			tribe.storage = b
	# Stockpile
	for k in data["stock"]:
		tribe.stockpile.set_initial(int(k), int(data["stock"][k]))
	tribe.stockpile.total_delivered = Dictionary(data["stock_totals"][0]).duplicate()
	tribe.stockpile.total_consumed = Dictionary(data["stock_totals"][1]).duplicate()
	tribe.auto_build = bool(data["tribe"]["auto_build"])
	tribe.deaths = int(data["tribe"]["deaths"])
	tribe.tribe_name = data["tribe"].get("name", tribe.tribe_name)
	# Villagers
	for vd in data["villagers"]:
		var parents: Array[int] = []
		parents.assign(vd["parents"])
		var v := tribe.add_villager(Vector3(vd["pos"][0], 0, vd["pos"][1]), float(vd["age"]), StringName(vd["sex"]), null,
				VillagerSkills.from_dict(vd["skills"]), parents, vd["name"], int(vd["id"]))
		v.needs.health = float(vd["health"])
		v.needs.hunger = float(vd["hunger"])
		v.needs.energy = float(vd["energy"])
		if int(vd["carry"][1]) > 0:
			v.inventory.add(int(vd["carry"][0]), int(vd["carry"][1]))
		v.home = by_id.get(int(vd["home"]))
		if v.home != null and v.home.is_complete and not v.is_child():
			v.home.claim_bed(v)
		v.born_day = int(vd["born"])
		v.prestige = float(vd["prestige"])
		v.profession = StringName(vd["profession"])
		v.pregnancy_days = float(vd["pregnancy"][0])
		v.pregnancy_partner = int(vd["pregnancy"][1])
		v.last_birth_day = int(vd["pregnancy"][2])
		v.tool_durability = float(vd["tool"])
		v.emotions = Emotions.from_dict(vd["emotions"])
		v.brain.last_work_goal = StringName(vd["last_work"])
		v.update_age_visual()
	ctx.social.load_dict(data["social"])
	ctx.society.load_dict(data["society"])
	for v in tribe.villagers:
		v.needs.social_rate_mult = lerpf(0.4, 1.8, v.personality.get_trait(&"social_need"))
	tribe._next_villager_id = int(data["next_villager"])
	ctx._next_entity_id = int(data["next_entity"])
	SimClock.sim_time = float(data["sim_time"])
	SimClock.tick_count = int(data["tick"])
	tribe._emit_population()
	EventBus.stockpile_changed.emit(tribe.stockpile.amounts())
