class_name TribalLanguage
extends RefCounted
## The tribe's own words.
##
## Each tribe gets a small, consistent sound system (which consonants and
## vowels it uses, whether syllables may end in a consonant, a linking vowel
## for compounds). Every concept has one stable root built from those sounds,
## and new terms are compounds of existing roots, so words stay
## pronounceable and related ideas sound related ("fire" + "together" ->
## the name of the evening gathering).
##
## Words only enter the shared vocabulary when something becomes culturally
## significant: a custom, a remembered event, a place, a value the tribe
## holds dear, a title. Early on the tribe has no words of its own; the
## vocabulary grows with its history.

const CONSONANT_POOL := ["p", "t", "k", "m", "n", "s", "l", "r", "v", "h", "d", "g", "b", "sh", "th", "z", "w", "y", "f", "ch"]
const VOWEL_POOL := ["a", "e", "i", "o", "u", "ai", "au", "ei"]

## concept -> English gloss (used to explain words in the UI).
const GLOSS := {
	&"fire": "fire", &"together": "together", &"food": "food", &"share": "share", &"death": "death",
	&"ancestor": "ancestor", &"harvest": "harvest", &"child": "child", &"partner": "bond", &"stone": "stone",
	&"tree": "tree", &"water": "water", &"sky": "sky", &"people": "people", &"home": "home", &"path": "path",
	&"honor": "honour", &"brave": "brave", &"wise": "wise", &"make": "make", &"hand": "hand", &"old": "old",
	&"new": "new", &"first": "first", &"strong": "strong", &"spirit": "spirit", &"song": "song",
	&"night": "night", &"valley": "valley", &"lake": "lake", &"mountain": "mountain", &"chief": "chief",
	&"elder": "elder", &"gift": "gift", &"rite": "rite", &"peace": "peace", &"trial": "trial", &"mark": "mark",
	&"light": "light", &"hunger": "hunger", &"teach": "teach", &"guard": "keep", &"field": "field",
	&"fish": "fish", &"word": "word", &"story": "story", &"free": "free", &"equal": "equal", &"heart": "heart",
	&"memory": "memory", &"circle": "circle", &"blood": "kin", &"earth": "earth", &"seek": "seek",
}

var consonants: Array = []
var vowels: Array = []
var finals: Array = []
var closed_syllables := 0.3
var linker := "a"
var _seed := 0
var _roots: Dictionary = {}
var _syllables: Dictionary = {}  # concept -> [syllables of its root]
var _used_roots: Dictionary = {}
## concept -> {"word", "day", "gloss"}
var lexicon: Dictionary = {}
## Concepts that turned out to mean the same as an existing word: concept -> concept
var aliases: Dictionary = {}


func _init(seed_value: int) -> void:
	_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "phonology"])
	var cpool := CONSONANT_POOL.duplicate()
	_shuffle(cpool, rng)
	consonants = cpool.slice(0, rng.randi_range(7, 11))
	var vpool := VOWEL_POOL.slice(0, 5)
	_shuffle(vpool, rng)
	vowels = vpool.slice(0, rng.randi_range(3, 5))
	if rng.randf() < 0.35:
		vowels.append(VOWEL_POOL[rng.randi_range(5, 7)])
	closed_syllables = rng.randf_range(0.0, 0.45)
	for c in consonants:
		if c.length() == 1 and c in ["n", "m", "l", "r", "s", "k", "t", "sh", "th"]:
			finals.append(c)
	if finals.is_empty():
		closed_syllables = 0.0
	linker = vowels[rng.randi() % vowels.size()]


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _syllable(rng: RandomNumberGenerator, allow_closed: bool) -> String:
	var s := ""
	if rng.randf() < 0.85:
		s += consonants[rng.randi() % consonants.size()]
	var vw: String = vowels[rng.randi() % vowels.size()]
	if vw.length() > 1 and rng.randf() < 0.65:
		vw = vowels[rng.randi() % vowels.size()]  # diphthongs are rarer
	s += vw
	if allow_closed and not finals.is_empty() and rng.randf() < closed_syllables:
		s += finals[rng.randi() % finals.size()]
	return s


