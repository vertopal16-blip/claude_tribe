class_name MemoryPolicy
extends RefCounted
## Rules for what experiences mean: how important (salience), how pleasant
## (valence), how they change the opinion of the other villager involved
## (affinity / trust) and how they shape personality over time.
## Deterministic data: the single place to rebalance social behaviour.

## kind -> [salience, valence, affinity delta, trust delta, text]
## Text placeholders: {other}, {subject}, {detail}.
const KINDS := {
	&"chatted": [0.12, 0.15, 0.05, 0.01, "Talked with {other}"],
	&"awkward_talk": [0.15, -0.1, -0.03, 0.0, "Had an awkward talk with {other}"],
	&"learned_location": [0.12, 0.1, 0.04, 0.03, "{other} told me where to find {detail}"],
	&"taught_location": [0.08, 0.05, 0.02, 0.0, "Told {other} where to find {detail}"],
	&"doubted": [0.15, -0.05, -0.02, -0.02, "Didn't believe {other} about {detail}"],
	&"misled": [0.4, -0.35, -0.12, -0.15, "{other}'s directions led me to nothing"],
	&"was_helped": [0.8, 0.8, 0.3, 0.2, "{other} gave me food when I was starving"],
	&"helped": [0.5, 0.5, 0.12, 0.03, "Shared food with {other}"],
	&"was_refused": [0.6, -0.6, -0.25, -0.15, "{other} refused to help me when I was starving"],
	&"refused": [0.3, -0.15, -0.03, 0.0, "Refused to help {other}"],
	&"was_insulted": [0.55, -0.7, -0.3, -0.12, "{other} insulted me"],
	&"insulted": [0.3, -0.1, -0.08, 0.0, "Insulted {other}"],
	&"argued": [0.45, -0.45, -0.18, -0.06, "Argued with {other}"],
	&"was_comforted": [0.55, 0.6, 0.22, 0.1, "{other} comforted me"],
	&"comforted": [0.35, 0.35, 0.1, 0.02, "Comforted {other}"],
	&"heard_gossip": [0.2, 0.0, 0.0, 0.0, "{other} told me about {subject}"],
	&"flirted": [0.45, 0.5, 0.15, 0.04, "Spent a lovely moment with {other}"],
	&"rejected": [0.45, -0.4, -0.08, 0.0, "{other} turned me down"],
	&"built_together": [0.3, 0.3, 0.08, 0.04, "Built a {detail} with {other}"],
	&"built": [0.3, 0.35, 0.0, 0.0, "Helped build a {detail}"],
	&"moved_in": [0.55, 0.55, 0.0, 0.0, "Moved into a new hut"],
	&"starved": [0.55, -0.6, 0.0, 0.0, "Went hungry with no food in sight"],
	&"lost_partner": [1.0, -1.0, 0.0, 0.0, "Lost {subject}, my partner"],
	&"lost_family": [0.95, -0.9, 0.0, 0.0, "Lost {subject}, my family"],
	&"lost_friend": [0.8, -0.75, 0.0, 0.0, "Lost my friend {subject}"],
	&"saw_death": [0.5, -0.45, 0.0, 0.0, "Saw {subject} die"],
	&"became_friends": [0.6, 0.6, 0.0, 0.0, "Became friends with {other}"],
	&"became_rivals": [0.6, -0.5, 0.0, 0.0, "Became rivals with {other}"],
	&"became_partners": [0.95, 0.9, 0.0, 0.0, "Became partners with {other}"],
}

## kind -> [[trait, delta], ...] applied to the villager who remembers it.
const TRAIT_DRIFT := {
	&"was_helped": [[&"trust", 0.02], [&"generosity", 0.01]],
	&"was_refused": [[&"trust", -0.02]],
	&"was_insulted": [[&"trust", -0.015], [&"aggressiveness", 0.01]],
	&"misled": [[&"trust", -0.02]],
	&"was_comforted": [[&"empathy", 0.01]],
	&"comforted": [[&"empathy", 0.005]],
	&"built_together": [[&"sociability", 0.004]],
	&"starved": [[&"generosity", -0.01]],
	&"lost_partner": [[&"sociability", -0.03]],
	&"helped": [[&"generosity", 0.005]],
}

## Below this salience an experience is only kept briefly (never long-term).
const LONG_TERM_THRESHOLD := 0.4


static func has_kind(kind: StringName) -> bool:
	return KINDS.has(kind)


static func salience(kind: StringName) -> float:
	return KINDS[kind][0]


static func valence(kind: StringName) -> float:
	return KINDS[kind][1]


static func affinity_delta(kind: StringName) -> float:
	return KINDS[kind][2]


static func trust_delta(kind: StringName) -> float:
	return KINDS[kind][3]


## Human readable line. `name_of` maps a villager id to a name.
static func describe(r: MemoryRecord, name_of: Callable) -> String:
	var text: String = KINDS[r.kind][4] if KINDS.has(r.kind) else String(r.kind)
	text = text.replace("{other}", name_of.call(r.other_id) if r.other_id >= 0 else "someone")
	text = text.replace("{subject}", name_of.call(r.subject_id) if r.subject_id >= 0 else "someone")
	text = text.replace("{detail}", r.detail if r.detail != "" else "something")
	if r.count > 1:
		text += " (x%d)" % r.count
	return text
