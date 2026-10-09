class_name MemoryPolicy
extends RefCounted
## What experiences mean. For every kind of memory:
##   [salience, valence, affinity delta, trust delta, text]
## plus the emotions it triggers and how it slowly shapes personality.
## Deterministic data: the single place to rebalance social behaviour.
## Text placeholders: {other}, {subject}, {detail}.

const KINDS := {
	# Everyday contact
	&"chatted": [0.12, 0.15, 0.05, 0.01, "Talked with {other}"],
	&"awkward_talk": [0.15, -0.1, -0.03, 0.0, "Had an awkward talk with {other}"],
	&"ignored": [0.25, -0.2, -0.06, 0.0, "{other} ignored me"],
	&"learned_location": [0.12, 0.1, 0.04, 0.03, "{other} told me where to find {detail}"],
	&"taught_location": [0.08, 0.05, 0.02, 0.0, "Told {other} where to find {detail}"],
	&"doubted": [0.15, -0.05, -0.02, -0.02, "Didn't believe {other} about {detail}"],
	&"misled": [0.4, -0.35, -0.12, -0.15, "{other}'s directions led me to nothing"],
	&"heard_gossip": [0.2, 0.0, 0.0, 0.0, "{other} told me about {subject}"],
	&"heard_rumor": [0.3, -0.1, 0.0, 0.0, "{other} said {subject} {detail}"],
	&"worked_together": [0.15, 0.2, 0.04, 0.03, "Worked alongside {other}"],
	# Help and crises
	&"was_helped": [0.8, 0.8, 0.3, 0.2, "{other} gave me food when I was starving"],
	&"helped": [0.5, 0.5, 0.12, 0.03, "Shared food with {other}"],
	&"was_refused": [0.6, -0.6, -0.25, -0.15, "{other} refused to help me when I was starving"],
	&"refused": [0.3, -0.15, -0.03, 0.0, "Refused to help {other}"],
	&"starved": [0.55, -0.6, 0.0, 0.0, "Went hungry with no food in sight"],
	&"traded": [0.25, 0.2, 0.05, 0.05, "Traded {detail} with {other}"],
	&"promise_kept": [0.5, 0.45, 0.15, 0.2, "{other} kept their promise to {detail}"],
	&"promise_broken": [0.6, -0.5, -0.2, -0.3, "{other} broke their promise to {detail}"],
	# Conflict
	&"was_insulted": [0.55, -0.7, -0.3, -0.12, "{other} insulted me"],
	&"insulted": [0.3, -0.1, -0.08, 0.0, "Insulted {other}"],
	&"argued": [0.45, -0.45, -0.18, -0.06, "Argued with {other} about {detail}"],
	&"humiliated": [0.75, -0.75, -0.35, -0.15, "{other} humiliated me in front of others"],
	&"fought": [0.8, -0.75, -0.4, -0.25, "Came to blows with {other}"],
	&"saw_fight": [0.35, -0.3, 0.0, 0.0, "Saw {other} and {subject} fight"],
	&"accused": [0.55, -0.5, -0.25, -0.15, "{other} accused me of {detail}"],
	&"accused_someone": [0.35, -0.1, -0.12, -0.08, "Accused {other} of {detail}"],
	&"complained": [0.25, -0.15, -0.04, 0.0, "Complained to {other} about {detail}"],
	&"reconciled": [0.55, 0.5, 0.3, 0.12, "Made peace with {other}"],
	&"mediated": [0.45, 0.35, 0.12, 0.12, "{other} settled my dispute with {subject}"],
	&"rival_honored": [0.4, -0.3, -0.1, 0.0, "{other} was honoured over me"],
	# Comfort
	&"was_comforted": [0.55, 0.6, 0.22, 0.1, "{other} comforted me"],
	&"comforted": [0.35, 0.35, 0.1, 0.02, "Comforted {other}"],
	# Romance and family
	&"flirted": [0.45, 0.5, 0.15, 0.04, "Spent a lovely moment with {other}"],
	&"rejected": [0.45, -0.4, -0.08, 0.0, "{other} turned me down"],
	&"courting": [0.6, 0.6, 0.12, 0.08, "Started courting {other}"],
	&"became_partners": [0.95, 0.9, 0.1, 0.1, "Became partners with {other}"],
	&"proposal_refused": [0.6, -0.5, -0.1, 0.0, "{other} refused to be my partner"],
	&"broke_up": [0.9, -0.8, -0.3, -0.25, "Broke up with {other}"],
	&"partner_unfaithful": [0.9, -0.85, -0.5, -0.5, "Caught {other} courting {subject}"],
	&"jealous_of": [0.5, -0.4, -0.25, -0.05, "{other} was flirting with my partner"],
	&"moved_in_with": [0.6, 0.6, 0.05, 0.05, "Moved in with {other}"],
	&"child_born": [1.0, 0.95, 0.0, 0.0, "My child {subject} was born"],
	&"sibling_born": [0.4, 0.4, 0.0, 0.0, "My sibling {subject} was born"],
	&"grew_up": [0.6, 0.5, 0.0, 0.0, "Grew up and became {detail}"],
	# Work, learning, discovery
	&"built_together": [0.3, 0.3, 0.08, 0.04, "Built a {detail} with {other}"],
	&"built": [0.3, 0.35, 0.0, 0.0, "Helped build a {detail}"],
	&"moved_in": [0.55, 0.55, 0.0, 0.0, "Moved into a new home"],
	&"taught": [0.3, 0.3, 0.05, 0.02, "Taught {other} {detail}"],
	&"was_taught": [0.4, 0.4, 0.15, 0.08, "{other} taught me {detail}"],
	&"skill_mastered": [0.65, 0.6, 0.0, 0.0, "Mastered {detail}"],
	&"new_profession": [0.6, 0.5, 0.0, 0.0, "Became a {detail}"],
	&"discovered": [0.85, 0.75, 0.0, 0.0, "Discovered {detail}"],
	&"learned_discovery": [0.35, 0.3, 0.06, 0.05, "{other} explained {detail} to me"],
	&"got_tool": [0.25, 0.3, 0.06, 0.02, "Got a new tool from {other}"],
	# Community and politics
	&"proposed_project": [0.45, 0.3, 0.0, 0.0, "Proposed building a {detail}"],
	&"project_completed": [0.75, 0.7, 0.0, 0.0, "The {detail} I championed was built"],
	&"project_failed": [0.7, -0.6, 0.0, 0.0, "My plan for a {detail} failed"],
	&"persuaded": [0.25, 0.1, 0.05, 0.03, "{other} convinced me about the {detail}"],
	&"disagreed": [0.25, -0.15, -0.05, -0.02, "Disagreed with {other} about the {detail}"],
	&"became_leader": [0.95, 0.85, 0.0, 0.0, "Became {detail}"],
	&"lost_leadership": [0.9, -0.75, 0.0, 0.0, "Lost my position as {detail}"],
	&"endorsed": [0.3, 0.2, 0.08, 0.04, "Backed {other} as leader"],
	&"vetoed": [0.5, -0.4, -0.15, -0.1, "{other} blocked my plan for a {detail}"],
	&"joined_group": [0.4, 0.35, 0.0, 0.0, "Became part of {detail}"],
	&"ceremony": [0.4, 0.4, 0.0, 0.0, "Took part in {detail}"],
	&"feast": [0.4, 0.6, 0.0, 0.0, "Celebrated {detail}"],
	# Loss
	&"lost_partner": [1.0, -1.0, 0.0, 0.0, "Lost {subject}, my partner"],
	&"lost_child": [1.0, -1.0, 0.0, 0.0, "Lost my child {subject}"],
	&"lost_family": [0.95, -0.9, 0.0, 0.0, "Lost {subject}, my family"],
	&"lost_friend": [0.8, -0.75, 0.0, 0.0, "Lost my friend {subject}"],
	&"saw_death": [0.5, -0.45, 0.0, 0.0, "Saw {subject} die"],
	&"became_friends": [0.6, 0.6, 0.0, 0.0, "Became friends with {other}"],
	&"became_rivals": [0.6, -0.5, 0.0, 0.0, "Became rivals with {other}"],
	&"became_enemies": [0.8, -0.7, 0.0, 0.0, "Became enemies with {other}"],
}