## The stable root for a concept (the same every time it is asked for).
func root(concept: StringName) -> String:
	if _roots.has(concept):
		return _roots[concept]
	var rng := RandomNumberGenerator.new()
	for attempt in 20:
		rng.seed = hash([_seed, String(concept), attempt])
		var n := 1 if rng.randf() < 0.55 else 2
		var sy: Array = []
		for i in n:
			sy.append(_syllable(rng, i == n - 1))
		var w := "".join(sy)
		if not _used_roots.has(w) and w.length() >= 2:
			_used_roots[w] = concept
			_roots[concept] = w
			_syllables[concept] = sy
			return w
	_roots[concept] = root(&"word") + str(_roots.size())
	return _roots[concept]


## Two roots joined by the tribe's linking vowel where needed.
func compound(a: StringName, b: StringName) -> String:
	var ra := root(a)
	var rb := root(b)
	# Long roots are clipped to their first syllable in compounds.
	var sb: Array = _syllables.get(b, [rb])
	if sb.size() > 1 and _syllables.get(a, [ra]).size() > 1:
		rb = sb[0]
	if not _is_vowel(ra[ra.length() - 1]) and not _is_vowel(rb[0]):
		return ra + linker + rb
	return ra + rb


static func _is_vowel(ch: String) -> bool:
	return ch in ["a", "e", "i", "o", "u"]


## Add a word to the shared vocabulary (idempotent). `parts` = two concepts
## to compound; otherwise the concept's own root is used.
func coin(concept: StringName, gloss: String = "", parts: Array = []) -> String:
	if lexicon.has(concept):
		return lexicon[concept]["word"]
	if aliases.has(concept):
		return lexicon[aliases[concept]]["word"]
	var w := compound(parts[0], parts[1]) if parts.size() == 2 else root(concept)
	for other in lexicon:
		if lexicon[other]["word"] == w:
			aliases[concept] = other  # the same idea again: the same word
			return w
	lexicon[concept] = {"word": w, "day": SimClock.get_day(), "gloss": gloss if gloss != "" else GLOSS.get(concept, String(concept))}
	return w


func knows(concept: StringName) -> bool:
	return lexicon.has(concept) or aliases.has(concept)


func word(concept: StringName) -> String:
	if aliases.has(concept):
		concept = aliases[concept]
	return lexicon[concept]["word"] if lexicon.has(concept) else ""


func capitalized(concept: StringName) -> String:
	var w := word(concept)
	return w.capitalize() if w != "" else ""


## "Tavuri (fire-gathering)" for the UI.
func display(concept: StringName) -> String:
	if not lexicon.has(concept):
		return ""
	return "%s (%s)" % [String(lexicon[concept]["word"]).capitalize(), lexicon[concept]["gloss"]]


func size() -> int:
	return lexicon.size()


## A personal name in the tribe's own sounds.
func personal_name(rng: RandomNumberGenerator) -> String:
	var n := 2 if rng.randf() < 0.7 else 3
	var w := ""
	for i in n:
		w += _syllable(rng, i == n - 1)
	return w.capitalize()


## True if `w` can be split into syllables of this language (for tests).
func is_well_formed(w: String) -> bool:
	return _parse(w.to_lower(), 0)


func _parse(w: String, i: int) -> bool:
	if i >= w.length():
		return true
	for c in consonants + [""]:
		if c != "" and not w.substr(i).begins_with(c):
			continue
		var j: int = i + c.length()
		for v in vowels + [linker]:
			if not w.substr(j).begins_with(v):
				continue
			var k: int = j + v.length()
			if _parse(w, k):
				return true
			for f in finals:
				if w.substr(k).begins_with(f) and _parse(w, k + f.length()):
					return true
	return false


func to_dict() -> Dictionary:
	var lx := {}
	for c in lexicon:
		lx[String(c)] = lexicon[c].duplicate()
	var al := {}
	for c in aliases:
		al[String(c)] = String(aliases[c])
	return {"lexicon": lx, "aliases": al}


func load_dict(d: Dictionary) -> void:
	lexicon.clear()
	for c in d.get("lexicon", {}):
		lexicon[StringName(c)] = Dictionary(d["lexicon"][c]).duplicate()
		root(StringName(c))
	aliases.clear()
	for c in d.get("aliases", {}):
		aliases[StringName(c)] = StringName(d["aliases"][c])
