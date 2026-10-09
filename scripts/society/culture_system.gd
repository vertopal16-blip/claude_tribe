class_name CultureSystem
extends RefCounted
## The tribe's culture, emerging from the lives of its members.
##
## Nothing cultural is predefined or randomly assigned:
## - BELIEFS: each villager holds values (CulturalValues). Experiences shape
##   them - interpreted through temperament and existing beliefs, so the same
##   famine can teach one person to share and another to rely on no one.
##   Parents, mentors, friends, leaders, elders and the remembered dead pass
##   their beliefs on; the young sometimes reject what their elders hold dear.
##   The tribe's values are the influence-weighted beliefs of its members.
## - CUSTOMS: repeated behaviour (gathering by the fire, sharing in hard
##   times, funerals, harvests, quarrels...) becomes a custom once the people
##   involved share beliefs that give it meaning (CustomCatalog). Each
##   villager is more or less devoted to each custom; customs spread, are
##   practised in real ceremonies, become central, get contested, reformed by
##   innovators, kept alive by one generation and dropped by the next, and
##   vanish when nobody practises them. Families and guilds can have customs
##   of their own.
## - MEMORY: important events become stories (LoreBook) that are retold,
##   distorted and eventually lost; they are commemorated and reinforce the
##   values they stand for.
## - LANGUAGE: the tribe coins words for what matters to it (TribalLanguage),
##   names places and itself, and later names its children in its own sounds.
## - ART: pigments, a motif, sashes, painted homes, carvings and monuments,
##   and architectural eras (TribalAesthetics).
## Every change is recorded with the data that caused it, so the culture
## panel can explain why the tribe is the way it is.

const CHECK_INTERVAL := 30.0
const NORMS: Array[StringName] = [&"cooperation", &"hierarchy", &"spirituality", &"industry", &"consensus", &"tradition"]
const YEARLY: Array[StringName] = [&"commemoration", &"leader_remembrance", &"ancestor_veneration"]
const CEREMONY_SECONDS := 40.0
const ACTIVE := ["emerging", "established", "central", "contested", "fading"]
const YOUNG_MAX_AGE := 28.0
## Customs a single family may keep as its own (others belong to the whole tribe).
const FAMILY_CUSTOMS: Array[StringName] = [&"funeral_rites", &"ancestor_veneration", &"kin_naming", &"partnership_feast",
	&"vows", &"birth_welcome", &"coming_of_age_trial", &"coming_of_age_teaching", &"evening_fire", &"storytelling"]
const OLD_MIN_AGE := 45.0

## What moved a value, in words (cause key -> phrase).
const CAUSES := {
	"was_helped": "the starving were fed by others", "helped": "people shared food with the hungry",
	"refused_coop": "seeing the hungry refused made people want everyone to share",
	"refused_order": "seeing the hungry refused made people want someone to keep order",
	"refused_alone": "being refused taught people to rely on themselves",
	"famine_shared": "hungry times were survived by sharing", "famine_order": "hungry times made people want order",
	"famine_alone": "in hungry times everyone had to fend for themselves",
	"fought_proud": "people stood their ground in fights", "fought_peace": "fights made people long for peace",
	"saw_fight": "people saw others come to blows", "humiliated": "people were humiliated in front of others",
	"reconciled": "enemies made peace", "mediated_elder": "elders settled disputes", "mediated_leader": "leaders settled disputes",
	"child_born": "children were born", "partners": "couples bound themselves together", "betrayed": "people were betrayed",
	"promise_kept": "promises were kept", "loss": "people lost those they loved", "death_seen": "people saw death",
	"discovered": "new things were discovered", "taught_by_elder": "elders taught the young", "taught": "knowledge was passed on",
	"mastery_craft": "people mastered crafts", "mastery_land": "people mastered work on the land",
	"mastery_healing": "people mastered healing", "project_done": "shared projects succeeded",
	"project_failed": "plans failed and people fell back on old ways", "leader_chosen": "leaders were chosen",
	"vetoed": "the leadership blocked plans", "overthrown": "leaders were cast down", "rival_honored": "rivals were honoured",
	"ceremony": "people took part in ceremonies", "work_land": "people worked the land", "work_craft": "people worked with their hands",
	"age": "the old grew set in their ways", "youth": "the young questioned what their elders believed",
	"teaching": "parents and teachers passed on their beliefs", "legacy": "the teachings of the dead lived on",
	"stories": "old stories were told", "norm_shame": "those who broke custom were shamed", "custom": "customs were practised",
	"gift": "gifts were given freely", "traded": "goods were traded", "faction": "people joined factions",
}

var society: SocietySystem
## villager id -> CulturalValues
var people: Dictionary = {}
## villager id -> {custom id: devotion -1..1}
var devotion: Dictionary = {}
## id -> custom (see _found_custom)
var customs: Dictionary = {}
var next_custom := 1
## pattern -> {"count", "who": {id: n}, "first_day", "notes": [], "help", "refused"}
var patterns: Dictionary = {}
## value -> {cause: weight} (decays), and cohort-specific ledgers
var causes: Dictionary = {}
var cohort_causes: Dictionary = {"young": {}, "old": {}}
var cause_counts: Dictionary = {}
var tribe_values: Dictionary = {}
var cohort_values: Dictionary = {"young": {}, "old": {}}
## [{"day", "values"}] one per day
var snapshots: Array = []
## value -> level announced (-1, 0, 1, 2)
var core_levels: Dictionary = {}
## dead influential people: id -> {"name", "values": [], "weight", "day"}
var legacies: Dictionary = {}
var movements: Array = []
## Explained cultural changes: [{"day", "text"}]
var changes: Array = []
var ceremonies: Array = []
var counters: Dictionary = {}
## Recent breaches of custom: [villager id, day, what]
var violations: Array = []
## Divides already announced: value -> day
var divides: Dictionary = {}
## Temporary blessings (before_expedition): villager id -> sim time until
var blessings: Dictionary = {}
## Couples who swore vows: Vector2i -> day
var vowed: Dictionary = {}
var famine := {}
var language: TribalLanguage
var lore := LoreBook.new()
var aesthetics := TribalAesthetics.new()
var _timer := 0.0
var _last_snapshot_day := -1
var _phase := 0
var _step := 0
var _firsts: Dictionary = {}


func _init(s: SocietySystem) -> void:
	society = s
	var seed_value: int = s.ctx.config.social_seed if s.ctx.config.social_seed != 0 else s.ctx.world_seed
	language = TribalLanguage.new(hash([seed_value, "language"]))
	for k in CulturalValues.VALUES:
		tribe_values[k] = 0.0


# ==========================================================================
# People
# ==========================================================================

func register(v: Villager) -> void:
	if people.has(v.villager_id):
		return
	# Founders bring faint personal leanings; children are born with none.
	people[v.villager_id] = CulturalValues.new() if not v.parent_ids.is_empty() else CulturalValues.from_personality(v.personality)
	devotion[v.villager_id] = {}


func values_of(v: Villager) -> CulturalValues:
	if not people.has(v.villager_id):
		register(v)
	return people[v.villager_id]


func value(v: Villager, k: StringName) -> float:
	return values_of(v).get_value(k)


func tribe_value(k: StringName) -> float:
	return float(tribe_values.get(k, 0.0))


func devotion_of(v_id: int, custom_id: int) -> float:
	return float(devotion.get(v_id, {}).get(custom_id, 0.0))


func _set_devotion(v_id: int, custom_id: int, d: float) -> void:
	if not devotion.has(v_id):
		devotion[v_id] = {}
	devotion[v_id][custom_id] = clampf(d, -1.0, 1.0)


func _shift(v: Villager, k: StringName, delta: float, cause: String) -> void:
	values_of(v).shift(k, delta)
	var led: Dictionary = causes.get(k, {})
	led[cause] = float(led.get(cause, 0.0)) + delta
	causes[k] = led
	cause_counts[cause] = int(cause_counts.get(cause, 0)) + 1
	var c := _cohort(v)
	if c != "":
		var cl: Dictionary = cohort_causes[c].get(k, {})
		cl[cause] = float(cl.get(cause, 0.0)) + delta
		cohort_causes[c][k] = cl


func _cohort(v: Villager) -> String:
	if v.is_child():
		return ""
	if v.age_years <= YOUNG_MAX_AGE:
		return "young"
	if v.age_years >= OLD_MIN_AGE:
		return "old"
	return ""


func similarity(a: Villager, b: Villager) -> float:
	return values_of(a).similarity(values_of(b))


# ==========================================================================
# Legacy API used across the simulation
# ==========================================================================

## 0..1 summaries of the tribe's values (0.5 = no shared view).
func norm(n: StringName) -> float:
	var x := 0.0
	match n:
		&"cooperation": x = tribe_value(&"cooperation") * 0.7 + tribe_value(&"generosity") * 0.3 - tribe_value(&"independence") * 0.4
		&"hierarchy": x = tribe_value(&"hierarchy") - tribe_value(&"equality") * 0.5
		&"spirituality": x = tribe_value(&"spirituality")
		&"industry": x = (tribe_value(&"craftsmanship") + tribe_value(&"achievement")) * 0.5
		&"consensus": x = tribe_value(&"equality") * 0.6 + tribe_value(&"cooperation") * 0.4
		&"tradition": x = tribe_value(&"tradition") - tribe_value(&"curiosity") * 0.3
		_: x = tribe_value(n)
	return clampf(0.5 + 0.5 * x, 0.0, 1.0)


## Nudges everyone's beliefs a little after a tribe-wide experience.
func shift(n: StringName, delta: float, why: String = "") -> void:
	var k := n
	match n:
		&"industry": k = &"achievement"
		&"consensus": k = &"equality"
	if not CulturalValues.VALUES.has(k):
		return
	for v in society.ctx.tribe.villagers:
		if not v.is_child():
			_shift(v, k, delta, "project_done" if why.contains("project") else "custom")


func count(key: String, amount: int = 1) -> void:
	counters[key] = int(counters.get(key, 0)) + amount


## Is a custom of this kind alive and accepted in the tribe?
func has_tradition(kind: StringName) -> bool:
	return strength(kind) >= 0.3


## Support (0..1) for the strongest tribe-wide custom of a kind (0 if none).
func strength(kind: StringName) -> float:
	var best := 0.0
	for c in customs.values():
		if c["kind"] == String(kind) and c["status"] in ACTIVE and int(c["scope"]) < 0:
			best = maxf(best, float(c["support"]))
	return best


func custom_of_kind(kind: StringName) -> Dictionary:
	for c in customs.values():
		if c["kind"] == String(kind) and c["status"] in ACTIVE:
			return c
	return {}


func tradition_names() -> PackedStringArray:
	var out: PackedStringArray = []
	for c in customs.values():
		if c["status"] in ACTIVE and float(c["support"]) >= 0.3:
			out.append("the %s" % String(c["word"]).capitalize())
	return out


func sharing_bonus() -> float:
	return 0.25 * strength(&"sharing_custom") + 0.15 * tribe_value(&"generosity") - 0.2 * strength(&"strict_rationing")


func peace_norm() -> float:
	return norm(&"cooperation") + 0.3 * strength(&"peacekeeping")


func evening_bonus() -> float:
	return 0.18 * strength(&"evening_fire") + 0.12 * strength(&"storytelling")


func ration_limit() -> int:
	return 2 if strength(&"strict_rationing") >= 0.4 else 99


## Share of adults that must back a candidate before they become chief.
func election_share() -> float:
	return clampf(0.5 + 0.15 * tribe_value(&"equality") - 0.12 * tribe_value(&"hierarchy") + 0.25 * strength(&"no_one_above"), 0.4, 0.85)


func council_favoured() -> bool:
	return norm(&"consensus") >= 0.55 or has_tradition(&"elder_council")


func elder_council() -> bool:
	return has_tradition(&"elder_council")


func hereditary() -> bool:
	return has_tradition(&"hereditary")


## Extra teaching strength from valuing knowledge and craft traditions.
func learning_bonus(student: Villager, teacher: Villager) -> float:
	var b := 1.0 + 0.4 * maxf(0.0, value(student, &"knowledge")) + 0.2 * maxf(0.0, value(teacher, &"knowledge"))
	for c in customs.values():
		if c["kind"] == "craft_mark" and c["status"] in ACTIVE and _in_scope(c, student.villager_id) and _in_scope(c, teacher.villager_id):
			b += 0.4 * maxf(0.0, devotion_of(teacher.villager_id, c["id"]))
	if teacher.life_stage() == &"elder":
		b += 0.25 * maxf(0.0, tribe_value(&"elders"))
	return b


func efficiency_bonus(v: Villager, skill: StringName) -> float:
	if skill == &"fishing" and float(blessings.get(v.villager_id, 0.0)) > SimClock.sim_time:
		return 1.1
	return 1.0


func conception_factor(v: Villager) -> float:
	return clampf(1.0 + 0.4 * value(v, &"family"), 0.6, 1.5)


## How much more it takes for this couple to split (0..1).
func bond_tolerance(a: int, b: int) -> float:
	var t := 0.0
	var va := society.ctx.social.get_villager(a)
	if va != null:
		t += 0.3 * maxf(0.0, value(va, &"loyalty")) + 0.2 * maxf(0.0, value(va, &"family"))
	if vowed.has(Vector2i(mini(a, b), maxi(a, b))):
		t += 0.3 * maxf(0.2, strength(&"vows"))
	return t


## Elders weigh more where the tribe respects them.
func elder_influence(v: Villager) -> float:
	if v.life_stage() != &"elder":
		return 0.0
	return 6.0 + 24.0 * maxf(0.0, tribe_value(&"elders")) + 8.0 * strength(&"elder_council")


## Feeling about a kind of building (-1..1) from beliefs, and wariness of
## the untried.
func project_attitude(v: Villager, type: StringName, first_of_kind: bool) -> float:
	var cv := values_of(v)
	var a := 0.0
	match type:
		&"farm": a = cv.alignment({&"nature": 0.6, &"cooperation": 0.4})
		&"workshop": a = cv.alignment({&"craftsmanship": 0.8, &"achievement": 0.4})
		&"longhouse": a = cv.alignment({&"cooperation": 0.6, &"equality": 0.5, &"hospitality": 0.3})
		&"shrine": a = cv.alignment({&"spirituality": 0.8, &"elders": 0.4})
		&"gathering_circle": a = cv.alignment({&"cooperation": 0.5, &"tradition": 0.5, &"spirituality": 0.4})
		&"totem": a = cv.alignment({&"spirituality": 0.6, &"tradition": 0.5, &"craftsmanship": 0.4})
		&"memorial_stone": a = cv.alignment({&"elders": 0.6, &"loyalty": 0.5, &"tradition": 0.5, &"family": 0.3})
		&"food_drive": a = cv.alignment({&"cooperation": 0.7, &"generosity": 0.4, &"independence": -0.5})
	if first_of_kind:
		a += 0.25 * cv.get_value(&"curiosity") - 0.3 * cv.get_value(&"tradition")
	return clampf(a, -1.0, 1.0)


# ==========================================================================
# Events from the rest of the simulation
# ==========================================================================

