class_name DialogueRenderer
extends RefCounted
## Turns a decided conversation outcome into spoken lines. Presentation only:
## it never decides or changes anything. Lines are filled with real context
## (names, work, recent tribe events, shortages, projects) so what villagers
## say matches the state of the simulation. A generative text backend could
## replace these templates, fed only with what the two villagers know.

const LINES := {
	&"small_talk": [
		["{time_remark}", "It is. {reply_work}"],
		["How is the {work_noun} going, {listener}?", "{reply_work}"],
		["Did you hear? {event}", "I did. {event_reply}"],
		["{shortage_remark}", "{shortage_reply}"],
		["Your little {child} is growing fast.", "Faster than I'd like!"],
		["Will you come to the {custom} tonight?", "I wouldn't miss it."],
		["Nowhere is as beautiful as {place} in the evening.", "{place} is home."],
		["The fire kept me warm last night.", "Mine too. It feels like home."],
	],
	&"small_talk_fail": [
		["...so. The weather.", "Mm. Sure."],
		["Are you even listening, {listener}?", "Not really, sorry."],
		["You always talk about {work_noun}.", "And you never listen."],
	],
	&"family": [
		["Have you eaten today, {listener}?", "Yes, don't worry about me."],
		["Our family should stick together.", "Always."],
		["{event}", "We'll get through it together."],
	],
	&"parent_advice": [["Watch how I do the {skill}. Like this.", "Oh! I see now."]],
	&"share_location": [["There's {res} {where}.", "Thanks, I'll remember that."]],
	&"share_location_doubt": [["There's {res} {where}.", "Hmm... I'm not sure I believe you."]],
	&"ask_food": [["{listener}, I'm so hungry... spare some food?", "Here, take some."]],
	&"ask_food_refused": [["{listener}, I'm so hungry... spare some food?", "Sorry. I need it myself."]],
	&"offer_food": [["{listener}! I brought you food.", "Thank you... you saved me."]],
	&"console": [["I'm sorry about {subject}.", "Thank you. It helps to talk."], ["{subject} will be missed.", "Every day."]],
	&"cheer_up": [["You look troubled. Walk with me?", "...Thank you. I needed that."]],
	&"console_fail": [["I'm sorry about {subject}.", "Please... leave me be."], ["Cheer up!", "Just leave me alone."]],
	&"rumor_good": [["Have you noticed how kind {subject} is?", "Now that you say it, yes."]],
	&"rumor_bad": [["Don't trust {subject}. I've seen things.", "Really? I'll keep an eye out."],
		["{subject} is not who you think.", "I had a feeling..."]],
	&"rumor_doubted": [["{subject} can't be trusted, you know.", "That's not the {subject} I know."]],
	&"complain_agree": [["{subject} keeps {reason}.", "You're right, it's not fair."]],
	&"complain_defend": [["{subject} keeps {reason}.", "Come on, {subject} isn't that bad."]],
	&"insult": [["Out of my way, {listener}!", "...fine."], ["Is that the best you can do, {listener}?", "..."]],
	&"argue": [["You're useless, {listener}!", "How dare you!"], ["Always in the way, aren't you?", "Look who's talking!"]],
	&"accuse_apology": [["You've been {reason}!", "You're right. I'm sorry."]],
	&"accuse_deny": [["You've been {reason}!", "That's a lie!"], ["I know you've been {reason}.", "Prove it!"]],
	&"fight": [["That's enough, {listener}!", "Then make me!"], ["I've had it with you!", "Come on then!"]],
	&"reconcile": [["I don't want us to fight anymore.", "Neither do I. Friends?"]],
	&"reconcile_no": [["Can we put it behind us?", "Not yet. Not after that."]],
	&"flirt": [["Walk with me by the lake later?", "I'd like that very much."], ["You look lovely in this light, {listener}.", "You're sweet."],
		["I saved you a seat by the fire.", "Then I'd better take it."]],
	&"flirt_rejected": [["Walk with me by the lake later?", "Maybe... another time."], ["You look lovely today.", "Thanks. I have work to do."]],
	&"propose_yes": [["{listener}, will you share a home with me?", "Yes! I hoped you'd ask."]],
	&"propose_no": [["{listener}, will you share a home with me?", "I... I'm sorry. I can't."]],
	&"couple_warm": [["Long day?", "Better now that you're here."], ["I was thinking about you.", "Only good things, I hope."]],
	&"couple_mend": [["About {reason}... I'm sorry.", "Me too. Let's do better."]],
	&"couple_argue": [["We need to talk about {reason}.", "Not this again!"]],
	&"couple_breakup": [["I can't live with {reason} any longer.", "Then go!"]],
	&"teach": [["Here, let me show you some {skill}.", "Oh, that's clever!"], ["Hold it like this for {skill}.", "Like this? I see!"]],
	&"teach_no": [["Want to learn some {skill}?", "Not now, thanks."]],
	&"coordinate": [["Come gather {res} with me?", "Sure, let's go together."]],
	&"coordinate_no": [["Come gather {res} with me?", "I'm busy, sorry."]],
	&"ask_build_help": [["Will you help me build my home?", "I promise I'll lend a hand."]],
	&"ask_build_help_no": [["Will you help me build my home?", "I've got my own troubles."]],
	&"discovery": [["I found a new way of {tech}!", "Show me! That could change everything."]],
	&"discovery_doubt": [["I found a new way of {tech}!", "Sounds like nonsense to me."]],
	&"proposal_support": [["We should build a {project}. {why}", "You're right. I'll back it."]],
	&"proposal_oppose": [["We should build a {project}. {why}", "No. {counter}"]],
	&"proposal_undecided": [["We should build a {project}. {why}", "Maybe. Let me think about it."]],
	&"problem_food": [["Food is getting scarce. What do we do?", "{plan}"]],
	&"endorse": [["We need someone to lead. I think {candidate} should.", "Agreed. {candidate} has my support."]],
	&"endorse_no": [["We need someone to lead. I think {candidate} should.", "{candidate}? Never."]],
	&"mediate": [["{subject} and you must stop this feud.", "...Alright. For the tribe."]],
	&"mediate_no": [["{subject} and you must stop this feud.", "Stay out of it."]],
	&"trade": [["A tool for {price} {res}?", "Deal."]],
	&"trade_no": [["A tool for {price} {res}?", "Not for that price."]],
	&"tradition": [["The {tradition} - it's who we are.", "It is. Our people have always done it."]],
}


