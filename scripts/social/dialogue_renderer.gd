class_name DialogueRenderer
extends RefCounted
## Turns a decided conversation outcome into short spoken lines.
## Presentation only: it never decides or changes anything. A generative text
## backend could replace these templates later, fed only with what the two
## villagers actually know.

const LINES := {
	&"small_talk": [
		["Beautiful day, isn't it?", "It is. Good for working."],
		["The fire kept me warm last night.", "Mine too. Feels like home."],
		["How are your hands, {listener}?", "Sore, but fine. Thanks."],
		["Did you hear the birds this morning?", "I did! Lovely."],
	],
	&"small_talk_fail": [
		["...so, the weather.", "Mm. Sure."],
		["Are you listening, {listener}?", "Not really, sorry."],
	],
	&"share_location": [["There's {res} {where}.", "Thanks, I'll remember that."]],
	&"share_location_doubt": [["There's {res} {where}.", "Hmm... I'm not sure I believe you."]],
	&"ask_food": [["{listener}, I'm so hungry... spare some food?", "Here, take some."]],
	&"ask_food_refused": [["{listener}, I'm so hungry... spare some food?", "Sorry. I need it myself."]],
	&"offer_food": [["{listener}! I brought you food.", "Thank you... you saved me."]],
	&"console": [["I'm sorry about {subject}.", "Thank you. It helps to talk."]],
	&"console_fail": [["I'm sorry about {subject}.", "Please... leave me be."]],
	&"gossip_good": [["Have you noticed how kind {subject} is?", "Now that you say it, yes."]],
	&"gossip_bad": [["I don't trust {subject}, you know.", "Really? I'll keep an eye out."]],
	&"insult": [["Out of my way, {listener}!", "...fine."]],
	&"argue": [["You're useless, {listener}!", "How dare you!"]],
	&"flirt": [["Walk with me by the lake later?", "I'd like that very much."]],
	&"flirt_rejected": [["Walk with me by the lake later?", "Maybe... another time."]],
}


static func render(key: StringName, rng: RandomNumberGenerator, values: Dictionary) -> Array:
	var options: Array = LINES.get(key, [["...", "..."]])
	var pair: Array = options[rng.randi() % options.size()]
	var out := []
	for line: String in pair:
		for k in values:
			line = line.replace("{%s}" % k, str(values[k]))
		out.append(line)
	return out


## "north of camp" style direction from the camp to a point.
static func direction_words(camp: Vector3, p: Vector3) -> String:
	var d := p - camp
	var dist := Vector2(d.x, d.z).length()
	var dir := ""
	if absf(d.x) > absf(d.z):
		dir = "east" if d.x > 0.0 else "west"
	else:
		dir = "south" if d.z > 0.0 else "north"
	if dist < 12.0:
		return "right by the camp"
	return ("just %s of the camp" if dist < 28.0 else "far to the %s") % dir