## Every remembered experience can shape beliefs and feed patterns.
func on_social_event(v: Villager, kind: StringName, rec: Dictionary) -> void:
	if v == null or v.is_dead:
		return
	var social := society.ctx.social
	var other := social.get_villager(int(rec.get("other", -1)))
	var p := v.personality
	var cv := values_of(v)
	var oid := int(rec.get("other", -1))
	match kind:
		&"chatted":
			count("conversations")
			var tod := SimClock.get_time_of_day()
			var fire := society.ctx.tribe.campfire
			if (tod >= 0.72 or tod < 0.04) and fire != null and v.villager_id < oid \
					and v.global_position.distance_to(fire.global_position) < 16.0:
				observe("evening_talk", [v.villager_id, oid], "")
				_practise(&"evening_fire", [v.villager_id, oid])
				_practise(&"storytelling", [v.villager_id, oid])
		&"was_helped":
			count("help")
			if other != null and social.graph.is_kin(v.villager_id, oid):
				_shift(v, &"family", 0.03, "was_helped")
			else:
				_shift(v, &"cooperation", 0.03, "was_helped")
				_shift(v, &"generosity", 0.03, "was_helped")
				_shift(v, &"hospitality", 0.015, "was_helped")
			observe("hardship", [v.villager_id, oid], "%s fed the starving %s" % [social.name_of(oid), v.villager_name], "help")
			_practise(&"sharing_custom", [v.villager_id, oid])
		&"helped":
			_shift(v, &"generosity", 0.02, "helped")
			_shift(v, &"cooperation", 0.01, "helped")
			_reward_norm(v, other)
		&"was_refused":
			count("refusals")
			# The same hurt teaches different lessons to different people.
			if cv.get_value(&"hierarchy") > cv.get_value(&"equality") + 0.05 or p.get_trait(&"status_desire") > 0.65:
				_shift(v, &"hierarchy", 0.03, "refused_order")
			elif cv.get_value(&"cooperation") + p.get_trait(&"empathy") - 0.5 > cv.get_value(&"independence"):
				_shift(v, &"cooperation", 0.025, "refused_coop")
				_shift(v, &"generosity", 0.02, "refused_coop")
			else:
				_shift(v, &"independence", 0.04, "refused_alone")
			observe("hardship", [v.villager_id, oid], "%s refused to feed the starving %s" % [social.name_of(oid), v.villager_name], "refused")
		&"refused":
			_shift(v, &"independence", 0.01, "refused_alone")
			_sanction(v, other, "refused to share food")
		&"starved":
			_on_starved(v)
		&"fought":
			if v.villager_id < oid:
				observe("conflict", [v.villager_id, oid], "%s and %s came to blows" % [v.villager_name, social.name_of(oid)])
				_after_fight(v, other)
			if p.get_trait(&"aggressiveness") > 0.6 or cv.get_value(&"strength") > 0.15:
				_shift(v, &"strength", 0.03, "fought_proud")
				_shift(v, &"courage", 0.01, "fought_proud")
			else:
				_shift(v, &"cooperation", 0.02, "fought_peace")
		&"saw_fight":
			if p.get_trait(&"empathy") > 0.5:
				_shift(v, &"cooperation", 0.012, "saw_fight")
			else:
				_shift(v, &"strength", 0.01, "saw_fight")
		&"humiliated":
			if p.get_trait(&"status_desire") > 0.6:
				_shift(v, &"achievement", 0.02, "humiliated")
			else:
				_shift(v, &"equality", 0.025, "humiliated")
		&"reconciled":
			_shift(v, &"cooperation", 0.02, "reconciled")
			if other != null and v.villager_id < oid and (social.graph.has_tag(v.villager_id, oid, &"enemy")
					or social.graph.has_tag(v.villager_id, oid, &"rival") or _fought_before(v, oid)):
				_lore_once("reconcile_%d_%d" % [v.villager_id, oid], "reconciliation", [v.villager_id, oid],
						[v.villager_name, social.name_of(oid)], {&"cooperation": 1.0}, 0.6, {})
		&"mediated":
			var m := social.get_villager(oid)
			if m != null and m.life_stage() == &"elder":
				_shift(v, &"elders", 0.03, "mediated_elder")
			elif m != null and society.politics.is_leader(m):
				_shift(v, &"hierarchy", 0.02, "mediated_leader")
			_shift(v, &"cooperation", 0.01, "reconciled")
		&"child_born":
			_shift(v, &"family", 0.05, "child_born")
		&"became_partners":
			_shift(v, &"family", 0.03, "partners")
			_shift(v, &"loyalty", 0.02, "partners")
			if v.villager_id < oid:
				observe("partnership", [v.villager_id, oid], "%s and %s became a couple" % [v.villager_name, social.name_of(oid)])
				_on_partnership(v, other)
		&"partner_unfaithful", &"promise_broken":
			_shift(v, &"loyalty", 0.04, "betrayed")
		&"promise_kept":
			_shift(v, &"loyalty", 0.02, "promise_kept")
		&"lost_partner", &"lost_child", &"lost_family":
			_shift(v, &"family", 0.03, "loss")
			_shift(v, &"spirituality", 0.03 if p.get_trait(&"curiosity") < 0.7 else 0.01, "loss")
			_shift(v, &"tradition", 0.01, "loss")
		&"lost_friend":
			_shift(v, &"loyalty", 0.015, "loss")
			_shift(v, &"spirituality", 0.015, "loss")
		&"saw_death":
			_shift(v, &"spirituality", 0.015, "death_seen")
		&"discovered":
			_shift(v, &"curiosity", 0.05, "discovered")
			_shift(v, &"knowledge", 0.04, "discovered")
			_shift(v, &"achievement", 0.02, "discovered")
			observe("expedition", [v.villager_id], "%s discovered %s" % [v.villager_name, rec.get("detail", "something")])
		&"learned_discovery", &"was_taught":
			_shift(v, &"knowledge", 0.025, "taught")
			if other != null and other.age_years > v.age_years + 15.0:
				_shift(v, &"elders", 0.025, "taught_by_elder")
			if kind == &"was_taught" and other != null and other.profession != &"":
				observe("craft_teaching", [oid, v.villager_id], "%s taught %s the ways of the %s" % [
						social.name_of(oid), v.villager_name, String(other.profession).to_lower()])
				_practise(&"craft_mark")
		&"taught":
			_shift(v, &"knowledge", 0.015, "taught")
		&"skill_mastered":
			var skill := StringName(rec.get("detail", ""))
			if skill in [&"toolmaking", &"building", &"stonework", &"woodcutting"]:
				_shift(v, &"craftsmanship", 0.05, "mastery_craft")
			elif skill in [&"foraging", &"farming", &"fishing"]:
				_shift(v, &"nature", 0.04, "mastery_land")
			elif skill == &"healing":
				_shift(v, &"knowledge", 0.04, "mastery_healing")
			_shift(v, &"achievement", 0.03, "mastery_craft")
		&"built_together", &"built":
			_shift(v, &"cooperation", 0.006, "project_done")
			_shift(v, &"craftsmanship", 0.006, "work_craft")
		&"project_completed":
			_shift(v, &"achievement", 0.04, "project_done")
			_shift(v, &"cooperation", 0.02, "project_done")
		&"project_failed":
			_shift(v, &"tradition", 0.02, "project_failed")
		&"became_leader":
			_shift(v, &"hierarchy", 0.05, "leader_chosen")
			_shift(v, &"achievement", 0.03, "leader_chosen")
		&"lost_leadership":
			_shift(v, &"equality", 0.02, "overthrown")
		&"endorsed":
			_shift(v, &"hierarchy", 0.01, "leader_chosen")
		&"vetoed":
			_shift(v, &"equality", 0.04, "vetoed")
		&"rival_honored":
			if p.get_trait(&"competitiveness") > 0.55:
				_shift(v, &"achievement", 0.02, "rival_honored")
			else:
				_shift(v, &"equality", 0.02, "rival_honored")
		&"joined_group":
			_shift(v, &"loyalty", 0.01, "faction")
		&"got_tool":
			_shift(v, &"generosity", 0.01, "gift")
		&"traded":
			_shift(v, &"independence", 0.01, "traded")
		&"ceremony", &"feast":
			_shift(v, &"tradition", 0.01, "ceremony")


func _fought_before(v: Villager, other_id: int) -> bool:
	for r in v.memory.about(other_id):
		if r.kind == &"fought":
			return true
	return false


## Hunger shapes beliefs according to how the tribe actually got through it.
func _on_starved(v: Villager) -> void:
	var help := int(counters.get("help", 0))
	var refused := int(counters.get("refusals", 0))
	var cv := values_of(v)
	if help > refused or strength(&"sharing_custom") > 0.3:
		_shift(v, &"cooperation", 0.025, "famine_shared")
		_shift(v, &"generosity", 0.02, "famine_shared")
	elif strength(&"strict_rationing") > 0.3 or cv.get_value(&"hierarchy") > cv.get_value(&"independence"):
		_shift(v, &"hierarchy", 0.025, "famine_order")
	else:
		_shift(v, &"independence", 0.03, "famine_alone")
	observe("hardship", [v.villager_id], "%s went hungry" % v.villager_name)
	if famine.is_empty():
		famine = {"start": SimClock.get_day(), "help0": help, "ref0": refused, "hungry": {}}
	famine["hungry"][v.villager_id] = true


## Breaking a custom costs standing with those who hold it; independent
## minds don't feel the shame.
func _sanction(v: Villager, victim: Villager, what: String) -> void:
	var weight := maxf(tribe_value(&"generosity"), strength(&"sharing_custom"))
	if weight < 0.2:
		return
	violations.append([v.villager_id, SimClock.get_day(), what])
	if violations.size() > 20:
		violations.pop_front()
	var social := society.ctx.social
	if victim != null:
		social.graph.adjust_field(victim.villager_id, v.villager_id, "respect", -0.1 * weight)
	for w in society.ctx.tribe.villagers_near(v.global_position, SocialSystem.WITNESS_RADIUS):
		if w != v and w != victim and not w.is_child():
			social.graph.adjust_field(w.villager_id, v.villager_id, "respect", -0.06 * weight * maxf(0.2, value(w, &"generosity") + 0.5))
	var own := value(v, &"generosity") - value(v, &"independence")
	if own > -0.1:
		v.emotions.feel(&"shame", 0.25 * weight * (own + 0.5), "Broke the custom: %s" % what, v.personality)
		_shift(v, &"generosity", 0.01, "norm_shame")


func _reward_norm(v: Villager, receiver: Villager) -> void:
	var weight := maxf(tribe_value(&"generosity"), strength(&"sharing_custom"))
	if weight < 0.15:
		return
	society.politics.add_prestige(v, 1.5 * weight)
	if receiver != null:
		society.ctx.social.graph.adjust_field(receiver.villager_id, v.villager_id, "respect", 0.05 * weight)


func _after_fight(a: Villager, b: Villager) -> void:
	if b == null:
		return
	var g := society.ctx.social.graph
	if strength(&"contest") >= 0.35:
		# Settled by the contest: grudges are dropped, as custom demands.
		for pair in [[a.villager_id, b.villager_id], [b.villager_id, a.villager_id]]:
			g.set_field(pair[0], pair[1], "resentment", g.resentment(pair[0], pair[1]) * 0.4)
		_practise(&"contest")
	elif strength(&"peacekeeping") >= 0.35:
		society.politics.record_dispute(a.villager_id, b.villager_id, "a fight")
		_practise(&"peacekeeping")


func on_death(v: Villager) -> void:
	count("deaths")
	var social := society.ctx.social
	var mourners: Array = []
	for id in social.kin_of(v.villager_id) + social.friends_of(v.villager_id):
		if social.is_alive(id) and not mourners.has(id):
			mourners.append(id)
	observe("death", mourners, "the death of %s" % v.villager_name)
	# The beliefs of the influential outlive them through those they taught.
	var inf := society.politics.influence(v)
	if inf >= 30.0 or v.life_stage() == &"elder" or society.politics.is_leader(v):
		legacies[v.villager_id] = {"name": v.villager_name, "values": values_of(v).to_array(), "weight": inf, "day": SimClock.get_day()}
		if legacies.size() > 10:
			var oldest := -1
			var od := INF
			for id in legacies:
				if float(legacies[id]["weight"]) < od:
					od = float(legacies[id]["weight"])
					oldest = id
			legacies.erase(oldest)
	# Founders and great figures become part of the tribe's story.
	if v.born_day < 0 or v.prestige >= 40.0 or society.politics.is_leader(v):
		var epithet := _epithet(v)
		_add_lore("passing", [v.villager_id], [v.villager_name], values_of(v).values.duplicate(), 0.6 + v.prestige / 200.0,
				{"n": int(v.age_years), "x": "%s was remembered as %s." % [v.villager_name, epithet], "epithet": epithet})
	var funeral := custom_of_kind(&"funeral_rites")
	if not funeral.is_empty():
		start_ceremony(funeral, "funeral of %s" % v.villager_name, _place("sacred"), CEREMONY_SECONDS, [v.villager_id])
	elif not custom_of_kind(&"ancestor_veneration").is_empty():
		start_ceremony(custom_of_kind(&"ancestor_veneration"), "farewell to %s" % v.villager_name, _place("sacred"), CEREMONY_SECONDS, [v.villager_id])
	people.erase(v.villager_id)
	devotion.erase(v.villager_id)


func _epithet(v: Villager) -> String:
	var top := values_of(v).strongest(1)
	var by_value := {&"courage": "the brave", &"strength": "the strong", &"knowledge": "the wise", &"curiosity": "the seeker",
		&"generosity": "the generous", &"cooperation": "the peacemaker", &"hierarchy": "the commander", &"equality": "the just",
		&"craftsmanship": "the maker", &"nature": "the gardener", &"spirituality": "the seer", &"family": "the mother" if v.sex == &"female" else "the father",
		&"loyalty": "the faithful", &"tradition": "the keeper", &"elders": "the elder", &"achievement": "the great",
		&"hospitality": "the kind", &"independence": "the free"}
	if v.born_day < 0 and (top.is_empty() or float(top[0][1]) < 0.2):
		return "the founder"
	return by_value.get(top[0][0], "the founder") if not top.is_empty() else "the founder"


func on_harvest(v: Villager = null, food: int = 0, first: bool = false) -> void:
	count("harvests")
	if v != null:
		observe("harvest", [v.villager_id], "%s brought in a harvest" % v.villager_name)
		if first:
			_lore_once("first_harvest", "first_harvest", [v.villager_id], [v.villager_name], {&"nature": 0.6, &"cooperation": 0.5, &"achievement": 0.4},
					0.8, {"n": food, "epithet": _epithet(v)})
	var stock := society.ctx.tribe.stockpile.get_amount(ResourceType.FOOD)
	var pop := society.ctx.tribe.population()
	var feast := custom_of_kind(&"harvest_feast")
	var year := society.ctx.config.days_per_year
	if not feast.is_empty() and SimClock.get_day() - int(feast.get("last_feast", -100)) >= year and stock > pop * 6:
		feast["last_feast"] = SimClock.get_day()
		society.ctx.tribe.stockpile.take(ResourceType.FOOD, pop)
		start_ceremony(feast, "harvest feast", _place("fire"), CEREMONY_SECONDS)
	var fruits := custom_of_kind(&"first_fruits")
	if not fruits.is_empty() and SimClock.get_day() - int(fruits.get("last_feast", -100)) >= year and stock > pop * 3:
		fruits["last_feast"] = SimClock.get_day()
		society.ctx.tribe.stockpile.take(ResourceType.FOOD, maxi(2, pop / 3))
		start_ceremony(fruits, "offering of the first fruits", _place("sacred"), CEREMONY_SECONDS * 0.6)