static func render(key: StringName, rng: RandomNumberGenerator, values: Dictionary) -> Array:
	var options: Array = LINES.get(key, [["...", "..."]])
	var pair: Array = options[rng.randi() % options.size()]
	# Skip context lines whose slots we can't fill (e.g. no children, no events).
	for attempt in 4:
		var ok := true
		for line: String in pair:
			for slot in ["{child}", "{event}", "{shortage_remark}", "{custom}", "{place}"]:
				if line.contains(slot) and not values.has(slot.trim_prefix("{").trim_suffix("}")):
					ok = false
		if ok:
			break
		pair = options[rng.randi() % options.size()]
	var out := []
	for line: String in pair:
		for k in values:
			line = line.replace("{%s}" % k, str(values[k]))
		out.append(line)
	return out


## Context slots about the two speakers and the tribe right now.
static func context_for(social: SocialSystem, s: Villager, l: Villager) -> Dictionary:
	var values := {}
	var tod := SimClock.get_time_of_day()
	values["time_remark"] = "Lovely morning, isn't it?" if tod < 0.45 else ("Hot day today." if tod < 0.65 else "The evening is calm.")
	var work := String(l.profession).to_lower() if l.profession != &"" else "work"
	values["work_noun"] = work
	var skill := ProfessionSystem.skill_of(l.profession)
	values["reply_work"] = "Getting better at it every day." if skill != &"" and l.skills.get_level(skill) > 50.0 \
			else "Hard, but I'm learning."
	var tribe := social.ctx.tribe
	var food := tribe.stockpile.get_amount(ResourceType.FOOD)
	if food < tribe.population() * 4:
		values["shortage_remark"] = "The food stores are running low."
		values["shortage_reply"] = "I know. We'll have to do something."
	elif tribe.stockpile.get_amount(ResourceType.WOOD) < 15:
		values["shortage_remark"] = "We're short of wood again."
		values["shortage_reply"] = "I'll fetch some later."
	var entries := social.ctx.society.history.entries
	for i in range(entries.size() - 1, maxi(-1, entries.size() - 8), -1):
		var e: Dictionary = entries[i]
		if e["category"] in ["birth", "death", "romance", "leadership", "construction", "discovery", "dispute"]:
			values["event"] = e["text"]
			values["event_reply"] = "Who would have thought." if e["category"] != "death" else "Sad times."
			break
	# The tribe's own words, once it has them.
	var culture := social.ctx.society.culture
	var best := 0.4
	for c in culture.customs.values():
		if c["status"] in CultureSystem.ACTIVE and culture.devotion_of(s.villager_id, c["id"]) > best:
			best = culture.devotion_of(s.villager_id, c["id"])
			values["custom"] = String(c["word"]).capitalize()
	if culture.language.knows(&"valley"):
		values["place"] = culture.language.capitalized(&"valley")
	var kids := social.ctx.society.demographics.children_of(l.villager_id)
	for k in kids:
		var c := social.get_villager(k)
		if c != null and c.is_child():
			values["child"] = c.villager_name
			break
	return values


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
