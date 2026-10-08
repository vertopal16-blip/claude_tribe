class_name VillagerInventory
extends RefCounted
## What a villager is carrying: a single resource type at a time, up to capacity.

signal changed

var carried_type: int = ResourceType.NONE
var amount: int = 0
var capacity: int = 8


func _init(cap: int) -> void:
	capacity = maxi(1, cap)


func is_empty() -> bool:
	return amount <= 0


func is_full() -> bool:
	return amount >= capacity


func free_space_for(type: int) -> int:
	if amount > 0 and carried_type != type:
		return 0
	return capacity - amount


## Adds up to n units; returns how many fit.
func add(type: int, n: int) -> int:
	var fit := mini(n, free_space_for(type))
	if fit <= 0:
		return 0
	carried_type = type
	amount += fit
	changed.emit()
	return fit


func remove(n: int) -> int:
	var taken := mini(n, amount)
	amount -= taken
	if amount <= 0:
		amount = 0
		carried_type = ResourceType.NONE
	changed.emit()
	return taken


func take_all() -> Dictionary:
	var out := {"type": carried_type, "amount": amount}
	amount = 0
	carried_type = ResourceType.NONE
	changed.emit()
	return out


func describe() -> String:
	if is_empty():
		return "Nothing"
	return "%d %s" % [amount, ResourceType.display_name(carried_type).to_lower()]