func on_birth(child: Villager, parents: Array) -> void:
	var social := society.ctx.social
	register(child)
	observe("birth", parents, "%s was born" % child.villager_name)
	_lore_once("first_birth", "first_birth", [child.villager_id], [child.villager_name], {&"family": 1.0}, 0.75, {})
	var welcome := custom_of_kind(&"birth_welcome")
	if not welcome.is_empty() and float(welcome["support"]) >= 0.3:
		var stock := society.ctx.tribe.stockpile
		var gift := mini(6, stock.get_amount(ResourceType.FOOD) / 4)
		if gift > 0:
			stock.take(ResourceType.FOOD, gift)
			for pid in parents:
				var parent := social.get_villager(pid)
				if parent != null:
					parent.needs.eat(gift / maxi(1, parents.size()))
					parent.emotions.feel(&"gratitude", 0.3, "Gifts for the newborn %s" % child.villager_name, parent.personality)
			_practise(&"birth_welcome")
	# Children inherit their parents' devotion to customs as a starting point.
	for c in customs.values():
		var total := 0.0
		for pid in parents:
			total += devotion_of(pid, c["id"])
		if not parents.is_empty():
			_set_devotion(child.villager_id, c["id"], total / parents.size() * 0.5)


## A name for a newborn according to the tribe's naming customs.
func name_for_child(parents: Array, rng: RandomNumberGenerator, fallback: String) -> String:
	var social := society.ctx.social
	var base := fallback
	if language.size() >= 4:
		base = language.personal_name(rng)
	var kn := custom_of_kind(&"kin_naming")
	if not kn.is_empty() and float(kn["support"]) >= 0.3 and not parents.is_empty():
		var from_father := int(kn["form_idx"]) == 0
		var pid: int = parents[1] if from_father and parents.size() > 1 else parents[0]
		var pname := social.name_of(pid).split(" ")[0]
		_practise(&"kin_naming")
		# "<name> <parent>-<child-of>", in the tribe's own sounds.
		return "%s %s%s" % [base, pname, language.root(&"child")]
	var av := custom_of_kind(&"ancestor_veneration")
	if not av.is_empty() and float(av["support"]) >= 0.4 and int(av["form_idx"]) == 0 and rng.randf() < 0.5:
		# Carry on the name of an honoured ancestor.
		for id in legacies:
			var n: String = legacies[id]["name"]
			if not social.is_alive(id):
				return n.split(" ")[0] + " " + language.root(&"new").capitalize()
	return base


func on_came_of_age(v: Villager) -> void:
	var social := society.ctx.social
	observe("coming_of_age", [v.villager_id] + v.parent_ids, "%s came of age" % v.villager_name)
	var trial := custom_of_kind(&"coming_of_age_trial")
	var teach := custom_of_kind(&"coming_of_age_teaching")
	if not trial.is_empty():
		start_ceremony(trial, "trial of %s" % v.villager_name, _place("fire"), CEREMONY_SECONDS * 0.6, [v.villager_id])
	elif not teach.is_empty():
		start_ceremony(teach, "apprenticing of %s" % v.villager_name, _place("fire"), CEREMONY_SECONDS * 0.6, [v.villager_id])
	elif social.get_villager(v.villager_id) == null:
		return


func _on_partnership(a: Villager, b: Villager) -> void:
	if b == null:
		return
	var feast := custom_of_kind(&"partnership_feast")
	var vows := custom_of_kind(&"vows")
	if not vows.is_empty() and float(vows["support"]) >= 0.25:
		start_ceremony(vows, "vows of %s and %s" % [a.villager_name, b.villager_name], _place("sacred"), CEREMONY_SECONDS * 0.6,
				[a.villager_id, b.villager_id])
	elif not feast.is_empty():
		start_ceremony(feast, "celebration of %s and %s" % [a.villager_name, b.villager_name], _place("fire"), CEREMONY_SECONDS * 0.7,
				[a.villager_id, b.villager_id])


## Someone leaves to fish (or scout): those who keep the custom ask for luck first.
func on_expedition(v: Villager) -> void:
	observe("expedition", [v.villager_id], "%s went out to fish" % v.villager_name)
	var c := custom_of_kind(&"before_expedition")
	if c.is_empty() or devotion_of(v.villager_id, c["id"]) < 0.2:
		return
	blessings[v.villager_id] = SimClock.sim_time + society.ctx.config.day_length_seconds * 0.5
	v.emotions.feel(&"courage", 0.3, "Sang the %s before going out" % String(c["word"]).capitalize(), v.personality)
	v.emotions.values[&"fear"] = v.emotions.get_value(&"fear") * 0.5
	_practise(&"before_expedition")


func on_tree_felled(v: Villager, node: ResourceNode) -> void:
	observe("woodcut", [v.villager_id], "")
	var c := custom_of_kind(&"tree_thanks")
	if c.is_empty() or devotion_of(v.villager_id, c["id"]) < 0.2:
		return
	# A sapling planted at once: the tree comes back sooner.
	node._regrow_timer = node.regrow_interval * 0.45
	_practise(&"tree_thanks")


func on_discovery(v: Villager, tech: StringName, label: String) -> void:
	if not _firsts.has("tech_" + String(tech)):
		_firsts["tech_" + String(tech)] = true
		var verbs := {&"agriculture": "plant crops", &"fishing": "catch fish", &"toolmaking": "shape tools",
			&"herbalism": "heal with herbs", &"carpentry": "join timber"}
		_add_lore("discovery", [v.villager_id], [v.villager_name], {&"curiosity": 0.7, &"knowledge": 0.7}, 0.65,
				{"x": label, "x2": verbs.get(tech, label), "epithet": "the wise"})
	_consider_new_style(tech)


func on_building_completed(b: Building) -> void:
	if b.def.id != &"hut" and b.def.id != &"farm" and not _firsts.has("first_building"):
		var who := b.contributor_ids.duplicate()
		var proposer := -1
		var p: Dictionary = society.proposals.proposals.get(b.project_id, {})
		if not p.is_empty():
			proposer = int(p["proposer"])
		var lead: int = proposer if proposer >= 0 else (int(who[0]) if not who.is_empty() else -1)
		_lore_once("first_building", "first_building", [lead], [society.ctx.social.name_of(lead)],
				{&"cooperation": 0.7, &"achievement": 0.5, &"craftsmanship": 0.4}, 0.8, {"x": b.def.display_name.to_lower()})
	_style_building(b)
	if b.def.id in [&"totem", &"memorial_stone", &"gathering_circle"]:
		var p2: Dictionary = society.proposals.proposals.get(b.project_id, {})
		var subject := int(p2.get("subject", -1))
		b.set_meta("honours", subject)
		var txt := "The tribe raised a %s" % b.def.display_name.to_lower()
		if subject >= 0:
			txt += " in memory of %s" % _lore_subject_name(subject)
			var e: Dictionary = lore.entries.get(subject, {})
			if not e.is_empty():
				e["importance"] = float(e["importance"]) + 0.2
		_change(txt + ".")


func _lore_subject_name(lore_id: int) -> String:
	var e: Dictionary = lore.entries.get(lore_id, {})
	if e.is_empty():
		return "the ancestors"
	return lore.title(e, 1, society.ctx.social)


func on_government_change(kind: StringName, who: Array, old: Array, overthrown: bool) -> void:
	var social := society.ctx.social
	if kind in [&"chief", &"hereditary"] and not who.is_empty() and not _firsts.has("first_chief"):
		var chief := social.get_villager(who[0])
		_lore_once("first_chief", "first_leader", [who[0]], [social.name_of(who[0])], {&"hierarchy": 1.0, &"loyalty": 0.3}, 0.7,
				{"x": "chief", "epithet": _epithet(chief) if chief != null else "the founder"})
	if overthrown and not old.is_empty() and not who.is_empty():
		_add_lore("leader_fell", [old[0], who[0]], [social.name_of(old[0]), social.name_of(who[0])], {&"equality": 1.0}, 0.65,
				{"epithet": "the proud"})
		observe("leader_passing_bad", [who[0]], "%s was cast down" % social.name_of(old[0]))
	if kind in [&"chief", &"hereditary"] and not who.is_empty():
		var c := social.get_villager(who[0])
		if c != null and not society.demographics.children_of(c.villager_id).is_empty():
			observe("lineage", [c.villager_id], "%s led the tribe and had children" % c.villager_name)
		if not language.knows(&"chief"):
			_coin(&"chief", "chief", [], "The tribe now has its own word for its chief: %s.")


## A leader is gone: remembered fondly or as a warning, by the tribe's own judgement.
func on_leader_gone(id: int, approval_value: float, name: String, died: bool) -> void:
	if approval_value > 0.15:
		observe("leader_passing_good", [], "%s, a respected leader, %s" % [name, "died" if died else "stepped down"])
		patterns["leader_passing_good"]["subject"] = name
	elif approval_value < -0.05:
		observe("leader_passing_bad", [], "%s, a resented leader, %s" % [name, "died" if died else "fell"])
	if society.politics.government in [&"chief", &"hereditary"]:
		observe("lineage", [], "")


# ==========================================================================
# Patterns -> customs
# ==========================================================================

func observe(pattern: String, ids: Array, note: String, tag: String = "") -> void:
	if not patterns.has(pattern):
		patterns[pattern] = {"count": 0, "who": {}, "first_day": SimClock.get_day(), "notes": [], "help": 0, "refused": 0}
	var p: Dictionary = patterns[pattern]
	p["count"] = int(p["count"]) + 1
	for id in ids:
		if id >= 0:
			p["who"][id] = int(p["who"].get(id, 0)) + 1
	if note != "" and not p["notes"].has(note):
		p["notes"].append(note)
		if p["notes"].size() > 6:
			p["notes"].pop_front()
	if tag != "":
		p[tag] = int(p.get(tag, 0)) + 1


## A custom was practised (by `ids`, whose attachment to it grows by doing it).
func _practise(kind: StringName, ids: Array = []) -> void:
	for c in customs.values():
		if c["kind"] == String(kind) and c["status"] in ACTIVE:
			c["practiced"] = int(c["practiced"]) + 1
			c["last"] = SimClock.get_day()
			for id in ids:
				if id >= 0 and _in_scope(c, id):
					_set_devotion(id, c["id"], devotion_of(id, c["id"]) + 0.05)


func max_customs() -> int:
	var n := 1 + society.ctx.tribe.population() / 5
	for b in society.ctx.tribe.buildings:
		if b.is_complete and b.def.id in [&"shrine", &"longhouse", &"gathering_circle", &"totem"]:
			n += 1
	return n


func live_count() -> int:
	var n := 0
	for c in customs.values():
		if c["status"] in ACTIVE:
			n += 1
	return n


func _requirements_met(kind: Dictionary) -> bool:
	if society.ctx.tribe.population() < int(kind["min_pop"]):
		return false
	for r: String in kind["requires"]:
		var parts := r.split(":")
		match parts[0]:
			"tech":
				if not society.tech.tribe_knows(StringName(parts[1])):
					return false
			"built":
				var ok := false
				for alt in parts[1].split("|"):
					if society.politics._has(StringName(alt)):
						ok = true
				if not ok:
					return false
			"art":
				if aesthetics.art_level < int(parts[1]):
					return false
			"lexicon":
				if language.size() < int(parts[1]):
					return false
			"lore":
				if lore.living().size() < int(parts[1]):
					return false
			"ceremonies":
				var n := 0
				for c in customs.values():
					if c["status"] in ACTIVE and CustomCatalog.get_kind(StringName(c["kind"]))["ceremony"] != "":
						n += 1
				if n < int(parts[1]):
					return false
	return true


## Average beliefs of the people involved in a pattern (weighted by involvement).
func _participant_values(p: Dictionary) -> Dictionary:
	var out := {}
	var total := 0.0
	var social := society.ctx.social
	for id in p["who"]:
		var v := social.get_villager(id)
		if v == null:
			continue
		var w := float(p["who"][id])
		total += w
		var cv := values_of(v)
		for k in CulturalValues.VALUES:
			out[k] = float(out.get(k, 0.0)) + cv.get_value(k) * w
	if total <= 0.0:
		return tribe_values.duplicate()
	for k in out:
		out[k] /= total
	# Everyone else in the tribe still colours what the practice comes to mean.
	for k in CulturalValues.VALUES:
		out[k] = float(out.get(k, 0.0)) * 0.7 + tribe_value(k) * 0.3
	return out


## How well a custom fits the beliefs of the people who would keep it.
func fitness(kind_id: StringName, vals: Dictionary, p: Dictionary = {}) -> float:
	var k := CustomCatalog.get_kind(kind_id)
	var cv := CulturalValues.new()
	cv.values = vals.duplicate()
	var f := cv.alignment(k["values"])
	var help := int(p.get("help", 0))
	var refused := int(p.get("refused", 0))
	if help + refused > 0:
		if kind_id == &"sharing_custom":
			f += 0.15 * float(help - refused) / (help + refused)
		elif kind_id == &"strict_rationing":
			f += 0.15 * float(refused - help) / (help + refused)
	return f


func _pattern_has_live_custom(pattern: String) -> bool:
	for c in customs.values():
		if c["status"] in ACTIVE and int(c["scope"]) < 0 and CustomCatalog.get_kind(StringName(c["kind"]))["pattern"] == pattern:
			return true
	return false


func _check_patterns() -> void:
	if live_count() >= max_customs():
		return
	for pattern in patterns:
		var p: Dictionary = patterns[pattern]
		if _pattern_has_live_custom(pattern):
			continue
		var vals := _participant_values(p)
		var best: StringName = &""
		var best_f := 0.06  # beliefs must give the practice some meaning
		for kind_id in CustomCatalog.candidates(pattern):
			var kind := CustomCatalog.get_kind(kind_id)
			if int(p["count"]) < int(kind["needs"]) or not _requirements_met(kind):
				continue
			if pattern == "commemoration" and _commemoration_target() < 0:
				continue
			var f := fitness(kind_id, vals, p) + society.rng.randf() * 0.04
			if f > best_f:
				best_f = f
				best = kind_id
		if best != &"":
			_found_custom(best, pattern, p, vals)
			return  # one new custom at a time


