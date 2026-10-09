# Organic cultural evolution

The tribe's culture is not predefined, scripted or randomly assigned. It
grows out of what happens in the simulation, passes from generation to
generation, changes how people behave, and changes over time. Each new game
develops a different culture.

Code: `scripts/culture/` (values, customs catalogue, language, lore, art,
decision modifier) and `scripts/society/culture_system.gd` (the system that
ties them together). Inspect it in the game with **K** (Culture panel) and
**I** (a villager's beliefs, customs and stories).

## What was there before (audit)

The previous "culture" had six tribe-wide sliders that started at 0.5 with a
small random offset. It also had a fixed list of seven traditions, each
switching on at a hard-coded threshold. Every tribe could only ever get the
same seven traditions. Nobody held beliefs of their own, so nothing could be
passed on, disputed or lost. There were no stories, words, symbols or
cultural visuals. All of that was removed and replaced by the systems below.
The old API (`norm()`, `has_tradition()`, `sharing_bonus()`...) still exists,
but it is now computed from what people actually believe and practise.

## A. Origins: customs come from repeated behaviour

`CultureSystem.observe()` records patterns of real behaviour with the people
involved and concrete notes ("Aru fed the starving Bela"):

| Pattern | Recorded when |
|---|---|
| evening talk | two villagers chat by the campfire in the evening |
| hardship | someone is fed while starving, refused food, or goes hungry |
| death | someone dies (mourners: kin and friends) |
| harvest | a farm is harvested |
| coming of age | a youth becomes an adult |
| partnership | a couple forms |
| expedition | someone goes fishing or makes a discovery |
| conflict | two people come to blows |
| craft teaching | a professional teaches their trade |
| birth | a child is born |
| leader passing | a leader dies or falls (approval decides "good" or "bad") |
| lineage | a chief with children rules |
| woodcut | a tree is felled |
| commemoration | an important event becomes part of the collective memory |

A pattern becomes a custom only when three things hold:

1. It has repeated enough times.
2. The tribe is complex enough: population, known techniques, existing
   ceremonies, enough vocabulary or stories, depending on the custom.
3. The people involved share beliefs that give it meaning.

Several customs compete for each pattern (`CustomCatalog`, 24 kinds).
The one that best fits the participants' current beliefs wins, so the same
event leads to different customs:

| Pattern | Possible customs |
|---|---|
| hardship | **sharing custom** (generosity, cooperation) or **strict rationing** (hierarchy, independence). How the hard times were actually survived (help versus refusals) also counts. |
| death | **funeral rites** (spirituality) or **ancestor veneration** (elders, family) |
| evening talk | **evening fire** (cooperation, hospitality) or **storytelling nights** (knowledge, tradition, elders) |
| harvest | **harvest feast** or **first-fruits offering** |
| coming of age | **trial of courage** or **apprenticeship to a master** |
| partnership | **partnership feast** or **vows** |
| conflict | **peacekeeping** (mediation) or **contest** (a fight settles the quarrel) |
| leader passing | **remembrance of the leader** or **"no one above the rest"** |
| lineage | **hereditary succession** or **council of elders** |
| birth | **gifts for newborns** or **kin naming** |

Each custom also takes a *form*, the variant that best fits its founders'
beliefs. For example, a funeral might be "beneath a cairn", "with a great
fire", "with the tools of their trade" or "beneath a young tree". Each
custom records:
- its origin: the actual events and names behind it;
- its founder: the person most involved, weighted by standing;
- its own word in the tribe's language.

## B. Values and beliefs

Every villager holds 18 values (`CulturalValues`, from -1 to 1):
cooperation, independence, respect for elders, courage, generosity, loyalty,
family, achievement, equality, hierarchy, hospitality, tradition, curiosity,
spirituality, respect for nature, strength, craftsmanship and knowledge.

- **Starting point.** Founders start with faint personal leanings derived from
  their temperament. Children are born with no values.
- **Experience.** About 40 kinds of experience shape values. Each one is
  interpreted through the person's personality and existing beliefs. Being
  refused food teaches one person to want someone to keep order, another that
  everyone should share, and a third to rely on no one. Hunger strengthens
  solidarity, order or self-reliance depending on how the tribe actually got
  through it.
- **Work and age.** Working the land breeds respect for nature, and working
  with one's hands breeds craftsmanship. Elders grow more traditional.
  Beliefs that are not fed by experience slowly fade.
- **Tribe values.** The tribe's values are its members' beliefs, weighted by
  influence, so leaders and respected elders weigh more.

Values change behaviour (tendencies, not rules), and individuals still act on
their own beliefs:

- **Decisions.** `CultureModifier` adjusts goal scores: craft and building,
  working the land and sparing trees, exploring, helping, attending
  ceremonies, seeking office. It appears in the inspector's decision trace as
  "Beliefs ×…".
- **Economy.** Tools are held in common or privately depending on cooperation
  versus independence.
- **Politics:**
  - The backing a chief needs (50–85% of adults) depends on equality and
    hierarchy, and on the "no one above" custom.
  - Elders' influence depends on respect for elders.
  - Achievement and family change whose voice carries.
  - Following the leader depends on each person's hierarchy, loyalty and
    independence.
  - Councils form when the tribe favours consensus. A council of elders forms
    under the elder-council custom.
- **Projects.** Each building type means something (a farm means nature and
  cooperation, a workshop craftsmanship, a shrine spirituality...). The first
  building of a new kind is opposed by traditional people and favoured by
  curious ones.
- **Relationships.** Shared beliefs make conversations go better and add to
  attraction. Loyalty, family values and vows make couples hold together
  longer.
- **Education.** Valuing knowledge makes teaching more effective, and
  craft-mark guilds train apprentices better.
- **Family.** Valuing family raises the chance of conceiving.
- **Expectations.** In a generous culture, refusing food to the hungry costs
  respect from the victim and witnesses, and brings shame to anyone who shares
  the value. A person who values independence feels no shame. Helping earns
  prestige. Staying away from a *central* custom costs respect among its
  keepers. Breaches of custom are recorded and can lead to a rebuke.

## C. Customs, traditions and rituals

Each villager has a devotion (from -1 to 1) to each custom. It drifts toward:
- how well the custom fits their own beliefs;
- what their partner, family and friends keep (conformity);
- their attachment to tradition once the custom is old.

Practising a custom and attending its ceremonies deepen devotion. Devotion in
turn strengthens the custom's values, so customs sustain themselves while
people keep them.

**Ceremonies** are real gatherings: funerals, harvest feasts, first-fruits
offerings, vows, partnership feasts, coming-of-age trials and
apprenticeships, yearly remembrances of leaders and ancestors, and
commemorations of events.
- **Who comes.** Devoted villagers are drawn to attend. Those who reject the
  custom stay away, unless the ceremony is about someone close to them.
- **Effects.** Attendees grow closer and remember the ceremony. Grief eases at
  funerals. Couples' grudges are cleared at weddings, and vows make
  separation harder. Youths gain courage and prestige at trials, or a master
  and a skill at apprenticeships. Commemorations retell the event.
- **Costs.** Feasts and offerings use real food from the store.

Customs have a status that changes with support:
- **emerging**: newly founded;
- **established**: 45% of adults keep it;
- **central**: 75% keep it;
- **contested**: 30% reject it;
- **fading**: support below 20%;
- **abandoned**: support stays below 10%. A daily practice (the evening fire,
  storytelling nights, the luck song before fishing) is also abandoned after 20
  days without practice.

Complexity is gated: the number of customs a tribe can sustain grows with its
population and its ceremonial buildings.

Some customs have direct effects:
- strict rationing caps each share of food;
- the luck song makes fishers braver and more effective for half a day;
- under tree-thanks, saplings are planted, so felled trees regrow sooner;
- kin naming gives children part of a parent's name;
- gifts for newborns take food from the store for the parents.

When ceremonies become important (two or more ceremonial customs and ten or
more people), villagers propose a **gathering circle**. Ceremonies then move
there, to the shrine or to the longhouse, depending on their kind.

## D. Transmission between generations

At every culture check, each villager learns toward a weighted mix of models:
- parents (most strongly for children);
- the remembered beliefs of dead parents;
- mentors and the two closest friends;
- the leader (weighted more in hierarchical cultures);
- elders (in cultures that respect them);
- the legacies of influential dead people they were fond of.

Openness falls with age: children 0.05, youths 0.03, adults 0.008, elders
0.003. Independent people learn more slowly. Children's devotion to customs
follows their parents'.

**The young do not simply copy their elders.** Independent and curious youths
sometimes turn against the value their models hold most strongly. Customs
cherished by the old can lose support among restless young adults. The
"pass on values" and "tell story" conversations may be accepted or brushed
off.

When an influential person dies, their beliefs are kept as a **legacy** and
keep shaping those who loved them. Their customs survive them if enough people
keep them; the culture panel notes "the legacy of the late X".

## E. Language and communication

`TribalLanguage` gives each tribe a small sound system, chosen from its seed:
- 7–11 consonants and 3–5 vowels (sometimes a diphthong);
- how often syllables end in a consonant;
- a linking vowel for compounds.

Each concept has one stable root, and new terms are compounds of roots.
Every word is checked against the sound system (`is_well_formed`).

Words are coined only when something matters:
- a custom (for example *Momurai*, "food-share");
- an important story;
- a value the tribe comes to hold (it then has a word for "cooperation");
- the lake, the valley and the mountains, once there are stories to tell
  about them;
- the leader's title;
- a title for elders, where they are respected.

**The tribe's own name.** Once it shares a home, a custom and a value, the
tribe names itself (for example "the Gimeno, people of cooperation") and is
renamed in the game.

**Names.** After four words exist, children are named in the tribe's own
sounds. Under kin naming, a child also carries part of a parent's name. Under
ancestor veneration, names of honoured dead are carried on.

**Dialogue.** Conversations use the words: "Will you come to the Chanopa
tonight?", "Nowhere is as beautiful as Gesichi in the evening", "Remember:
Nopago, cooperation, matters above all".

## F. Art, symbols and architecture

`TribalAesthetics` handles colour, motif, art levels and architecture.

**Pigments** come from what the tribe actually does, in the order its history
provides them:

| Pigment | Comes from |
|---|---|
| red ochre | stonework |
| charcoal | the fire or funeral customs |
| purple | foraging |
| green | herbalism |
| blue clay | fishing |
| white chalk | a shrine |
| yellow | fields |

**Motif.** When decoration first appears, the tribe adopts the motif that best
expresses its strongest values: spirals, zigzags, bands, dots, chevrons,
leaves, hatching or rings. A much later shift in values can replace it.

**Art levels** each have real prerequisites:
1. **Body paint and sashes**: an established ceremonial custom and a pigment.
   Only adults devoted to a custom wear its colour; children and those who
   reject it do not. Respected elders and leaders wear a headband, and guild
   members a belt of the guild's colour.
2. **Painted homes**: 10+ people and craft values or toolmaking. Bands of
   paint and the motif appear on huts, the workshop, the longhouse and the
   shrine. Existing homes are repainted once.
3. **Carving**: 12+ people and carpentry or a master woodcutter or
   stoneworker. This makes **totems** (carved, painted segments) and
   **memorial stones** possible. Villagers propose both, and a memorial is
   raised for a specific remembered person.

**Architecture eras.** A new technique (carpentry, toolmaking, agriculture)
offers a new building style, such as timber frames, carved door posts or
thatch from the fields.
- Builders vote with their influence and skill. The curious and the young
  push for the new style; the traditional and the old resist.
- If adopted, new buildings take the new style. If rejected, "the older
  builders' ways prevailed", and the idea can come back 10 days later.
- Each building keeps the style of the era it was built in, so the
  settlement's architecture records its history.

## G. Change and internal disagreement

- **Contested customs** are detected and explained: "The young increasingly
  reject it (20% of the young keep it, 80% of the old)", or opposition
  concentrated in a named group.
- **Movements.** Opponents form a movement with a leader, the most
  influential opponent. Its outcome (reformed, abandoned) is recorded.
- **Reform.** An innovator (high creativity and curiosity, middling devotion)
  can reshape a contested custom into the form its critics prefer. Critics
  come round, traditionalists resent it, and the reformer gains prestige.
- **Generational divides.** When the young and the old differ by 0.25 or more
  on a value, it is announced, with the main cause for the side that moved.
- **Group customs.** Guild traditions (craft mark) belong to one guild.
  Family-type customs can belong to one extended family when it practised them
  on its own. Each group's distinctive values are shown in the panel.
- **Value thresholds.** A value crossing one is announced with its causes,
  for example "Generosity is becoming a shared value of the tribe (+0.31).
  Mostly because people shared food with the hungry (12 times), …".

## H. Collective memory

`LoreBook` turns important events into stories:
- the first harvest, the first communal building and the first chief;
- a fallen leader and the hungry days;
- discoveries, the passing of founders and notable people;
- the founding of customs, reconciliations and the first birth.

At first, only those who lived through an event know it. Others learn it in
"tell story" conversations (elders and parents tell children) and at
commemorations.

**Distortion.** Each retelling may simplify the story. The dead lose their
names (Aru → "Aru the wise" → "the Wise" → "the ancestors"), numbers become
"a great harvest", and eventually it becomes myth: "In the old days the first
chief was given to the people". The panel shows how many versions are in
circulation.

**Interpretation.** Each person's feeling about a story depends on their
beliefs. The first chief is a proud memory for those who value hierarchy and
a warning for those who value equality. The panel shows how each group
remembers it.

**Memory shapes values.** Stories people know keep reinforcing (or
discrediting) the values they stand for.

**Forgetting.** A story nobody alive remembers is lost, and this is recorded
in the chronicle.

## I. Emergence, not a script

- **No fixed progression.** Nothing is scheduled. Which customs appear, their
  forms, the words, colours and motif, and the tribe's name all depend on
  what happens and who is involved.
- **Different worlds.** Runs with different seeds differ in language,
  customs, values, art and name (see the test results below).
- **Different histories.** The same event has different consequences
  depending on existing beliefs: the hardship test shows sharing in one tribe
  and rationing in another.

## J. Inspection (K)

The Culture panel shows:
- dominant values, each rising, falling or steady, with the recorded causes;
- every custom, with its word, meaning, form, status, support and opposition,
  young versus old, scope (tribe or a group), origin story, founder and
  reforms;
- abandoned customs;
- social expectations derived from the current culture, and recent breaches;
- what is gaining or losing support, and active movements;
- generational differences and differences between groups;
- the collective memory: the most common version of each story, the number of
  versions, and how groups feel about it;
- influential cultural figures;
- art: pigments and where they came from, the motif and why, art level and
  architectural eras;
- the lexicon;
- a timeline of explained cultural changes.

Every explanation is assembled from recorded data (causes, counts, support
figures, names and days), not from flavour text.

## Tests

`tests/culture_test.gd` runs the tribe for N days, prints its culture,
checks what emerged, then exercises each mechanism directly:

```bash
godot --headless --path . res://tests/culture_test.tscn --fixed-fps 60 -- --seed=42 --days=30
godot --headless --path . res://tests/culture_test.tscn --fixed-fps 60 -- --seed=2024 --days=200 --report-only --chronicle
```

See the README for the latest results.

## Limitations

- **Templates.** Customs come from a catalogue of 24 kinds with 2–4 forms
  each. Which ones appear, when, in what form, under what name and among whom
  is emergent, but the tribe cannot invent an entirely new kind of practice.
- **Language.** It produces words, names and compounds, but no grammar. The
  dialogue is English with tribal words inserted.
- **Art.** Art is limited to sashes, headbands, belts, painted bands and
  motifs on buildings, totems, memorial stones and the gathering circle. There
  is no pottery, no clothing cut, and no group-specific patterns beyond guild
  belts.
- **Movements and reform.** These need contested customs, which mostly appear
  once a second generation has grown up. In short runs (under about 40 days)
  they are rare.
- **No other tribes.** As specified, there is only one tribe. Migration
  within the territory is not modelled.