## kind -> [[emotion, amount], ...] felt by the one who remembers it.
const EMOTIONS := {
	&"chatted": [[&"happiness", 0.08]],
	&"awkward_talk": [[&"frustration", 0.1]],
	&"ignored": [[&"sadness", 0.15], [&"shame", 0.08]],
	&"misled": [[&"anger", 0.25], [&"resentment", 0.2]],
	&"heard_rumor": [[&"curiosity", 0.15]],
	&"worked_together": [[&"satisfaction", 0.08]],
	&"was_helped": [[&"gratitude", 0.7], [&"happiness", 0.3], [&"trust", 0.3], [&"fear", -0.3]],
	&"helped": [[&"satisfaction", 0.3], [&"pride", 0.15]],
	&"was_refused": [[&"resentment", 0.4], [&"sadness", 0.3], [&"anger", 0.2]],
	&"refused": [[&"shame", 0.1]],
	&"starved": [[&"fear", 0.45], [&"stress", 0.5], [&"frustration", 0.3]],
	&"traded": [[&"satisfaction", 0.15]],
	&"promise_kept": [[&"trust", 0.3], [&"gratitude", 0.3]],
	&"promise_broken": [[&"resentment", 0.35], [&"anger", 0.25], [&"trust", -0.3]],
	&"was_insulted": [[&"anger", 0.5], [&"shame", 0.25], [&"resentment", 0.3]],
	&"insulted": [[&"anger", 0.1]],
	&"argued": [[&"anger", 0.35], [&"stress", 0.15]],
	&"humiliated": [[&"shame", 0.6], [&"resentment", 0.5], [&"anger", 0.3]],
	&"fought": [[&"anger", 0.5], [&"fear", 0.3], [&"stress", 0.4]],
	&"saw_fight": [[&"fear", 0.25], [&"stress", 0.1]],
	&"accused": [[&"anger", 0.4], [&"shame", 0.3], [&"resentment", 0.3]],
	&"accused_someone": [[&"anger", 0.15]],
	&"complained": [[&"frustration", -0.15]],
	&"reconciled": [[&"anger", -0.4], [&"resentment", -0.4], [&"happiness", 0.2], [&"trust", 0.2]],
	&"mediated": [[&"anger", -0.3], [&"resentment", -0.25], [&"gratitude", 0.3]],
	&"rival_honored": [[&"jealousy", 0.5], [&"frustration", 0.2]],
	&"was_comforted": [[&"gratitude", 0.3], [&"grief", -0.2], [&"sadness", -0.25], [&"loneliness", -0.2]],
	&"comforted": [[&"affection", 0.15]],
	&"flirted": [[&"affection", 0.4], [&"happiness", 0.3], [&"hope", 0.2]],
	&"rejected": [[&"shame", 0.35], [&"sadness", 0.3]],
	&"courting": [[&"affection", 0.5], [&"hope", 0.4], [&"happiness", 0.3]],
	&"became_partners": [[&"affection", 0.8], [&"happiness", 0.6], [&"hope", 0.5]],
	&"proposal_refused": [[&"sadness", 0.45], [&"shame", 0.3]],
	&"broke_up": [[&"sadness", 0.6], [&"anger", 0.3], [&"affection", -0.6]],
	&"partner_unfaithful": [[&"jealousy", 0.8], [&"anger", 0.6], [&"sadness", 0.5], [&"trust", -0.5]],
	&"jealous_of": [[&"jealousy", 0.6], [&"anger", 0.3]],
	&"moved_in_with": [[&"happiness", 0.4], [&"affection", 0.3]],
	&"child_born": [[&"happiness", 0.8], [&"hope", 0.6], [&"pride", 0.4], [&"affection", 0.5]],
	&"sibling_born": [[&"happiness", 0.3], [&"curiosity", 0.3]],
	&"grew_up": [[&"pride", 0.4], [&"hope", 0.4]],
	&"built_together": [[&"satisfaction", 0.2]],
	&"built": [[&"pride", 0.25], [&"satisfaction", 0.3]],
	&"moved_in": [[&"happiness", 0.5], [&"satisfaction", 0.4]],
	&"taught": [[&"pride", 0.2], [&"satisfaction", 0.2]],
	&"was_taught": [[&"gratitude", 0.25], [&"hope", 0.15]],
	&"skill_mastered": [[&"pride", 0.5], [&"satisfaction", 0.5]],
	&"new_profession": [[&"pride", 0.35], [&"hope", 0.3]],
	&"discovered": [[&"pride", 0.6], [&"curiosity", 0.5], [&"happiness", 0.4]],
	&"learned_discovery": [[&"curiosity", 0.4], [&"hope", 0.2]],
	&"got_tool": [[&"gratitude", 0.2], [&"satisfaction", 0.2]],
	&"proposed_project": [[&"hope", 0.35]],
	&"project_completed": [[&"pride", 0.7], [&"satisfaction", 0.6]],
	&"project_failed": [[&"shame", 0.45], [&"frustration", 0.5]],
	&"persuaded": [[&"trust", 0.1]],
	&"disagreed": [[&"frustration", 0.15]],
	&"became_leader": [[&"pride", 0.8], [&"hope", 0.5], [&"stress", 0.2]],
	&"lost_leadership": [[&"shame", 0.6], [&"resentment", 0.5], [&"sadness", 0.3]],
	&"endorsed": [[&"hope", 0.15]],
	&"vetoed": [[&"frustration", 0.45], [&"resentment", 0.3]],
	&"joined_group": [[&"happiness", 0.25], [&"loneliness", -0.2]],
	&"ceremony": [[&"grief", -0.25], [&"sadness", -0.2], [&"hope", 0.2], [&"loneliness", -0.2]],
	&"feast": [[&"happiness", 0.5], [&"satisfaction", 0.3], [&"stress", -0.3]],
	&"lost_partner": [[&"grief", 0.95], [&"sadness", 0.7], [&"loneliness", 0.4]],
	&"lost_child": [[&"grief", 1.0], [&"sadness", 0.8]],
	&"lost_family": [[&"grief", 0.85], [&"sadness", 0.6]],
	&"lost_friend": [[&"grief", 0.6], [&"sadness", 0.5]],
	&"saw_death": [[&"fear", 0.35], [&"sadness", 0.3]],
	&"became_friends": [[&"happiness", 0.4], [&"affection", 0.3]],
	&"became_rivals": [[&"anger", 0.3], [&"resentment", 0.3]],
	&"became_enemies": [[&"anger", 0.5], [&"resentment", 0.5], [&"stress", 0.2]],
}