func _found_custom(kind_id: StringName, pattern: String, p: Dictionary, vals: Dictionary) -> Dictionary:
	var kind := CustomCatalog.get_kind(kind_id)
	var social := society.ctx.social
	# The founder: whoever was most involved, weighted by standing.
	var founder := -1
	var fbest := -1.0
	for id in p["who"]:
		var v := social.get_villager(id)
		if v == null:
			continue
		var s := float(p["who"][id]) * society.politics.influence(v)
		if s > fbest:
			fbest = s
			founder = id
	# Scope: guild traditions, or a custom kept by one family.
	var scope := -1
	var scope_name := ""
	var fv := social.get_villager(founder)
	if kind.get("scope", "tribe") == "group" and fv != null:
		for g in society.groups.groups_of(founder):
			if g["kind"] in ["guild", "crew"]:
				scope = g["id"]
				scope_name = g["name"]
		if scope < 0:
			return {}
	elif society.ctx.tribe.population() >= 12 and fv != null and FAMILY_CUSTOMS.has(kind_id):
		var fam := -1
		for g in society.groups.groups_of(founder):
			if g["kind"] == "family":
				fam = g["id"]
		if fam >= 0:
			var inside := 0
			var all := 0
			var members: Array = society.groups.groups[fam]["members"]
			for id in p["who"]:
				all += int(p["who"][id])
				if members.has(id):
					inside += int(p["who"][id])
			if all > 0 and float(inside) / all >= 0.8:
				scope = fam
				scope_name = society.groups.groups[fam]["name"]
	# Form: the variant that best expresses the founders' beliefs.
	var cv := CulturalValues.new()
	cv.values = vals.duplicate()
	var forms: Array = kind["forms"]
	var form_idx := 0
	var fb := -INF
	for i in forms.size():
		var a := cv.alignment(forms[i][1]) + society.rng.randf() * 0.03
		if a > fb:
			fb = a
			form_idx = i
	var id := next_custom
	next_custom += 1
	var concept := StringName("custom_%d" % id)
	var roots: Array = kind["roots"]
	var gloss := "%s-%s" % [TribalLanguage.GLOSS.get(roots[0], String(roots[0])), TribalLanguage.GLOSS.get(roots[1], String(roots[1]))]
	var word := language.coin(concept, gloss, roots)
	var origin := _origin_text(pattern, p)
	var c := {"id": id, "kind": String(kind_id), "word": word, "concept": String(concept), "gloss": gloss,
		"form_idx": form_idx, "form": forms[form_idx][0], "origin": origin, "day": SimClock.get_day(),
		"founder": founder, "founder_name": social.name_of(founder), "scope": scope, "scope_name": scope_name,
		"values": kind["values"].duplicate(), "practiced": 0, "last": SimClock.get_day(), "status": "emerging",
		"support": 0.0, "opposition": 0.0, "young": 0.0, "old": 0.0, "peak": 0.0, "low": 0,
		"color": aesthetics.palette.size(), "reforms": [], "founding_values": vals.duplicate(),
		"subject": p.get("subject", ""), "support_hist": []}
	if pattern == "commemoration":
		var target := _commemoration_target()
		c["lore"] = target
		var e: Dictionary = lore.entries.get(target, {})
		if not e.is_empty():
			e["commemorated"] = true
			for k in e["values"]:
				c["values"][k] = float(e["values"][k])
			c["subject"] = lore.title(e, 1, social)
	customs[id] = c
	# Those who took part start out devoted (as far as their beliefs allow).
	for vid in p["who"]:
		var v := social.get_villager(vid)
		if v != null:
			_set_devotion(vid, id, clampf(0.35 + values_of(v).alignment(c["values"]) * 0.8, -0.2, 0.9))
	p["count"] = 0
	p["who"] = {}
	var where := " among %s" % scope_name if scope >= 0 else ""
	var text := "A new custom takes hold%s: the %s (\"%s\") - %s, %s. It began %s." % [where, word.capitalize(), gloss,
			String(kind["describe"]).to_lower(), c["form"], origin]
	if String(c["subject"]) != "" and kind_id == &"leader_remembrance":
		text = "A new custom takes hold: the %s (\"%s\") - each year the tribe remembers %s. It began %s." % [
				word.capitalize(), gloss, c["subject"], origin]
	society.history.add(&"culture", text, [founder])
	_change(text)
	EventBus.notify("New custom: the %s" % word.capitalize(), &"social")
	if fv != null:
		society.ctx.social.remember(fv, &"ceremony", -1, -1, -1, "the first %s" % word.capitalize())
		society.politics.add_prestige(fv, 4.0)
	_add_lore("custom_founded", [founder], [social.name_of(founder)], c["values"], 0.55,
			{"x": word.capitalize(), "x2": origin.trim_prefix("after "), "epithet": _epithet(fv) if fv != null else "the founder"})
	return c


func _origin_text(pattern: String, p: Dictionary) -> String:
	var notes: Array = p["notes"]
	var some := ", ".join(notes.slice(maxi(0, notes.size() - 2))) if not notes.is_empty() else ""
	match pattern:
		"evening_talk": return "after the tribe gathered around the fire night after night"
		"hardship":
			if int(p.get("help", 0)) >= int(p.get("refused", 0)):
				return "after hard times when %s" % (some if some != "" else "food was shared")
			return "after hard times when %s" % (some if some != "" else "the hungry were turned away")
		"death": return "after %s" % (some if some != "" else "the tribe lost its own")
		"harvest": return "after the first good harvests"
		"coming_of_age": return "as the first children of the valley came of age (%s)" % some
		"partnership": return "after %s" % some
		"expedition": return "after %s" % some
		"leader_passing_good": return "after %s" % some
		"leader_passing_bad": return "after %s" % some
		"conflict": return "after %s" % some
		"commemoration": return "to keep the memory of what the tribe went through"
		"craft_teaching": return "as %s" % some
		"birth": return "after %s" % some
		"lineage": return "when %s" % some
		"woodcut": return "after so many trees had been felled"
	return "from what the tribe lived through"


## The most important remembered event not yet commemorated (or -1).
func _commemoration_target() -> int:
	var best := -1
	var bi := 0.75
	for e in lore.living():
		if e.get("commemorated", false):
			continue
		if SimClock.get_day() - int(e["day"]) < int(society.ctx.config.days_per_year * 2.0):
			continue
		if float(e["importance"]) > bi and lore.living_knowers(e, society.ctx.social) >= 3:
			bi = float(e["importance"])
			best = e["id"]
	return best


# ==========================================================================
# Customs over time
# ==========================================================================

func _in_scope(c: Dictionary, vid: int) -> bool:
	var scope := int(c["scope"])
	if scope < 0:
		return true
	var g: Dictionary = society.groups.groups.get(scope, {})
	return not g.is_empty() and g["members"].has(vid)


func _update_customs() -> void:
	var social := society.ctx.social
	var villagers := society.ctx.tribe.villagers
	for c in customs.values():
		if not c["status"] in ACTIVE:
			continue
		var cid: int = c["id"]
		if int(c["scope"]) >= 0 and not society.groups.groups.has(int(c["scope"])):
			_abandon(c, "%s no longer exists as a group" % c["scope_name"])
			continue
		var age_days := SimClock.get_day() - int(c["day"])
		var n := 0
		var yes := 0
		var no := 0
		var young := [0, 0]
		var old := [0, 0]
		for v in villagers:
			var vid := v.villager_id
			var d := devotion_of(vid, cid)
			if v.is_child():
				# Children absorb the customs of their parents.
				var pd := 0.0
				var pn := 0
				for pid in v.parent_ids:
					if social.is_alive(pid):
						pd += devotion_of(pid, cid)
						pn += 1
				if pn > 0:
					d = lerpf(d, pd / pn, 0.15)
				_set_devotion(vid, cid, d)
				continue
			var cv := values_of(v)
			var target := cv.alignment(c["values"]) * 1.6
			if age_days > 6:
				target += 0.35 * cv.get_value(&"tradition")
			# People take up what those close to them keep.
			target += 0.6 * _close_devotion(v, cid)
			var p := v.personality
			# Restless youth push back against what their elders hold dear.
			if v.age_years < society.ctx.config.adult_age + 8.0 and (p.get_trait(&"independence") + p.get_trait(&"curiosity")) > 1.15 \
					and float(c["old"]) > 0.5 and age_days > 8:
				target -= 0.35
			if not _in_scope(c, vid):
				target *= 0.3
			d += (clampf(target, -1.0, 1.0) - d) * 0.08
			_set_devotion(vid, cid, d)
			if d > 0.4:
				for k in c["values"]:
					if float(c["values"][k]) > 0.0:
						_shift(v, k, 0.0012 * float(c["values"][k]), "custom")
			if not _in_scope(c, vid):
				continue
			n += 1
			if d > 0.2:
				yes += 1
			elif d < -0.2:
				no += 1
			var coh := _cohort(v)
			if coh == "young":
				young[0] += 1
				young[1] += 1 if d > 0.2 else 0
			elif coh == "old":
				old[0] += 1
				old[1] += 1 if d > 0.2 else 0
		if n == 0:
			_abandon(c, "no one is left who keeps it")
			continue
		var prev := float(c["support"])
		c["support"] = float(yes) / n
		c["opposition"] = float(no) / n
		c["young"] = float(young[1]) / young[0] if young[0] > 0 else -1.0
		c["old"] = float(old[1]) / old[0] if old[0] > 0 else -1.0
		c["peak"] = maxf(float(c["peak"]), float(c["support"]))
		var hist: Array = c["support_hist"]
		if hist.is_empty() or int(hist.back()[0]) != SimClock.get_day():
			hist.append([SimClock.get_day(), float(c["support"])])
			if hist.size() > 12:
				hist.pop_front()
		if int(c["scope"]) < 0 and c["kind"] in ["hereditary", "elder_council", "no_one_above"] and float(c["support"]) >= 0.3:
			c["last"] = SimClock.get_day()
		_status_step(c, prev, age_days)
		if YEARLY.has(StringName(c["kind"])) and c["status"] in ACTIVE:
			_yearly(c)


func _close_devotion(v: Villager, cid: int) -> float:
	var social := society.ctx.social
	var total := 0.0
	var n := 0
	var close: Array = social.kin_of(v.villager_id)
	close.append_array(social.friends_of(v.villager_id))
	var pid := social.partner_of(v.villager_id)
	if pid >= 0:
		close.append(pid)
		close.append(pid)  # a partner counts double
	for id in close.slice(0, 8):
		if social.is_alive(id):
			total += devotion_of(id, cid)
			n += 1
	return 0.0 if n == 0 else total / n


func _status_step(c: Dictionary, prev: float, age_days: int) -> void:
	var name := "the %s" % String(c["word"]).capitalize()
	var sup := float(c["support"])
	var opp := float(c["opposition"])
	match c["status"]:
		"emerging":
			if sup >= 0.45:
				c["status"] = "established"
				_change("%s has become part of the tribe's way of life (%d%% keep it). %s" % [name.capitalize(), int(sup * 100), _why_support(c)])
			elif age_days > 6 and sup < 0.12:
				_abandon(c, "it never caught on beyond its founders")
				return
		"established":
			if sup >= 0.75 and age_days >= 6:
				c["status"] = "central"
				_change("%s is now central to who the tribe is (%d%% keep it). %s" % [name.capitalize(), int(sup * 100), _why_support(c)])
		"fading":
			if sup >= 0.35:
				c["status"] = "established"
				_change("%s is being taken up again (%d%%). %s" % [name.capitalize(), int(sup * 100), _why_support(c)])
	if c["status"] in ["established", "central"] and opp >= 0.3:
		c["status"] = "contested"
		_change("%s divides the tribe: %d%% keep it, %d%% reject it. %s" % [name.capitalize(), int(sup * 100), int(opp * 100), _who_opposes(c)])
		society.history.add(&"culture", "%s divides the tribe." % name.capitalize(), [])
		_movement(c)
	elif c["status"] == "contested":
		if opp < 0.15:
			c["status"] = "established" if sup >= 0.45 else "fading"
			_change("The quarrel over %s has died down." % name)
		elif society.rng.randf() < 0.35:
			_maybe_reform(c)
	if c["status"] in ["established", "central", "contested"] and sup < 0.2 and age_days > 4:
		c["status"] = "fading"
		_change("%s is fading: only %d%% still keep it (it once had %d%%). %s" % [name.capitalize(), int(sup * 100),
				int(float(c["peak"]) * 100), _why_decline(c)])
	if c["status"] == "fading":
		c["low"] = int(c["low"]) + (1 if sup < 0.1 else 0)
		if int(c["low"]) >= 4:
			_abandon(c, _why_decline(c))
			return
	# Daily practices die out when people stop doing them; customs tied to
	# events (funerals, harvests, hard times) wait for their occasion.
	if c["kind"] in ["evening_fire", "storytelling", "before_expedition"]:
		if SimClock.get_day() - int(c["last"]) > 20 and age_days > 20:
			_abandon(c, "no one has practised it for a long time")


