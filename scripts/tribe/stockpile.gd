class_name Stockpile
extends RefCounted
## Shared tribal storage. The only way resources enter it is add(), called when
## a villager physically delivers what they carried.

signal changed(amounts: Dictionary)

var _amounts: Dictionary = ResourceType.empty_amounts()
## Lifetime totals, useful for statistics and tests.
var total_delivered: Dictionary = ResourceType.empty_amounts()
var total_consumed: Dictionary = ResourceType.empty_amounts()


func get_amount(type: int) -> int:
	return int(_amounts.get(type, 0))


func amounts() -> Dictionary:
	return _amounts.duplicate()


func add(type: int, n: int) -> void:
	if n <= 0 or not _amounts.has(type):
		return
	_amounts[type] += n
	total_delivered[type] += n
	changed.emit(amounts())


## Takes up to `n` units; returns how many were actually taken.
func take(type: int, n: int) -> int:
	if n <= 0 or not _amounts.has(type):
		return 0
	var taken := mini(n, _amounts[type])
	if taken > 0:
		_amounts[type] -= taken
		total_consumed[type] += taken
		changed.emit(amounts())
	return taken


## Initial supplies the tribe arrives with (not "from nowhere": set once at world creation).
func set_initial(type: int, n: int) -> void:
	_amounts[type] = maxi(0, n)
	changed.emit(amounts())
