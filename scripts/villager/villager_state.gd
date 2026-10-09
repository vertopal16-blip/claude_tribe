class_name VillagerState
extends RefCounted
## High level activity states shown to the player and used by animation.

enum { IDLE, SEARCHING_FOOD, EATING, MOVING_TO_RESOURCE, GATHERING, RETURNING, DELIVERING, RESTING, BUILDING, DEAD,
	SOCIALIZING, EXPLORING }


static func label(state: int) -> String:
	match state:
		IDLE: return "Idle"
		SEARCHING_FOOD: return "Searching for food"
		EATING: return "Eating"
		MOVING_TO_RESOURCE: return "Moving to resource"
		GATHERING: return "Gathering"
		RETURNING: return "Returning to settlement"
		DELIVERING: return "Delivering"
		RESTING: return "Resting"
		BUILDING: return "Building"
		DEAD: return "Dead"
		SOCIALIZING: return "Socializing"
		EXPLORING: return "Exploring"
	return "Unknown"