func _why_support(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	var top := ""
	var tv := -INF
	for k in c["values"]:
		var x := tribe_value(k) * float(c["values"][k])
		if x > tv:
			tv = x
			top = k
	if top != "":
		parts.append("It fits the tribe's growing %s (%+.2f)" % [String(CulturalValues.LABELS[StringName(top)]).to_lower(), tribe_value(StringName(top))])
		var cause := _top_cause(StringName(top))
		if cause != "":
			parts.append("because %s" % cause)
	if int(c["practiced"]) > 0:
		parts.append("and has been practised %d times" % int(c["practiced"]))
	if not society.ctx.social.is_alive(int(c["founder"])) and c["founder_name"] != "":
		parts.append("- the legacy of the late %s" % c["founder_name"])
	return " ".join(parts) + "."


func _why_decline(c: Dictionary) -> String:
	var fv: Dictionary = c["founding_values"]
	var worst := ""
	var drop := 0.0
	for k in c["values"]:
		var d := float(fv.get(k, 0.0)) - tribe_value(k)
		if d > drop:
			drop = d
			worst = k
	var bits: PackedStringArray = []
	if worst != "" and drop > 0.05:
		bits.append("%s has weakened in the tribe (%+.2f to %+.2f)" % [CulturalValues.LABELS[StringName(worst)],
				float(fv.get(worst, 0.0)), tribe_value(StringName(worst))])
	var young := float(c["young"])
	var old := float(c["old"])
	if young >= 0.0 and old >= 0.0 and old - young > 0.3:
		bits.append("the young never took to it (%d%% of the young against %d%% of the old)" % [int(young * 100), int(old * 100)])
	if SimClock.get_day() - int(c["last"]) > 8:
		bits.append("it has not been practised for %d days" % (SimClock.get_day() - int(c["last"])))
	return ("Its decline: " + "; ".join(bits) + ".") if not bits.is_empty() else "Fewer and fewer people kept it."


func _who_opposes(c: Dictionary) -> String:
	var young := float(c["young"])
	var old := float(c["old"])
	if young >= 0.0 and old >= 0.0 and old - young > 0.25:
		return "The young increasingly reject it (%d%% of the young keep it, %d%% of the old)." % [int(young * 100), int(old * 100)]
	if young >= 0.0 and old >= 0.0 and young - old > 0.25:
		return "The old resist it while the young embrace it (%d%% of the young, %d%% of the old)." % [int(young * 100), int(old * 100)]
	var gname := _opposing_group(c)
	if gname != "":
		return "Opposition is strongest among %s." % gname
	return "Opinion is split across families and generations."


func _opposing_group(c: Dictionary) -> String:
	var best := ""
	var bv := 0.5
	for g in society.groups.groups.values():
		var members: Array = g["members"]
		if members.size() < 3:
			continue
		var against := 0
		for id in members:
			if devotion_of(id, c["id"]) < -0.2:
				against += 1
		var share := float(against) / members.size()
		if share > bv:
			bv = share
			best = g["name"]
	return best


func _movement(c: Dictionary) -> void:
	var social := society.ctx.social
	var leader := -1
	var best := 0.0
	var members: Array = []
	for v in society.ctx.tribe.villagers:
		if v.is_child() or devotion_of(v.villager_id, c["id"]) > -0.2:
			continue
		members.append(v.villager_id)
		var inf := society.politics.influence(v)
		if inf > best:
			best = inf
			leader = v.villager_id
	if members.size() < 3:
		return
	var young := float(c["young"])
	var old := float(c["old"])
	var who := "the young" if young >= 0.0 and old - young > 0.25 else ("" if _opposing_group(c) == "" else _opposing_group(c))
	var m := {"custom": c["id"], "leader": leader, "members": members, "day": SimClock.get_day(), "who": who, "outcome": ""}
	movements.append(m)
	var text := "%s leads %d people%s who want to change or end the %s." % [social.name_of(leader), members.size(),
			(" among " + who) if who != "" else "", String(c["word"]).capitalize()]
	society.history.add(&"culture", text, members)
	_change(text)


## An innovator reshapes a contested custom to suit its critics.
func _maybe_reform(c: Dictionary) -> void:
	var social := society.ctx.social
	var reformer: Villager = null
	var best := 0.0
	for v in society.ctx.tribe.villagers:
		if not v.is_adult() or not _in_scope(c, v.villager_id):
			continue
		var p := v.personality
		var d := devotion_of(v.villager_id, c["id"])
		var drive := p.get_trait(&"creativity") + p.get_trait(&"curiosity") + value(v, &"curiosity")
		if drive > 1.1 and d > -0.5 and d < 0.6:
			var s := drive * society.politics.influence(v)
			if s > best:
				best = s
				reformer = v
	if reformer == null:
		return
	# The form the critics would accept.
	var crit := CulturalValues.new()
	var nc := 0
	for v in society.ctx.tribe.villagers:
		if not v.is_child() and devotion_of(v.villager_id, c["id"]) < -0.1:
			for k in CulturalValues.VALUES:
				crit.values[k] = crit.get_value(k) + value(v, k)
			nc += 1
	if nc == 0:
		return
	var forms: Array = CustomCatalog.get_kind(StringName(c["kind"]))["forms"]
	var idx := -1
	var bv := -INF
	for i in forms.size():
		if i == int(c["form_idx"]):
			continue
		var a := crit.alignment(forms[i][1])
		if a > bv:
			bv = a
			idx = i
	if idx < 0:
		return
	var old_form: String = c["form"]
	c["form_idx"] = idx
	c["form"] = forms[idx][0]
	c["reforms"].append({"day": SimClock.get_day(), "by": reformer.villager_name, "from": old_form, "to": c["form"]})
	# Critics are won over; the most traditional resent the change.
	var won := 0
	var hurt := 0
	for v in society.ctx.tribe.villagers:
		var d := devotion_of(v.villager_id, c["id"])
		if d < -0.1:
			_set_devotion(v.villager_id, c["id"], d + 0.4)
			won += 1
		elif d > 0.4 and value(v, &"tradition") > 0.25:
			_set_devotion(v.villager_id, c["id"], d - 0.15)
			social.graph.adjust_field(v.villager_id, reformer.villager_id, "affinity", -0.05)
			hurt += 1
	society.politics.add_prestige(reformer, 4.0)
	c["status"] = "established"
	var text := "%s changed the %s: no longer %s, but %s. %d critics came round%s." % [reformer.villager_name,
			String(c["word"]).capitalize(), old_form, c["form"], won, (", while %d traditionalists resented it" % hurt) if hurt > 0 else ""]
	society.history.add(&"culture", text, [reformer.villager_id])
	_change(text)
	for m in movements:
		if m["custom"] == c["id"] and m["outcome"] == "":
			m["outcome"] = "reformed"


func _abandon(c: Dictionary, why: String) -> void:
	c["status"] = "abandoned"
	c["ended"] = SimClock.get_day()
	var text := "The %s has been abandoned: %s" % [String(c["word"]).capitalize(), why.trim_suffix(".") + "."]
	society.history.add(&"culture", text, [])
	_change(text)
	for m in movements:
		if m["custom"] == c["id"] and m["outcome"] == "":
			m["outcome"] = "abandoned"


func _yearly(c: Dictionary) -> void:
	var year := maxf(1.0, society.ctx.config.days_per_year)
	if SimClock.get_day() - int(c["last"]) < year or not active_ceremony().is_empty():
		return
	if float(c["support"]) < 0.25:
		return
	var label := ""
	match c["kind"]:
		"commemoration": label = "%s, remembering %s" % [String(c["word"]).capitalize(), c.get("subject", "the past")]
		"leader_remembrance": label = "%s, remembering %s" % [String(c["word"]).capitalize(), c.get("subject", "a great leader")]
		"ancestor_veneration": label = "%s, the day of the ancestors" % String(c["word"]).capitalize()
	start_ceremony(c, label, _place("hall" if c["kind"] == "commemoration" else "sacred"), CEREMONY_SECONDS)


# ==========================================================================
# Ceremonies
# ==========================================================================

func _place(kind: String) -> Vector3:
	var tribe := society.ctx.tribe
	var prefs := {"fire": [&"gathering_circle"], "sacred": [&"shrine", &"gathering_circle", &"totem", &"memorial_stone"],
		"hall": [&"longhouse", &"gathering_circle", &"shrine"]}
	for id in prefs.get(kind, []):
		for b in tribe.buildings:
			if b.def.id == id and b.is_complete:
				return b.global_position
	return tribe.campfire.global_position if tribe.campfire != null else tribe.center


## A real gathering: people who keep the custom walk there; those who
## reject it stay away.
func start_ceremony(custom: Dictionary, name: String, pos: Vector3, seconds: float, subjects: Array = []) -> void:
	var cid := int(custom.get("id", -1))
	var c := {"kind": String(custom.get("kind", "ceremony")), "custom": cid, "name": name, "pos": pos,
		"until": SimClock.sim_time + seconds, "attendees": [], "subjects": subjects.duplicate(), "boycott": []}
	ceremonies.append(c)
	if cid >= 0:
		customs[cid]["practiced"] = int(customs[cid]["practiced"]) + 1
		customs[cid]["last"] = SimClock.get_day()
	var first := cid >= 0 and int(customs[cid]["practiced"]) <= 1
	if first or int(customs.get(cid, {}).get("practiced", 0)) % 4 == 0 or not subjects.is_empty():
		society.history.add(&"culture", "The tribe gathers for the %s." % name, subjects)
	var social := society.ctx.social
	for v in society.ctx.tribe.villagers:
		var d := devotion_of(v.villager_id, cid) if cid >= 0 else 0.3
		var close := false
		for sid in subjects:
			if sid == v.villager_id or social.graph.is_kin(v.villager_id, sid) or social.graph.has_tag(v.villager_id, sid, &"friend"):
				close = true
		if d < -0.25 and not close:
			c["boycott"].append(v.villager_id)
			continue
		if cid >= 0 and not _in_scope(customs[cid], v.villager_id) and not close:
			continue
		var w := 0.3 + 0.5 * maxf(0.0, d) + 0.2 * maxf(0.0, value(v, &"spirituality")) + (0.4 if close else 0.0)
		v.brain.suggest(&"ceremony", w, seconds, "Attending the %s" % name)


func is_active(c: Dictionary) -> bool:
	return ceremonies.has(c) and SimClock.sim_time < float(c["until"])


func active_ceremony() -> Dictionary:
	for c in ceremonies:
		if SimClock.sim_time < float(c["until"]):
			return c
	return {}


func attend(c: Dictionary, v: Villager) -> void:
	if not c["attendees"].has(v.villager_id):
		c["attendees"].append(v.villager_id)


func _close_ceremonies() -> void:
	var social := society.ctx.social
	for c in ceremonies.duplicate():
		if SimClock.sim_time < float(c["until"]):
			continue
		ceremonies.erase(c)
		var who: Array = c["attendees"]
		var cid := int(c["custom"])
		var custom: Dictionary = customs.get(cid, {})
		for id in who:
			var v := social.get_villager(id)
			if v == null:
				continue
			social.remember(v, &"feast" if c["kind"] in ["harvest_feast", "partnership_feast"] else &"ceremony", -1, -1, -1, c["name"])
			for other in who:
				if other != id:
					social.graph.adjust_opinion(id, other, 0.03, 0.01)
			if cid >= 0:
				_set_devotion(id, cid, devotion_of(id, cid) + 0.08)
				for k in custom.get("values", {}):
					if float(custom["values"][k]) > 0.0:
						_shift(v, k, 0.008 * float(custom["values"][k]), "ceremony")
			_ceremony_effect(c, v)
		if not custom.is_empty():
			_ceremony_after(c, custom, who)
		if who.size() >= 3 and (int(custom.get("practiced", 0)) <= 1 or not c["subjects"].is_empty()):
			var boycott: Array = c["boycott"]
			society.history.add(&"culture", "%d people took part in the %s%s." % [who.size(), c["name"],
					(", %d stayed away" % boycott.size()) if boycott.size() >= 2 else ""], who)


func _ceremony_effect(c: Dictionary, v: Villager) -> void:
	var p := v.personality
	match c["kind"]:
		"funeral_rites", "ancestor_veneration":
			v.emotions.values[&"grief"] = v.emotions.get_value(&"grief") * 0.7
			v.emotions.feel(&"hope", 0.15, "Found comfort in the %s" % c["name"], p)
		"harvest_feast", "partnership_feast":
			v.emotions.feel(&"happiness", 0.4, "Celebrated the %s" % c["name"], p)
		"first_fruits":
			v.emotions.feel(&"satisfaction", 0.25, "Gave thanks at the %s" % c["name"], p)
		"commemoration", "leader_remembrance":
			v.emotions.feel(&"pride", 0.2, "Remembered together at the %s" % c["name"], p)
		"coming_of_age_trial", "coming_of_age_teaching", "vows":
			v.emotions.feel(&"happiness", 0.2, "Witnessed the %s" % c["name"], p)


func _ceremony_after(c: Dictionary, custom: Dictionary, who: Array) -> void:
	var social := society.ctx.social
	var subjects: Array = c["subjects"]
	match custom["kind"]:
		"partnership_feast", "vows":
			if subjects.size() == 2:
				var a: int = subjects[0]
				var b: int = subjects[1]
				for pair in [[a, b], [b, a]]:
					social.graph.set_field(pair[0], pair[1], "resentment", 0.0)
				for id in who:
					for s in subjects:
						if id != s:
							social.graph.adjust_opinion(id, s, 0.04, 0.02)
				if custom["kind"] == "vows":
					vowed[Vector2i(mini(a, b), maxi(a, b))] = SimClock.get_day()
		"coming_of_age_trial":
			for sid in subjects:
				var y := social.get_villager(sid)
				if y != null:
					y.emotions.feel(&"courage", 0.5, "Passed the %s" % String(custom["word"]).capitalize(), y.personality)
					y.emotions.values[&"fear"] = 0.0
					society.politics.add_prestige(y, 5.0)
					_shift(y, &"courage", 0.08, "ceremony")
					y.brain.suggest(&"explore", 0.5, society.ctx.config.day_length_seconds * 0.3, "The trial: a journey alone")
		"coming_of_age_teaching":
			for sid in subjects:
				var y := social.get_villager(sid)
				if y == null:
					continue
				var skill := y.skills.best()
				var master: Villager = null
				for v in society.ctx.tribe.villagers:
					if v != y and v.is_adult() and (master == null or v.skills.get_level(skill) > master.skills.get_level(skill)):
						master = v
				if master != null and master.skills.get_level(skill) > y.skills.get_level(skill):
					y.skills.learn_from(skill, master.skills.get_level(skill), 0.15, y.personality)
					social.graph.set_tag(master.villager_id, y.villager_id, &"mentor", true)
					social.remember(y, &"was_taught", master.villager_id, -1, -1, String(skill))
		"commemoration":
			var e: Dictionary = lore.entries.get(int(custom.get("lore", -1)), {})
			if not e.is_empty():
				# Everyone present hears the story - as the most respected teller tells it.
				var teller := -1
				for id in who:
					if lore.knows(e, id):
						teller = id
						break
				var d := lore.distortion_of(e, teller) if teller >= 0 else 1
				for id in who:
					var v := social.get_villager(id)
					if v != null and not lore.knows(e, id):
						lore.learn(e, id, d + (1 if society.rng.randf() < 0.15 else 0), lore.valence_for(e, values_of(v)))
					if v != null:
						for k in e["values"]:
							_shift(v, k, 0.006 * float(e["values"][k]), "stories")
				e["retold"] = int(e["retold"]) + 1
		"leader_remembrance":
			var leader := social.get_villager(society.politics.primary_leader())
			if leader != null:
				society.politics.add_prestige(leader, 2.0)
	# Devoted attendees think less of adults who stayed away from a central custom.
	if custom["status"] == "central":
		for vid in c["boycott"]:
			for id in who:
				if devotion_of(id, custom["id"]) > 0.5:
					social.graph.adjust_field(id, vid, "respect", -0.02)
			violations.append([vid, SimClock.get_day(), "stayed away from the %s" % String(custom["word"]).capitalize()])
		if violations.size() > 20:
			violations = violations.slice(violations.size() - 20)


# ==========================================================================
# Transmission between generations
# ==========================================================================

func _enculturate() -> void:
	var social := society.ctx.social
	var tribe := society.ctx.tribe
	var leader := social.get_villager(society.politics.primary_leader())
	var elders: Array = []
	for v in tribe.villagers:
		if v.life_stage() == &"elder":
			elders.append(v)
	for v in tribe.villagers:
		var stage := v.life_stage()
		var rate: float = {&"child": 0.05, &"youth": 0.03, &"adult": 0.008, &"elder": 0.003}.get(stage, 0.008)
		rate *= lerpf(1.2, 0.6, v.personality.get_trait(&"independence"))
		var models: Array = []  # [values dict, weight, cause]
		for pid in v.parent_ids:
			var parent := social.get_villager(pid)
			if parent != null:
				models.append([values_of(parent).values, 3.0 if stage == &"child" else (1.5 if stage == &"youth" else 0.4), "teaching"])
			elif legacies.has(pid):
				models.append([CulturalValues.from_array(legacies[pid]["values"]).values, 1.0, "legacy"])
		for mid in social.graph.with_tag(v.villager_id, &"mentor"):
			var m := social.get_villager(mid)
			if m != null and m.age_years > v.age_years:
				models.append([values_of(m).values, 2.0, "teaching"])
		var friends := social.friends_of(v.villager_id)
		for i in mini(2, friends.size()):
			var f := social.get_villager(friends[i])
			if f != null:
				models.append([values_of(f).values, 1.0, "teaching"])
		if leader != null and leader != v:
			models.append([values_of(leader).values, 0.6 + maxf(0.0, tribe_value(&"hierarchy")) * 2.0, "teaching"])
		if not elders.is_empty() and tribe_value(&"elders") > 0.1 and stage != &"elder":
			var e: Villager = elders[(v.villager_id + int(SimClock.sim_time)) % elders.size()]
			models.append([values_of(e).values, tribe_value(&"elders") * 2.5, "teaching"])
		for lid in legacies:
			if social.graph.affinity(v.villager_id, lid) > 0.3 and not v.parent_ids.has(lid):
				models.append([CulturalValues.from_array(legacies[lid]["values"]).values, 0.5, "legacy"])
		if models.is_empty():
			continue
		var target := {}
		var wsum := 0.0
		var legacy_w := 0.0
		for m in models:
			wsum += float(m[1])
			if m[2] == "legacy":
				legacy_w += float(m[1])
			for k in CulturalValues.VALUES:
				target[k] = float(target.get(k, 0.0)) + float(m[0].get(k, 0.0)) * float(m[1])
		for k in target:
			target[k] /= wsum
		var cv := values_of(v)
		var before := cv.values.duplicate()
		cv.learn_toward(target, rate)
		for k in CulturalValues.VALUES:
			var d := float(cv.values[k]) - float(before[k])
			if absf(d) > 0.0005:
				var cause := "legacy" if legacy_w > wsum * 0.4 else "teaching"
				var led: Dictionary = causes.get(k, {})
				led[cause] = float(led.get(cause, 0.0)) + d
				causes[k] = led
		# Some young people reject what their elders hold most dear.
		if stage == &"youth" or (stage == &"adult" and v.age_years < society.ctx.config.adult_age + 8.0):
			var reb := (v.personality.get_trait(&"independence") + v.personality.get_trait(&"curiosity")) * 0.5 - 0.55
			if reb > 0.0 and society.rng.randf() < reb * 1.5:
				var strongest := ""
				var sv := 0.25
				for k in CulturalValues.VALUES:
					if float(target[k]) > sv:
						sv = float(target[k])
						strongest = k
				if strongest != "":
					_shift(v, StringName(strongest), -0.03, "youth")
					_shift(v, &"curiosity", 0.01, "youth")


## Beliefs follow what people spend their days doing, and age.
func _work_drift() -> void:
	for v in society.ctx.tribe.villagers:
		if v.is_child():
			continue
		var s := v.skills
		var land := s.recent_share(&"foraging") + s.recent_share(&"farming") + s.recent_share(&"fishing")
		var craft := s.recent_share(&"toolmaking") + s.recent_share(&"building") + s.recent_share(&"stonework") + s.recent_share(&"woodcutting") * 0.5
		if land > 0.45:
			_shift(v, &"nature", 0.0015 * land, "work_land")
		if craft > 0.45:
			_shift(v, &"craftsmanship", 0.0015 * craft, "work_craft")
		if v.life_stage() == &"elder":
			_shift(v, &"tradition", 0.002, "age")
		# Beliefs that are not fed by experience slowly lose their hold.
		var cv := values_of(v)
		for k in CulturalValues.VALUES:
			cv.values[k] = float(cv.values[k]) * 0.996
		# Stories one knows keep their values alive.
		if (v.villager_id + _phase) % 4 == 0:
			for e in lore.known_by(v.villager_id):
				var val := float(e["knowers"][v.villager_id][1])
				if absf(val) > 0.3:
					for k in e["values"]:
						_shift(v, k, 0.002 * signf(val) * float(e["values"][k]), "stories")


# ==========================================================================
# The tribe's values, generations and explanations
# ==========================================================================

func _update_tribe_values() -> void:
	var sums := {}
	var total := 0.0
	var co := {"young": {}, "old": {}}
	var cn := {"young": 0, "old": 0}
	for k in CulturalValues.VALUES:
		sums[k] = 0.0
		co["young"][k] = 0.0
		co["old"][k] = 0.0
	for v in society.ctx.tribe.villagers:
		if v.is_child():
			continue
		var w := society.politics.influence(v) * (0.3 if v.life_stage() == &"youth" else 1.0)
		total += w
		var cv := values_of(v)
		var c := _cohort(v)
		if c != "":
			cn[c] += 1
		for k in CulturalValues.VALUES:
			sums[k] += cv.get_value(k) * w
			if c != "":
				co[c][k] += cv.get_value(k)
	if total <= 0.0:
		return
	for k in CulturalValues.VALUES:
		tribe_values[k] = sums[k] / total
		for c in ["young", "old"]:
			cohort_values[c][k] = co[c][k] / cn[c] if cn[c] > 0 else 0.0
	cohort_values["n_young"] = cn["young"]
	cohort_values["n_old"] = cn["old"]
	var day := SimClock.get_day()
	if day != _last_snapshot_day:
		_last_snapshot_day = day
		snapshots.append({"day": day, "values": tribe_values.duplicate()})
		if snapshots.size() > 60:
			snapshots.pop_front()
	_announce_values()


func _announce_values() -> void:
	for k in CulturalValues.VALUES:
		var x := tribe_value(k)
		var level := 2 if x >= 0.5 else (1 if x >= 0.25 else (-1 if x <= -0.25 else 0))
		var prev := int(core_levels.get(k, 0))
		if level == prev:
			continue
		# Hysteresis: only announce clear changes.
		if level < prev and ((prev == 2 and x >= 0.42) or (prev == 1 and x >= 0.18)):
			continue
		if level > prev and prev == -1 and x <= -0.18:
			continue
		core_levels[k] = level
		var label: String = CulturalValues.LABELS[k]
		var text := ""
		match level:
			2: text = "%s has become one of the tribe's deepest values (%+.2f)." % [label, x]
			1: text = "%s is becoming a shared value of the tribe (%+.2f)." % [label, x] if prev < 1 else "%s matters less than it did (%+.2f)." % [label, x]
			0: text = "%s no longer unites the tribe as it did (%+.2f)." % [label, x] if prev > 0 else "The tribe's distrust of %s has eased (%+.2f)." % [label.to_lower(), x]
			-1: text = "The tribe has turned against %s (%+.2f)." % [label.to_lower(), x]
		var why := explain_value(k)
		_change(text + " " + why)
		if level >= 1:
			_coin_value_word(k)


func _top_cause(k: StringName, ledger: Dictionary = {}) -> String:
	var led: Dictionary = ledger.get(k, {}) if not ledger.is_empty() else causes.get(k, {})
	var x := tribe_value(k) if ledger.is_empty() else 1.0
	var best := ""
	var bv := 0.0
	for cause in led:
		var w := float(led[cause]) * signf(x if x != 0.0 else 1.0)
		if w > bv:
			bv = w
			best = cause
	return CAUSES.get(best, best) if best != "" else ""


## Why a value is where it is, from the recorded causes.
func explain_value(k: StringName) -> String:
	var led: Dictionary = causes.get(k, {})
	var x := tribe_value(k)
	var list := []
	for cause in led:
		var w := float(led[cause]) * (1.0 if x >= 0.0 else -1.0)
		if w > 0.0:
			list.append([cause, w])
	list.sort_custom(func(a, b): return a[1] > b[1])
	var parts: PackedStringArray = []
	for item in list.slice(0, 3):
		var n := int(cause_counts.get(item[0], 0))
		var phrase: String = CAUSES.get(item[0], item[0])
		parts.append(phrase + (" (%d times)" % n if n > 1 and not item[0] in ["teaching", "legacy", "custom", "stories", "age", "work_land", "work_craft"] else ""))
	if parts.is_empty():
		return ""
	return "Mostly because " + ", ".join(parts) + "."


## Change in a tribe value over the last `days` days.
func trend(k: StringName, days: int = 6) -> float:
	if snapshots.is_empty():
		return 0.0
	var day := SimClock.get_day()
	for s in snapshots:
		if int(s["day"]) >= day - days:
			return tribe_value(k) - float(s["values"].get(k, 0.0))
	return 0.0


func _generational() -> void:
	if int(cohort_values.get("n_young", 0)) < 2 or int(cohort_values.get("n_old", 0)) < 2:
		return
	for k in CulturalValues.VALUES:
		var d := float(cohort_values["young"][k]) - float(cohort_values["old"][k])
		if absf(d) < 0.25:
			continue
		if SimClock.get_day() - int(divides.get(k, -100)) < 12:
			continue
		divides[k] = SimClock.get_day()
		var label: String = String(CulturalValues.LABELS[k]).to_lower()
		var side := "young" if d > 0.0 else "old"
		var why := _top_cause(k, cohort_causes[side])
		var text := ("The young value %s far more than their elders (%+.2f vs %+.2f)" if d > 0.0
				else "The young are turning away from the %s their elders hold dear (%+.2f vs %+.2f)") % [
				label, float(cohort_values["young"][k]), float(cohort_values["old"][k])]
		text += (", mostly because %s." % why) if why != "" else "."
		society.history.add(&"culture", text, [])
		_change(text)


func _decay_causes() -> void:
	for led in [causes, cohort_causes["young"], cohort_causes["old"]]:
		for k in led:
			for cause in led[k]:
				led[k][cause] = float(led[k][cause]) * 0.985


func _change(text: String) -> void:
	changes.append({"day": SimClock.get_day(), "text": text})
	if changes.size() > 80:
		changes.pop_front()


# ==========================================================================
# Lore
# ==========================================================================

func _add_lore(kind: String, actors: Array, names: Array, vals: Dictionary, importance: float, details: Dictionary) -> Dictionary:
	var knowers: Array = []
	for v in society.ctx.tribe.villagers:
		if not v.is_child() or actors.has(v.villager_id):
			knowers.append(v)
	var e := lore.add(kind, actors, names, vals, importance, knowers, details)
	for v in knowers:
		lore.learn(e, v.villager_id, 0, lore.valence_for(e, values_of(v)))
	if importance >= 0.7 and language.size() >= 3:
		var roots: Array = LoreBook.KINDS[kind][1]
		e["word"] = language.coin(StringName("lore_%d" % e["id"]), "%s-%s" % [TribalLanguage.GLOSS.get(roots[0], ""), TribalLanguage.GLOSS.get(roots[1], "")], roots)
	if importance >= 0.75:
		observe("commemoration", [], "")
	return e


func _lore_once(key: String, kind: String, actors: Array, names: Array, vals: Dictionary, importance: float, details: Dictionary) -> void:
	if _firsts.has(key):
		return
	_firsts[key] = true
	_add_lore(kind, actors, names, vals, importance, details)


func _update_lore() -> void:
	var social := society.ctx.social
	var lost_titles: PackedStringArray = []
	for e in lore.living():
		if lore.living_knowers(e, social) == 0:
			e["lost"] = true
			lore.forgotten += 1
			if float(e["importance"]) >= 0.6:
				lost_titles.append(lore.title(e, 1, social))
	if not lost_titles.is_empty():
		var text := "No one alive remembers %s any more." % (", ".join(lost_titles.slice(0, lost_titles.size() - 1)) + " or " + lost_titles[-1]
				if lost_titles.size() > 1 else lost_titles[0])
		society.history.add(&"culture", text, [])
		_change(text)
	# Famines end and become stories, told according to how they were survived.
	if not famine.is_empty():
		var tribe := society.ctx.tribe
		if tribe.stockpile.get_amount(ResourceType.FOOD) > tribe.population() * 5:
			var help := int(counters.get("help", 0)) - int(famine["help0"])
			var refused := int(counters.get("refusals", 0)) - int(famine["ref0"])
			var how := "The tribe shared what little it had."
			var how2 := "they shared everything"
			var vals := {&"cooperation": 0.8, &"generosity": 0.8}
			if strength(&"strict_rationing") > 0.3:
				how = "Every share was counted and guarded."
				how2 = "every share was guarded"
				vals = {&"hierarchy": 0.8, &"tradition": 0.4}
			elif refused > help:
				how = "Each had to fend for themselves."
				how2 = "each fended for themselves"
				vals = {&"independence": 0.9}
			var hungry: Dictionary = famine["hungry"]
			if hungry.size() >= 3:
				_add_lore("famine", [], [], vals, 0.6 + 0.05 * hungry.size(), {"n": hungry.size(), "x": how, "x2": how2})
			famine = {}


# ==========================================================================
# Language
# ==========================================================================

const VALUE_ROOTS := {
	&"cooperation": [&"together", &"hand"], &"independence": [&"free", &"path"], &"elders": [&"elder", &"honor"],
	&"courage": [&"brave", &"heart"], &"generosity": [&"gift", &"hand"], &"loyalty": [&"blood", &"word"],
	&"family": [&"blood", &"home"], &"achievement": [&"strong", &"mark"], &"equality": [&"equal", &"people"],
	&"hierarchy": [&"chief", &"path"], &"hospitality": [&"home", &"gift"], &"tradition": [&"old", &"path"],
	&"curiosity": [&"seek", &"new"], &"spirituality": [&"spirit", &"light"], &"nature": [&"earth", &"heart"],
	&"strength": [&"strong", &"hand"], &"craftsmanship": [&"make", &"hand"], &"knowledge": [&"wise", &"word"],
}


func _coin(concept: StringName, gloss: String, parts: Array, text: String) -> void:
	if language.knows(concept):
		return
	var w := language.coin(concept, gloss, parts)
	var t := text % w.capitalize()
	society.history.add(&"culture", t, [])
	_change(t)


func _coin_value_word(k: StringName) -> void:
	var concept := StringName("value_" + String(k))
	if language.knows(concept):
		return
	var roots: Array = VALUE_ROOTS[k]
	var label: String = String(CulturalValues.LABELS[k]).to_lower()
	_coin(concept, label, roots, "The tribe now has a word for %s: %%s." % label)


func _language_step() -> void:
	var tribe := society.ctx.tribe
	# Naming the world: as stories accumulate, places get names.
	if lore.living().size() >= 2:
		_coin(&"lake", "the lake", [], "The lake has a name now: %s.")
		_coin(&"valley", "the valley", [&"valley", &"home"], "The people now call their valley %s.")
	if language.size() >= 6:
		_coin(&"mountain", "the mountains", [&"mountain", &"guard"], "The ring of mountains is called %s, the keepers.")
	# A people names itself once it shares a home, a custom and a story.
	if not language.knows(&"people") and _firsts.has("first_building") and live_count() >= 1 and core_levels.size() >= 1:
		var top := ""
		var tv := 0.0
		for k in CulturalValues.VALUES:
			if tribe_value(k) > tv:
				tv = tribe_value(k)
				top = k
		var root2: StringName = VALUE_ROOTS[StringName(top)][0] if top != "" else &"home"
		var meaning: String = String(CulturalValues.LABELS[StringName(top)]).to_lower() if top != "" else "the valley"
		var w := language.coin(&"people", "people of %s" % meaning, [&"people", root2])
		var old_name: String = tribe.tribe_name
		tribe.tribe_name = "The %s" % w.capitalize()
		var t := "%s now call themselves the %s - \"%s\"." % [old_name, w.capitalize(), language.lexicon[&"people"]["gloss"]]
		society.history.add(&"culture", t, [])
		_change(t)
	if tribe_value(&"elders") >= 0.25:
		_coin(&"elder", "elder", [], "Elders are now addressed with a title of respect: %s.")


# ==========================================================================
# Art and architecture
# ==========================================================================

func _update_art() -> void:
	var a := aesthetics
	var tribe := society.ctx.tribe
	var tech := society.tech
	var social := society.ctx.social
	var best_skill := func(k: StringName) -> float:
		var b := 0.0
		for v in tribe.villagers:
			b = maxf(b, v.skills.get_level(k))
		return b
	var gained: Array = []
	if best_skill.call(&"stonework") >= 35.0 and a.add_pigment("ochre"):
		gained.append("ochre")
	if (has_tradition(&"evening_fire") or has_tradition(&"funeral_rites")) and a.add_pigment("charcoal"):
		gained.append("charcoal")
	if best_skill.call(&"foraging") >= 40.0 and a.add_pigment("berry"):
		gained.append("berry")
	if tech.tribe_knows(&"herbalism") and a.add_pigment("leaf"):
		gained.append("leaf")
	if tech.tribe_knows(&"fishing") and best_skill.call(&"fishing") >= 25.0 and a.add_pigment("clay"):
		gained.append("clay")
	if society.politics._has(&"shrine") and a.add_pigment("chalk"):
		gained.append("chalk")
	if tech.tribe_knows(&"agriculture") and society.politics._has(&"farm") and a.add_pigment("saffron"):
		gained.append("saffron")
	for g in gained:
		var t := "The tribe has found a new colour: %s." % TribalAesthetics.PIGMENTS[g][1]
		_change(t)
		if a.art_level >= 1:
			society.history.add(&"culture", t, [])
	var ceremonial := 0
	for c in customs.values():
		if c["status"] in ["established", "central", "contested"] and CustomCatalog.get_kind(StringName(c["kind"]))["ceremony"] != "":
			ceremonial += 1
	var day := SimClock.get_day()
	var pop := tribe.population()
	if a.art_level == 0 and ceremonial >= 1 and not a.palette.is_empty():
		a.art_level = 1
		a.art_days[1] = day
		a.motif = a.choose_motif(tribe_values)
		a.motif_reason = _motif_reason(a.motif)
		var t := "Those who keep the tribe's customs have begun to paint themselves with %s %s and wear coloured sashes. %s" % [
				a.color_name(0), a.motif, a.motif_reason]
		society.history.add(&"culture", t, [])
		_change(t)
	elif a.art_level == 1 and pop >= 10 and day - int(a.art_days.get(1, day)) >= 3 \
			and (tribe_value(&"craftsmanship") > 0.12 or tech.tribe_knows(&"toolmaking")):
		a.art_level = 2
		a.art_days[2] = day
		a.new_era("painted walls", "Homes are painted with the tribe's %s since %s." % [a.motif,
				"its people came to value fine work" if tribe_value(&"craftsmanship") > 0.12 else "tools made finer work possible"], false)
		var t := "Homes are now painted: bands of %s with %s. New homes will be built in this style." % [a.color_name(0), a.motif]
		society.history.add(&"culture", t, [])
		_change(t)
		_restyle_all(false)
	elif a.art_level == 2 and pop >= 12 and day - int(a.art_days.get(2, day)) >= 3 \
			and (tech.tribe_knows(&"carpentry") or best_skill.call(&"woodcutting") >= 60.0 or best_skill.call(&"stonework") >= 60.0):
		a.art_level = 3
		a.art_days[3] = day
		var t := "The tribe has begun to carve: totems, posts and memorial stones become possible."
		society.history.add(&"culture", t, [])
		_change(t)
	# A motif can change when the tribe's values have moved far from it.
	if a.art_level >= 1 and day % 8 == 0:
		var m := a.choose_motif(tribe_values)
		if m != a.motif and _motif_score(m) > _motif_score(a.motif) + 0.2:
			var old := a.motif
			a.motif = m
			a.motif_reason = _motif_reason(m)
			var t := "The old %s are giving way to %s in the tribe's art. %s" % [old, m, a.motif_reason]
			society.history.add(&"culture", t, [])
			_change(t)


func _motif_score(m: String) -> float:
	var s := 0.0
	for k in TribalAesthetics.MOTIFS.get(m, []):
		s += tribe_value(k)
	return s / maxf(1.0, TribalAesthetics.MOTIFS.get(m, []).size())


func _motif_reason(m: String) -> String:
	var vals: Array = TribalAesthetics.MOTIFS[m]
	var names: PackedStringArray = []
	for k in vals:
		if tribe_value(k) > 0.05:
			names.append("%s %+.2f" % [String(CulturalValues.LABELS[k]).to_lower(), tribe_value(k)])
	return "The %s express what the tribe values (%s)." % [m, ", ".join(names) if not names.is_empty() else "its beliefs"]


## A new technique offers a new way of building; builders adopt or reject it.
func _consider_new_style(tech: StringName) -> void:
	if aesthetics.art_level < 2 or not TribalAesthetics.ERA_TECHS.has(tech):
		return
	var name: String = TribalAesthetics.ERA_TECHS[tech]
	for e in aesthetics.eras:
		if e["name"] == name:
			return
	_vote_style(tech, name)


func _vote_style(tech: StringName, name: String) -> void:
	var yes := 0.0
	var no := 0.0
	var young_yes := 0
	var old_no := 0
	for v in society.ctx.tribe.villagers:
		if not v.is_adult() or v.skills.get_level(&"building") < 15.0:
			continue
		var w := society.politics.influence(v) * (0.5 + v.skills.get_level(&"building") / 100.0)
		var lean := value(v, &"curiosity") - value(v, &"tradition") + (0.2 if v.age_years < 35.0 else -0.15) \
				+ (0.25 if society.tech.knows(v, tech) else 0.0)
		if lean > 0.0:
			yes += w
			if v.age_years < 35.0:
				young_yes += 1
		else:
			no += w
			if v.age_years >= 45.0:
				old_no += 1
	if yes + no <= 0.0:
		return
	var text := ""
	if yes > no:
		aesthetics.new_era(name, "Builders adopted %s after the tribe learned %s." % [name, String(tech)], tech == &"toolmaking")
		text = "A new way of building: %s. %d young builders embraced it%s; homes built from now on will look different." % [
				name, young_yes, (", over the objections of %d older builders who favoured the old ways" % old_no) if old_no > 0 else ""]
	else:
		aesthetics.rejected_styles[tech] = SimClock.get_day()
		text = "Some builders wanted %s, but the older builders' traditional ways prevailed (%d%% of builders' weight against)." % [
				name, int(no / (yes + no) * 100.0)]
	society.history.add(&"culture", text, [])
	_change(text)


func _retry_styles() -> void:
	for tech in aesthetics.rejected_styles.keys():
		if SimClock.get_day() - int(aesthetics.rejected_styles[tech]) >= 10:
			aesthetics.rejected_styles.erase(tech)
			_consider_new_style(tech)
			return


func _style_building(b: Building) -> void:
	var st := aesthetics.style()
	if b.def.is_campfire or b.def.is_storage or b.def.id == &"farm":
		return
	if not st.is_empty() or b.def.id in [&"totem", &"memorial_stone", &"gathering_circle"]:
		b.apply_culture_style(aesthetics.era_index(), _style_colors(st))


func _style_colors(st: Dictionary) -> Dictionary:
	var a := aesthetics
	var band: String = st.get("band", a.color_name(0))
	var accent: String = st.get("accent", a.color_name(1))
	return {"band": TribalAesthetics.PIGMENTS[band][0] if TribalAesthetics.PIGMENTS.has(band) else a.color(0),
		"accent": TribalAesthetics.PIGMENTS[accent][0] if TribalAesthetics.PIGMENTS.has(accent) else a.color(1),
		"motif": st.get("motif", a.motif), "posts": bool(st.get("posts", false)), "timber": bool(st.get("timber", false))}


## When decoration first appears, people repaint their existing homes too
## (`all`), otherwise buildings keep the style of the era they were built in.
func _restyle_all(all: bool) -> void:
	for b in society.ctx.tribe.buildings:
		if b.is_complete and (all or b.style_era < 0):
			_style_building(b)


func restyle_from_save() -> void:
	for b in society.ctx.tribe.buildings:
		if b.style_era >= 0 and b.style_era < aesthetics.eras.size():
			b.apply_culture_style(b.style_era, _style_colors(aesthetics.eras[b.style_era]))
		elif b.def.id in [&"totem", &"memorial_stone", &"gathering_circle"]:
			b.apply_culture_style(-1, _style_colors({}))


## What each villager wears: the colour of the custom they hold dearest.
func _update_adornments() -> void:
	var a := aesthetics
	for v in society.ctx.tribe.villagers:
		var spec := {}
		if a.art_level >= 1 and not v.is_child():
			var best := -1
			var bd := 0.45
			for c in customs.values():
				if c["status"] in ACTIVE:
					var d := devotion_of(v.villager_id, c["id"])
					if d > bd:
						bd = d
						best = c["id"]
			if best >= 0:
				spec["sash"] = a.color(int(customs[best]["color"]))
			if (v.life_stage() == &"elder" and tribe_value(&"elders") > 0.2) or society.politics.is_leader(v):
				spec["band"] = a.color(1 if a.palette.size() > 1 else 0)
			for g in society.groups.groups_of(v.villager_id):
				if g["kind"] == "guild":
					spec["belt"] = a.color(2 + int(g["id"]))
		v.set_adornment(spec)


# ==========================================================================
# Monuments and gathering places (as community projects)
# ==========================================================================

func add_concerns(v: Villager, out: Array) -> void:
	var tribe := society.ctx.tribe
	var props := society.proposals
	var ceremonial := 0
	for c in customs.values():
		if c["status"] in ["established", "central", "contested"] and CustomCatalog.get_kind(StringName(c["kind"]))["ceremony"] != "":
			ceremonial += 1
	if ceremonial >= 2 and tribe.population() >= 10 and props._count(&"gathering_circle") == 0:
		var urg := 0.3 + 0.4 * maxf(0.0, value(v, &"tradition") + value(v, &"spirituality")) * 0.5 + 0.2 * maxf(0.0, value(v, &"cooperation"))
		out.append([&"gathering_circle", "building", urg, "Our ceremonies have outgrown the campfire - we need a proper gathering place."])
	if aesthetics.art_level >= 3 and props._count(&"totem") == 0 and (value(v, &"spirituality") > 0.1 or value(v, &"tradition") > 0.15):
		out.append([&"totem", "building", 0.3 + 0.4 * maxf(0.0, value(v, &"spirituality")),
				"A totem carved with our %s would show who we are." % aesthetics.motif])
	if aesthetics.art_level >= 2 and society.ctx.tribe.population() >= 10:
		var best := -1
		var bv := 0.3
		for e in lore.known_by(v.villager_id):
			if e["kind"] != "passing" or e.get("monument", false):
				continue
			var val := float(e["knowers"][v.villager_id][1]) + float(e["importance"]) * 0.5
			if val > bv:
				bv = val
				best = e["id"]
		if best >= 0 and props._count(&"memorial_stone") == 0:
			var e2: Dictionary = lore.entries[best]
			out.append([&"memorial_stone", "building", 0.25 + 0.3 * maxf(0.0, value(v, &"elders") + value(v, &"loyalty")),
					"We should raise a stone for %s." % (e2["names"][0] if not e2["names"].is_empty() else "the ancestors"), best])


func on_monument_planned(type: StringName, subject: int) -> void:
	if type == &"memorial_stone" and lore.entries.has(subject):
		lore.entries[subject]["monument"] = true


# ==========================================================================
# Conversations about culture
# ==========================================================================

const TOPICS := [&"tell_story", &"teach_custom", &"debate_custom", &"rebuke", &"pass_on_values"]


func handles(topic: StringName) -> bool:
	return TOPICS.has(topic)


func add_topics(s: Villager, l: Villager, w: Dictionary, data: Dictionary) -> void:
	var social := society.ctx.social
	if s.is_child():
		return
	# Stories: the elders, the knowledgeable and the storytellers tell them.
	var story := -1
	var simp := 0.0
	for e in lore.known_by(s.villager_id):
		if not lore.knows(e, l.villager_id) and float(e["importance"]) > simp:
			simp = float(e["importance"])
			story = e["id"]
	if story >= 0:
		data["lore"] = story
		var st := custom_of_kind(&"storytelling")
		# Elders and parents tell the young what happened before they were born.
		var family := 0.8 if l.parent_ids.has(s.villager_id) or social.graph.is_kin(s.villager_id, l.villager_id) else 0.0
		w[&"tell_story"] = 0.4 + (0.8 if s.life_stage() == &"elder" else 0.0) + 0.6 * maxf(0.0, value(s, &"knowledge")) \
				+ 0.5 * maxf(0.0, value(s, &"tradition")) + (1.2 * maxf(0.0, devotion_of(s.villager_id, st["id"])) if not st.is_empty() else 0.0) \
				+ (1.0 if not l.is_adult() else 0.0) + family
	# Passing on beliefs to the young.
	if not l.is_adult() and (l.parent_ids.has(s.villager_id) or s.life_stage() == &"elder"
			or social.graph.has_tag(s.villager_id, l.villager_id, &"mentor")):
		var top := values_of(s).strongest(1)
		if not top.is_empty() and float(top[0][1]) > 0.15:
			data["value"] = top[0][0]
			w[&"pass_on_values"] = 0.6 + 0.5 * float(top[0][1])
	if not l.is_adult():
		return
	# Customs: keepers teach them, critics argue against them.
	var teach := -1
	var tv := 0.0
	var debate := -1
	var dv := 0.0
	for c in customs.values():
		if not c["status"] in ACTIVE or not _in_scope(c, s.villager_id):
			continue
		var ds := devotion_of(s.villager_id, c["id"])
		var dl := devotion_of(l.villager_id, c["id"])
		if ds > 0.45 and dl < ds - 0.3 and ds - dl > tv:
			tv = ds - dl
			teach = c["id"]
		if (ds < -0.3 and dl > 0.3) or (ds > 0.3 and dl < -0.3):
			if absf(ds - dl) > dv:
				dv = absf(ds - dl)
				debate = c["id"]
	if teach >= 0:
		data["custom"] = teach
		w[&"teach_custom"] = 0.3 + 0.5 * maxf(0.0, value(s, &"tradition")) + 0.3 * s.personality.get_trait(&"loyalty")
	if debate >= 0:
		data["debate"] = debate
		w[&"debate_custom"] = 0.3 + 0.4 * s.personality.get_trait(&"competitiveness") + 0.3 * dv
	for vi in violations:
		if vi[0] == l.villager_id and SimClock.get_day() - int(vi[1]) <= 2 and l != s:
			if value(s, &"generosity") + value(s, &"tradition") > 0.3:
				data["violation"] = vi[2]
				w[&"rebuke"] = 0.8 + 0.4 * s.personality.get_trait(&"honesty")
			break


func resolve(topic: StringName, o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary, conv: ConversationSystem) -> void:
	match topic:
		&"tell_story": _resolve_story(o, s, l, data)
		&"teach_custom": _resolve_teach_custom(o, s, l, data)
		&"debate_custom": _resolve_debate(o, s, l, data)
		&"rebuke": _resolve_rebuke(o, s, l, data)
		&"pass_on_values": _resolve_pass_on(o, s, l, data)
	if o.line_speaker == "":
		conv._resolve_small_talk(o, s, l, data)


func _resolve_story(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var e: Dictionary = lore.entries.get(int(data.get("lore", -1)), {})
	if e.is_empty():
		return
	var social := society.ctx.social
	var d := lore.distortion_of(e, s.villager_id)
	var age_years := (SimClock.get_day() - int(e["day"])) / maxf(1.0, society.ctx.config.days_per_year)
	# Retelling simplifies: the further back, the more it drifts.
	var p := 0.1 + 0.02 * age_years + (0.15 if s.personality.get_trait(&"honesty") < 0.35 else 0.0) \
			+ (0.1 if s.personality.get_trait(&"creativity") > 0.7 else 0.0)
	var nd := d + (1 if social.rng.randf() < clampf(p, 0.0, 0.8) else 0)
	# The listener hears it coloured by the teller's feelings.
	var tv := float(e["knowers"][s.villager_id][1])
	var lv := lerpf(lore.valence_for(e, values_of(l)), tv, 0.35)
	o.culture_ops.append(["lore", e["id"], l.villager_id, nd, lv])
	var vals := {}
	for k in e["values"]:
		vals[k] = 0.02 * float(e["values"][k]) * signf(lv)
	o.culture_ops.append(["values", l.villager_id, vals, "stories"])
	o.add_memory(s.villager_id, &"chatted", l.villager_id)
	o.add_memory(l.villager_id, &"chatted", s.villager_id)
	o.opinion_shifts.append([l.villager_id, s.villager_id, "respect", 0.03])
	o.style = &"warm"
	var title := (" of the %s" % String(e["word"]).capitalize()) if e["word"] != "" else ""
	o.line_speaker = "Let me tell you the story%s. %s" % [title, lore.render(e, d, social)]
	o.line_listener = "I didn't know that." if absf(lv) < 0.3 else ("We should never forget it." if lv > 0.0 else "A dark story.")
	var st := custom_of_kind(&"storytelling")
	if not st.is_empty():
		o.culture_ops.append(["practise", &"storytelling"])
	o.practice.append([s.villager_id, &"persuasion", 3.0])


func _resolve_teach_custom(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var c: Dictionary = customs.get(int(data.get("custom", -1)), {})
	if c.is_empty():
		return
	var social := society.ctx.social
	var lp := l.personality
	var fit := values_of(l).alignment(c["values"])
	var p := 0.35 + 0.4 * fit + 0.3 * social.graph.respect(l.villager_id, s.villager_id) + 0.2 * lp.get_trait(&"loyalty") \
			- 0.3 * maxf(0.0, lp.get_trait(&"curiosity") + lp.get_trait(&"independence") - 1.1)
	o.success = social.rng.randf() < clampf(p, 0.05, 0.9)
	var word := String(c["word"]).capitalize()
	o.style = &"warm" if o.success else &"talk"
	if o.success:
		o.culture_ops.append(["devotion", l.villager_id, c["id"], 0.15])
		var vals := {}
		for k in c["values"]:
			vals[k] = 0.015 * float(c["values"][k])
		o.culture_ops.append(["values", l.villager_id, vals, "teaching"])
		o.line_speaker = "The %s - %s. It is who we are." % [word, String(c["form"])]
		o.line_listener = "You're right. I'll keep it too."
	else:
		o.culture_ops.append(["devotion", l.villager_id, c["id"], -0.05])
		o.line_speaker = "You should keep the %s, as we always have." % word
		o.line_listener = "Maybe. Or maybe it's time for something new."
	o.add_memory(s.villager_id, &"chatted", l.villager_id)
	o.add_memory(l.villager_id, &"chatted", s.villager_id)


func _resolve_debate(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var c: Dictionary = customs.get(int(data.get("debate", -1)), {})
	if c.is_empty():
		return
	var social := society.ctx.social
	var ds := devotion_of(s.villager_id, c["id"])
	var word := String(c["word"]).capitalize()
	# Persuasion against entrenchment: most debates harden both sides.
	var p := 0.15 + 0.3 * social.graph.respect(l.villager_id, s.villager_id) + s.skills.get_level(&"persuasion") / 300.0 \
			- 0.2 * l.personality.get_trait(&"independence")
	o.style = &"argue"
	if social.rng.randf() < clampf(p, 0.05, 0.6):
		o.culture_ops.append(["devotion", l.villager_id, c["id"], 0.3 * signf(ds)])
		o.line_listener = "...Perhaps you have a point about the %s." % word
		o.add_memory(l.villager_id, &"persuaded", s.villager_id, -1, word)
	else:
		o.culture_ops.append(["devotion", s.villager_id, c["id"], 0.05 * signf(ds)])
		o.culture_ops.append(["devotion", l.villager_id, c["id"], -0.05 * signf(ds)])
		o.add_memory(s.villager_id, &"disagreed", l.villager_id, -1, word)
		o.add_memory(l.villager_id, &"disagreed", s.villager_id, -1, word)
		o.line_listener = "The %s is ours. I won't give it up." % word if ds < 0.0 else "No. The %s should be left behind." % word
	o.line_speaker = ("The %s is an old habit we don't need." % word) if ds < 0.0 else ("Without the %s we'd lose who we are." % word)


func _resolve_rebuke(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var what: String = data.get("violation", "broke our custom")
	var social := society.ctx.social
	o.style = &"argue"
	var own := value(l, &"generosity") + value(l, &"tradition") - value(l, &"independence")
	o.line_speaker = "People saw you - you %s. That's not how we live." % what
	if own > 0.0:
		o.culture_ops.append(["shame", l.villager_id, 0.3, "Was rebuked for having %s" % what])
		o.culture_ops.append(["values", l.villager_id, {&"generosity": 0.02}, "norm_shame"])
		o.line_listener = "...You're right. It won't happen again."
		o.add_memory(l.villager_id, &"was_comforted", s.villager_id)
	else:
		o.opinion_shifts.append([l.villager_id, s.villager_id, "resentment", 0.1])
		o.add_memory(l.villager_id, &"accused", s.villager_id, -1, what)
		o.line_listener = "I'll live as I see fit."
	if social != null:
		o.add_memory(s.villager_id, &"complained", l.villager_id, -1, what)


func _resolve_pass_on(o: ConversationOutcome, s: Villager, l: Villager, data: Dictionary) -> void:
	var k := StringName(data.get("value", ""))
	if k == &"":
		return
	var vals := {k: 0.04 * maxf(0.2, value(s, k))}
	var rebel := l.personality.get_trait(&"independence") + l.personality.get_trait(&"curiosity") > 1.3 and l.life_stage() == &"youth"
	if rebel and society.ctx.social.rng.randf() < 0.5:
		vals[k] = -0.02
		o.line_listener = "That's what you believe. I'm not so sure."
		o.style = &"talk"
	else:
		o.line_listener = "I'll remember."
		o.style = &"warm"
	o.culture_ops.append(["values", l.villager_id, vals, "teaching"])
	var label := String(CulturalValues.LABELS[k]).to_lower()
	var word := language.word(StringName("value_" + String(k)))
	o.line_speaker = ("Remember: %s - %s - matters above all." % [word.capitalize(), label]) if word != "" else ("Remember: %s matters above all." % label)
	o.add_memory(l.villager_id, &"was_taught", s.villager_id, -1, label)
	o.add_memory(s.villager_id, &"taught", l.villager_id, -1, label)


func validate_op(op: Array) -> bool:
	var social := society.ctx.social
	match op[0]:
		"lore": return lore.entries.has(int(op[1])) and social.get_villager(int(op[2])) != null
		"devotion": return customs.has(int(op[2])) and social.get_villager(int(op[1])) != null
		"values", "shame": return social.get_villager(int(op[1])) != null
		"practise": return true
	return false


func apply_op(op: Array) -> void:
	var social := society.ctx.social
	match op[0]:
		"lore":
			var e: Dictionary = lore.entries[int(op[1])]
			lore.learn(e, int(op[2]), int(op[3]), float(op[4]))
			e["retold"] = int(e["retold"]) + 1
		"devotion":
			_set_devotion(int(op[1]), int(op[2]), devotion_of(int(op[1]), int(op[2])) + float(op[3]))
		"values":
			var v := social.get_villager(int(op[1]))
			for k in op[2]:
				_shift(v, k, float(op[2][k]), op[3])
		"shame":
			var v2 := social.get_villager(int(op[1]))
			v2.emotions.feel(&"shame", float(op[2]), op[3], v2.personality)
		"practise":
			_practise(op[1])


# ==========================================================================
# Tick
# ==========================================================================

func tick(dt: float) -> void:
	_close_ceremonies()
	# The periodic work is spread over consecutive ticks to avoid spikes.
	if _step > 0:
		_run_step(_step)
		_step = (_step + 1) % 5
		return
	_timer += dt
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	_phase = (_phase + 1) % 4
	_step = 1
	_run_step(0)


func _run_step(step: int) -> void:
	match step:
		0: _enculturate()
		1:
			_work_drift()
			_update_tribe_values()
		2: _update_customs()
		3:
			_check_patterns()
			_update_lore()
			_language_step()
		4:
			_update_art()
			_update_adornments()
			if _phase == 0:
				_generational()
				_retry_styles()
				_decay_causes()
	if society.politics.government in [&"chief", &"hereditary"] and hereditary():
		var h := custom_of_kind(&"hereditary")
		if not h.is_empty():
			h["last"] = SimClock.get_day()


func describe() -> String:
	var parts: PackedStringArray = []
	for item in dominant_values(4):
		parts.append("%s %+.2f" % [CulturalValues.LABELS[item[0]], item[1]])
	return "  ·  ".join(parts) if not parts.is_empty() else "No shared values yet"


func dominant_values(n: int = 5) -> Array:
	var list := []
	for k in CulturalValues.VALUES:
		if absf(tribe_value(k)) >= 0.05:
			list.append([k, tribe_value(k)])
	list.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
	return list.slice(0, n)


## Cultural influence of a person: customs founded, followers of their
## beliefs, stories told about them.
func influential_figures(n: int = 5) -> Array:
	var score := {}
	var names := {}
	for c in customs.values():
		var f := int(c["founder"])
		score[f] = float(score.get(f, 0.0)) + 3.0 + float(c["support"]) * 4.0
		names[f] = c["founder_name"]
	for e in lore.living():
		for i in e["actors"].size():
			var id: int = e["actors"][i]
			score[id] = float(score.get(id, 0.0)) + float(e["importance"]) * 2.0 + e["knowers"].size() * 0.1
			names[id] = e["names"][i] if i < e["names"].size() else "?"
	for id in legacies:
		score[id] = float(score.get(id, 0.0)) + float(legacies[id]["weight"]) / 20.0
		names[id] = legacies[id]["name"]
	var list := []
	for id in score:
		if id >= 0:
			list.append([id, names.get(id, society.ctx.social.name_of(id)), score[id]])
	list.sort_custom(func(a, b): return a[2] > b[2])
	return list.slice(0, n)


func to_dict() -> Dictionary:
	var pv := {}
	for id in people:
		pv[str(id)] = people[id].to_array()
	var dv := {}
	for id in devotion:
		var m := {}
		for cid in devotion[id]:
			m[str(cid)] = devotion[id][cid]
		dv[str(id)] = m
	var cs := {}
	for id in customs:
		cs[str(id)] = _plain(customs[id])
	var lg := {}
	for id in legacies:
		lg[str(id)] = legacies[id].duplicate(true)
	var vw := []
	for k in vowed:
		vw.append([k.x, k.y, vowed[k]])
	var bl := {}
	for id in blessings:
		bl[str(id)] = blessings[id]
	return {"people": pv, "devotion": dv, "customs": cs, "next": next_custom, "patterns": _plain(patterns),
		"causes": _plain(causes), "cohort_causes": _plain(cohort_causes), "cause_counts": cause_counts.duplicate(),
		"tribe_values": _plain(tribe_values), "cohort_values": _plain(cohort_values), "snapshots": _plain(snapshots),
		"core": _plain(core_levels), "legacies": lg, "movements": movements.duplicate(true), "changes": changes.duplicate(true),
		"counters": counters.duplicate(), "violations": violations.duplicate(true), "divides": _plain(divides),
		"blessings": bl, "vowed": vw, "famine": _plain(famine), "firsts": _firsts.duplicate(), "snapday": _last_snapshot_day,
		"language": language.to_dict(), "lore": lore.to_dict(), "art": aesthetics.to_dict(), "phase": _phase, "timer": _timer, "step": _step}


## StringName keys -> String so saved data compares equal after loading.
static func _plain(x):
	if x is Dictionary:
		var out := {}
		for k in x:
			out[String(k) if k is StringName else k] = _plain(x[k])
		return out
	if x is Array:
		var a := []
		for i in x:
			a.append(_plain(i))
		return a
	if x is StringName:
		return String(x)
	return x


static func _names_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[StringName(k)] = d[k]
	return out


func load_dict(d: Dictionary) -> void:
	people.clear()
	for id in d["people"]:
		people[int(id)] = CulturalValues.from_array(d["people"][id])
	devotion.clear()
	for id in d["devotion"]:
		var m := {}
		for cid in d["devotion"][id]:
			m[int(cid)] = float(d["devotion"][id][cid])
		devotion[int(id)] = m
	customs.clear()
	for id in d["customs"]:
		var c: Dictionary = Dictionary(d["customs"][id]).duplicate(true)
		c["values"] = _names_dict(c["values"])
		c["founding_values"] = _names_dict(c["founding_values"])
		customs[int(id)] = c
	next_custom = int(d["next"])
	patterns = Dictionary(d["patterns"]).duplicate(true)
	for p in patterns.values():
		var who := {}
		for k in p["who"]:
			who[int(k)] = int(p["who"][k])
		p["who"] = who
	causes = {}
	for k in d["causes"]:
		causes[StringName(k)] = Dictionary(d["causes"][k]).duplicate()
	cohort_causes = {"young": {}, "old": {}}
	for c in ["young", "old"]:
		for k in d["cohort_causes"][c]:
			cohort_causes[c][StringName(k)] = Dictionary(d["cohort_causes"][c][k]).duplicate()
	cause_counts = Dictionary(d["cause_counts"]).duplicate()
	tribe_values = _names_dict(d["tribe_values"])
	cohort_values = {"young": _names_dict(d["cohort_values"].get("young", {})), "old": _names_dict(d["cohort_values"].get("old", {})),
		"n_young": int(d["cohort_values"].get("n_young", 0)), "n_old": int(d["cohort_values"].get("n_old", 0))}
	snapshots = []
	for s in d["snapshots"]:
		snapshots.append({"day": int(s["day"]), "values": _names_dict(s["values"])})
	core_levels = _names_dict(d["core"])
	legacies.clear()
	for id in d["legacies"]:
		legacies[int(id)] = Dictionary(d["legacies"][id]).duplicate(true)
	movements = Array(d["movements"]).duplicate(true)
	changes = Array(d["changes"]).duplicate(true)
	counters = Dictionary(d["counters"]).duplicate()
	violations = Array(d["violations"]).duplicate(true)
	divides = _names_dict(d["divides"])
	blessings.clear()
	for id in d["blessings"]:
		blessings[int(id)] = float(d["blessings"][id])
	vowed.clear()
	for row in d["vowed"]:
		vowed[Vector2i(int(row[0]), int(row[1]))] = int(row[2])
	famine = Dictionary(d["famine"]).duplicate(true)
	if famine.has("hungry"):
		var h := {}
		for k in famine["hungry"]:
			h[int(k)] = true
		famine["hungry"] = h
	_firsts = Dictionary(d["firsts"]).duplicate()
	_last_snapshot_day = int(d["snapday"])
	language.load_dict(d["language"])
	lore.load_dict(d["lore"])
	aesthetics.load_dict(d["art"])
	_phase = int(d["phase"])
	_timer = float(d["timer"])
	_step = int(d.get("step", 0))
	restyle_from_save()
	_update_adornments()
