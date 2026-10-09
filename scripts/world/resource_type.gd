class_name ResourceType
extends RefCounted
## Identifiers and display data for tribal resources.

const NONE := -1
const FOOD := 0
const WOOD := 1
const STONE := 2
## Crafted at a workshop; never found in the wild.
const TOOLS := 3
## Resources found in the world (gathered).
const ALL: Array[int] = [FOOD, WOOD, STONE]
## Everything the stockpile can hold.
const STORED: Array[int] = [FOOD, WOOD, STONE, TOOLS]


static func display_name(type: int) -> String:
	match type:
		FOOD: return "Food"
		WOOD: return "Wood"
		STONE: return "Stone"
		TOOLS: return "Tools"
	return "Nothing"


static func color(type: int) -> Color:
	match type:
		FOOD: return Color(0.90, 0.36, 0.38)
		WOOD: return Color(0.78, 0.56, 0.33)
		STONE: return Color(0.70, 0.73, 0.78)
		TOOLS: return Color(0.85, 0.8, 0.55)
	return Color.WHITE


static func empty_amounts() -> Dictionary:
	return {FOOD: 0, WOOD: 0, STONE: 0, TOOLS: 0}
