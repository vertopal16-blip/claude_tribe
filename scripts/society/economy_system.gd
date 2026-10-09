class_name EconomySystem
extends RefCounted
## Tools and how they are shared.
##
## Tools are made at a workshop from real wood and stone and wear out with
## use. While the tribe's culture is cooperative they go to the shared
## stockpile and anyone may take one. Once cooperation weakens, toolmakers
## keep what they make: they give tools to family and friends, and others must
## trade carried goods for one - so access to tools (and with it, the speed of
## a person's work) becomes unequal.

const TOOL_LIFE := 400.0  # work-seconds
const TRADE_PRICE := 4
const COMMUNAL_THRESHOLD := 0.45

var society: SocietySystem
var tools_made := 0
var trades := 0
var gifts := 0
## Toolmaker id -> tools they hold back for themselves (private mode).
var private_tools: Dictionary = {}


func _init(s: SocietySystem) -> void:
	society = s


func is_communal() -> bool:
	return society.culture.norm(&"cooperation") >= COMMUNAL_THRESHOLD


func mode_label() -> String:
	return "Communal (tools in the shared store)" if is_communal() else "Private (toolmakers keep their tools)"


func tool_made(maker: Villager) -> void:
	tools_made += 1
	if tools_made == 1:
		society.history.add(&"economy", "%s made the tribe's first tool." % maker.villager_name, [maker.villager_id])
	if is_communal():
		society.ctx.tribe.stockpile.add(ResourceType.TOOLS, 1)
	else:
		private_tools[maker.villager_id] = int(private_tools.get(maker.villager_id, 0)) + 1


## Before tool work: pick up a tool if one is available to this villager.
func equip(v: Villager) -> void:
	if v.tool_durability > 0.0 or not v.is_adult():
		return
	if society.ctx.tribe.stockpile.take(ResourceType.TOOLS, 1) > 0:
		v.tool_durability = TOOL_LIFE
		return
	# Private mode: toolmakers equip themselves from their own stock.
	if int(private_tools.get(v.villager_id, 0)) > 0:
		private_tools[v.villager_id] -= 1
		v.tool_durability = TOOL_LIFE


## A toolmaker with spare tools who might part with one for `v`.
func supplier_for(v: Villager) -> Villager:
	for id in private_tools:
		if int(private_tools[id]) > 0 and id != v.villager_id:
			var maker := society.ctx.social.get_villager(id)
			if maker != null:
				return maker
	return null


## Will `maker` simply give `v` a tool (family, friends, kind souls)?
func would_gift(maker: Villager, v: Villager) -> bool:
	var social := society.ctx.social
	return social.closeness(maker.villager_id, v.villager_id) + maker.personality.get_trait(&"generosity") * 0.4 > 0.75


func give_tool(maker: Villager, v: Villager, paid: bool) -> bool:
	if int(private_tools.get(maker.villager_id, 0)) <= 0:
		return false
	private_tools[maker.villager_id] -= 1
	v.tool_durability = TOOL_LIFE
	if paid:
		trades += 1
	else:
		gifts += 1
	return true


## Inequality: share of working adults without a tool.
func tool_access() -> float:
	var adults := 0
	var equipped := 0
	for v in society.ctx.tribe.villagers:
		if v.is_adult():
			adults += 1
			if v.tool_durability > 0.0:
				equipped += 1
	return 0.0 if adults == 0 else float(equipped) / adults


func to_dict() -> Dictionary:
	var pt := {}
	for id in private_tools:
		pt[str(id)] = private_tools[id]
	return {"made": tools_made, "trades": trades, "gifts": gifts, "private": pt}


func load_dict(d: Dictionary) -> void:
	tools_made = int(d["made"])
	trades = int(d["trades"])
	gifts = int(d["gifts"])
	private_tools.clear()
	for id in d["private"]:
		private_tools[int(id)] = int(d["private"][id])
