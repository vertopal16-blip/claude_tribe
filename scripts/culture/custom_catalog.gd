class_name CustomCatalog
extends RefCounted
## The repertoire of practices a tribe *could* turn into customs.
##
## Nothing here exists at the start of a game. A custom is born only when a
## pattern of real behaviour repeats (people gathering at the fire night after
## night, food shared through hard times, deaths, harvests, quarrels...) and
## the people involved share beliefs that give it meaning. Several customs
## compete for the same pattern; which one appears depends on what the
## participants actually value at that moment - so the same famine can give
## one tribe a sharing custom and another strict rationing.
##
## Per kind:
##   pattern   - the repeated behaviour that can give rise to it
##   needs     - how many times the pattern must occur first
##   values    - beliefs it expresses (what makes people embrace or reject it)
##   min_pop   - social complexity needed
##   requires  - "tech:x", "built:a|b", "art:n", "lexicon:n"
##   ceremony  - "" (a daily practice) or the gathering place: "fire", "sacred", "hall"
##   roots     - two concepts its name is compounded from
##   forms     - variants: [description, {values that favour this form}]
##   scope     - "tribe" or "group" (can belong to one family / guild)

const KINDS := {
	&"evening_fire": {
		"pattern": "evening_talk", "needs": 30, "values": {&"cooperation": 1.0, &"hospitality": 0.6, &"family": 0.3},
		"min_pop": 0, "requires": [], "ceremony": "", "roots": [&"fire", &"together"],
		"describe": "Evenings are spent together around the fire",
		"forms": [["with songs", {&"spirituality": 1.0, &"cooperation": 0.5}], ["with games and contests", {&"strength": 1.0, &"courage": 0.6}],
			["with quiet talk", {&"family": 1.0, &"hospitality": 0.5}]],
	},
	&"storytelling": {
		"pattern": "evening_talk", "needs": 30, "values": {&"knowledge": 1.0, &"tradition": 0.7, &"elders": 0.7},
		"min_pop": 8, "requires": ["lore:1"], "ceremony": "", "roots": [&"story", &"night"],
		"describe": "The old stories are told by the fire at night",
		"forms": [["told by the eldest", {&"elders": 1.0}], ["told by anyone who remembers", {&"equality": 1.0, &"knowledge": 0.5}]],
	},
	&"sharing_custom": {
		"pattern": "hardship", "needs": 4, "values": {&"generosity": 1.0, &"cooperation": 0.8},
		"min_pop": 0, "requires": [], "ceremony": "", "roots": [&"food", &"share"],
		"describe": "No one goes hungry while others eat",
		"forms": [["food is offered to anyone in need", {&"generosity": 1.0}], ["the hungry are fed from the common store first", {&"cooperation": 1.0}]],
	},
	&"strict_rationing": {
		"pattern": "hardship", "needs": 4, "values": {&"hierarchy": 0.8, &"independence": 0.6, &"tradition": 0.3},
		"min_pop": 0, "requires": [], "ceremony": "", "roots": [&"hunger", &"guard"],
		"describe": "Every share of food is counted and guarded",
		"forms": [["the leader hands out each share", {&"hierarchy": 1.0}], ["each takes only their own share", {&"independence": 1.0}]],
	},
	&"funeral_rites": {
		"pattern": "death", "needs": 2, "values": {&"spirituality": 1.0, &"tradition": 0.5},
		"min_pop": 0, "requires": [], "ceremony": "sacred", "roots": [&"death", &"rite"],
		"describe": "The dead are honoured together",
		"forms": [["laid beneath a cairn of stones", {&"tradition": 1.0, &"craftsmanship": 0.4}], ["sent off with a great fire", {&"spirituality": 1.0, &"courage": 0.3}],
			["buried with the tools of their trade", {&"craftsmanship": 1.0, &"achievement": 0.6}], ["returned to the earth beneath a young tree", {&"nature": 1.0}]],
	},
	&"ancestor_veneration": {
		"pattern": "death", "needs": 2, "values": {&"elders": 1.0, &"family": 0.8, &"tradition": 0.5},
		"min_pop": 6, "requires": [], "ceremony": "sacred", "roots": [&"ancestor", &"honor"],
		"describe": "The ancestors are remembered and their names carried on",
		"forms": [["their names are recited each year", {&"tradition": 1.0}], ["families keep a token of each ancestor", {&"family": 1.0}]],
	},
	&"harvest_feast": {
		"pattern": "harvest", "needs": 3, "values": {&"cooperation": 0.8, &"generosity": 0.6, &"nature": 0.4},
		"min_pop": 6, "requires": ["tech:agriculture"], "ceremony": "fire", "roots": [&"harvest", &"together"],
		"describe": "Good harvests are celebrated with a feast",
		"forms": [["everyone eats together", {&"cooperation": 1.0}], ["the best workers are honoured", {&"achievement": 1.0}]],
	},
	&"first_fruits": {
		"pattern": "harvest", "needs": 3, "values": {&"spirituality": 1.0, &"nature": 0.8},
		"min_pop": 6, "requires": ["tech:agriculture"], "ceremony": "sacred", "roots": [&"first", &"gift"],
		"describe": "The first of each harvest is given back to the land",
		"forms": [["offered at the sacred place", {&"spirituality": 1.0}], ["buried in the field", {&"nature": 1.0}]],
	},
	&"coming_of_age_trial": {
		"pattern": "coming_of_age", "needs": 2, "values": {&"courage": 1.0, &"strength": 0.7},
		"min_pop": 10, "requires": [], "ceremony": "fire", "roots": [&"brave", &"trial"],
		"describe": "Youths prove their courage before they are counted as adults",
		"forms": [["a journey alone beyond the valley's edge", {&"courage": 1.0}], ["a contest of strength", {&"strength": 1.0}]],
	},
	&"coming_of_age_teaching": {
		"pattern": "coming_of_age", "needs": 2, "values": {&"knowledge": 0.8, &"craftsmanship": 0.8, &"elders": 0.6},
		"min_pop": 10, "requires": [], "ceremony": "fire", "roots": [&"hand", &"teach"],
		"describe": "New adults are taught a craft by a master",
		"forms": [["a master chooses the apprentice", {&"elders": 1.0}], ["the youth chooses their master", {&"independence": 1.0}]],
	},
	&"partnership_feast": {
		"pattern": "partnership", "needs": 2, "values": {&"family": 1.0, &"cooperation": 0.5, &"hospitality": 0.4},
		"min_pop": 8, "requires": [], "ceremony": "fire", "roots": [&"partner", &"together"],
		"describe": "New couples are celebrated by the whole tribe",
		"forms": [["with dancing", {&"cooperation": 1.0}], ["with gifts from both families", {&"family": 1.0}]],
	},
	&"vows": {
		"pattern": "partnership", "needs": 2, "values": {&"loyalty": 1.0, &"spirituality": 0.5, &"tradition": 0.3},
		"min_pop": 8, "requires": [], "ceremony": "sacred", "roots": [&"partner", &"word"],
		"describe": "Partners swear lifelong vows",
		"forms": [["sworn before the elders", {&"elders": 1.0}], ["sworn before the spirits", {&"spirituality": 1.0}]],
	},
	&"before_expedition": {
		"pattern": "expedition", "needs": 25, "values": {&"courage": 0.7, &"spirituality": 0.7, &"nature": 0.5},
		"min_pop": 6, "requires": [], "ceremony": "", "roots": [&"path", &"song"],
		"describe": "Those who go out to fish or scout first ask the land for luck",
		"forms": [["a song for luck", {&"spirituality": 1.0}], ["a pledge of courage", {&"courage": 1.0}]],
	},
	&"leader_remembrance": {
		"pattern": "leader_passing_good", "needs": 1, "values": {&"loyalty": 1.0, &"hierarchy": 0.6, &"tradition": 0.5},
		"min_pop": 8, "requires": [], "ceremony": "fire", "roots": [&"chief", &"memory"],
		"describe": "The tribe remembers a great leader",
		"forms": [["their deeds are retold each year", {&"tradition": 1.0}], ["their successors swear to follow their example", {&"loyalty": 1.0}]],
	},
	&"no_one_above": {
		"pattern": "leader_passing_bad", "needs": 1, "values": {&"equality": 1.0, &"independence": 0.5},
		"min_pop": 8, "requires": [], "ceremony": "", "roots": [&"equal", &"heart"],
		"describe": "No one shall rule over the rest again",
		"forms": [["every voice counts the same", {&"equality": 1.0}], ["each family decides for itself", {&"independence": 1.0}]],
	},
	&"peacekeeping": {
		"pattern": "conflict", "needs": 4, "values": {&"cooperation": 1.0, &"elders": 0.5},
		"min_pop": 6, "requires": [], "ceremony": "", "roots": [&"peace", &"circle"],
		"describe": "Quarrels are brought before the respected to settle",
		"forms": [["the eldest judge", {&"elders": 1.0}], ["everyone sits in a circle until it is settled", {&"equality": 1.0, &"cooperation": 0.5}]],
	},
	&"contest": {
		"pattern": "conflict", "needs": 4, "values": {&"strength": 1.0, &"courage": 0.6},
		"min_pop": 6, "requires": [], "ceremony": "", "roots": [&"strong", &"trial"],
		"describe": "Quarrels are settled by a contest, then forgotten",
		"forms": [["wrestling", {&"strength": 1.0}], ["a test of endurance", {&"courage": 1.0}]],
	},
	&"commemoration": {
		"pattern": "commemoration", "needs": 1, "values": {&"tradition": 1.0},
		"min_pop": 10, "requires": ["ceremonies:1"], "ceremony": "hall", "roots": [&"memory", &"light"],
		"describe": "Each year the tribe remembers",
		"forms": [["with a night of stories", {&"knowledge": 1.0}], ["with a feast", {&"cooperation": 1.0}], ["with silence at the sacred place", {&"spirituality": 1.0}]],
	},
	&"craft_mark": {
		"pattern": "craft_teaching", "needs": 6, "values": {&"craftsmanship": 1.0, &"knowledge": 0.5},
		"min_pop": 10, "requires": [], "ceremony": "", "roots": [&"hand", &"mark"], "scope": "group",
		"describe": "Masters mark their work and train apprentices",
		"forms": [["the master's mark is passed to the best apprentice", {&"achievement": 1.0}], ["the mark belongs to the whole craft", {&"cooperation": 1.0}]],
	},
	&"birth_welcome": {
		"pattern": "birth", "needs": 3, "values": {&"hospitality": 0.8, &"generosity": 0.6, &"family": 0.6},
		"min_pop": 8, "requires": [], "ceremony": "", "roots": [&"child", &"gift"],
		"describe": "Each newborn's family receives gifts of food",
		"forms": [["from every household", {&"cooperation": 1.0}], ["from the newborn's kin", {&"family": 1.0}]],
	},
	&"kin_naming": {
		"pattern": "birth", "needs": 3, "values": {&"family": 1.0, &"tradition": 0.5, &"elders": 0.3},
		"min_pop": 8, "requires": ["lexicon:3"], "ceremony": "", "roots": [&"blood", &"word"],
		"describe": "Children carry part of a parent's name",
		"forms": [["the father's name", {&"hierarchy": 1.0}], ["the mother's name", {&"family": 1.0}]],
	},
	&"hereditary": {
		"pattern": "lineage", "needs": 1, "values": {&"hierarchy": 0.8, &"family": 0.8},
		"min_pop": 10, "requires": [], "ceremony": "", "roots": [&"blood", &"chief"],
		"describe": "Leadership passes from parent to child",
		"forms": [["to the eldest child", {&"tradition": 1.0}], ["to the most able child", {&"achievement": 1.0}]],
	},
	&"elder_council": {
		"pattern": "lineage", "needs": 1, "values": {&"elders": 1.0, &"equality": 0.4, &"tradition": 0.3},
		"min_pop": 10, "requires": [], "ceremony": "", "roots": [&"elder", &"circle"],
		"describe": "The eldest decide together",
		"forms": [["the three eldest", {&"tradition": 1.0}], ["the elders the tribe trusts most", {&"equality": 1.0}]],
	},
	&"tree_thanks": {
		"pattern": "woodcut", "needs": 40, "values": {&"nature": 1.0, &"spirituality": 0.5},
		"min_pop": 6, "requires": [], "ceremony": "", "roots": [&"tree", &"gift"],
		"describe": "A sapling is planted for every tree that is felled",
		"forms": [["with a word of thanks", {&"spirituality": 1.0}], ["by the woodcutter's own hand", {&"craftsmanship": 1.0, &"nature": 0.5}]],
	},
}

## Which kinds can arise from each pattern.
static func candidates(pattern: String) -> Array:
	var out := []
	for k in KINDS:
		if KINDS[k]["pattern"] == pattern:
			out.append(k)
	return out


static func get_kind(k: StringName) -> Dictionary:
	return KINDS.get(k, {})