## kind -> [[trait, delta], ...] applied to the villager who remembers it.
const TRAIT_DRIFT := {
	&"was_helped": [[&"trust", 0.02], [&"generosity", 0.01]],
	&"was_refused": [[&"trust", -0.02]],
	&"was_insulted": [[&"trust", -0.015], [&"aggressiveness", 0.01]],
	&"humiliated": [[&"status_desire", 0.02], [&"trust", -0.02]],
	&"misled": [[&"trust", -0.02]],
	&"was_comforted": [[&"empathy", 0.01]],
	&"comforted": [[&"empathy", 0.005]],
	&"built_together": [[&"sociability", 0.004]],
	&"starved": [[&"generosity", -0.01], [&"risk_tolerance", 0.01]],
	&"lost_partner": [[&"sociability", -0.03]],
	&"helped": [[&"generosity", 0.005]],
	&"fought": [[&"aggressiveness", 0.01], [&"patience", -0.01]],
	&"partner_unfaithful": [[&"trust", -0.04], [&"jealousy", 0.03]],
	&"discovered": [[&"curiosity", 0.02], [&"creativity", 0.02]],
	&"project_completed": [[&"ambition", 0.015]],
	&"project_failed": [[&"risk_tolerance", -0.02]],
	&"became_leader": [[&"status_desire", 0.02]],
	&"reconciled": [[&"patience", 0.01]],
	&"child_born": [[&"empathy", 0.01]],
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


## Human readable line. `name_of` maps a villager id to a name. Faded
## memories lose who was involved ("someone").
static func describe(r: MemoryRecord, name_of: Callable) -> String:
	var text: String = KINDS[r.kind][4] if KINDS.has(r.kind) else String(r.kind)
	var vague := r.salience < 0.12 and r.count < 3
	text = text.replace("{other}", name_of.call(r.other_id) if r.other_id >= 0 and not vague else "someone")
	text = text.replace("{subject}", name_of.call(r.subject_id) if r.subject_id >= 0 and not vague else "someone")
	text = text.replace("{detail}", r.detail if r.detail != "" else "something")
	if r.count > 1:
		text += " (x%d)" % r.count
	return text
