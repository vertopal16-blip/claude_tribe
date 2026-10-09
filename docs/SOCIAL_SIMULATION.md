# Emergent Personalities and Social Simulation

> **Status: implemented.** Sections 1–3 are the original specification and
> design. [Section 7](#7-audit-of-the-previous-version-why-no-couples-formed)
> is the audit, [section 8](#8-what-is-implemented) describes what is built
> and tested, and [section 9](#9-limitations-and-unfinished-parts) lists
> what is still open.

---

## 1. Specification

### Core vision
Every villager eventually has an individual personality, personal memories,
relationships, ambitions and preferences, forming a living society.

There is only **one tribe**. Families, friendships, rivalries and social groups
emerge *inside* that tribe. No independent civilizations are ever created.

### Individual personalities
Configurable traits per villager:

| Trait | Trait |
|---|---|
| Sociability | Courage |
| Ambition | Trust |
| Aggressiveness | Independence |
| Generosity | Industriousness |
| Curiosity | Empathy |

- Traits influence decisions **probabilistically**, never as identical scripted outcomes.
- Opinions and behaviour change through experience.

### Memory and relationships
Villagers remember significant events involving themselves and others, for example:
being helped during a crisis, being betrayed or insulted, receiving or refusing
help, building together, losing a family member, sharing resources, and forming
friendships, rivalries and romances.

- Memories influence trust, conversations, cooperation and decisions.
- Trivial events are not kept forever: important memories are prioritized and
  older experiences are summarized.

### Contextual conversations
Conversations consider both participants' personalities, their shared history,
recent events, current needs and goals, the knowledge each one actually has,
and the surroundings.

- Conversations have consequences: they change relationships, spread information,
  resolve conflicts, create misunderstandings or inspire plans.
- Villagers never know things they could not reasonably have learned.

### Emergent settlement distribution
House and work-area locations emerge from individual decisions and relationships.
Villagers weigh family and friends, trust and conflicts, access to resources,
safety and terrain, personal independence, and jobs and community duties.
Different playthroughs produce different settlements even from similar worlds.

### Technical requirements
- Separate modules for personality, memory, relationships, dialogue,
  decision-making, settlement planning and navigation.
- Routine AI never depends on an external language model.
- Generative dialogue (if added) never modifies game state directly. Every
  effect is validated by the simulation.
- Priorities: deterministic rules, performance, persistence, testability.

---

## 2. Design principles

1. **The simulation owns the truth.** Personality, memory and relationships are
   plain data plus deterministic rules. Text (templated or generated) only
   *describes* outcomes the simulation has already decided or validated.
2. **Bias, don't script.** Social systems change utility scores and
   probabilities. The brain still picks among concrete, validated tasks.
3. **Bounded cost per villager.** Fixed-size memory, top-N relationships, and
   social evaluation on a slower cadence than needs. The target is hundreds of
   villagers.
4. **Everything persists by id.** Systems reference villagers by `villager_id`
   and objects by `entity_id`, never by node, so state can be saved, loaded and
   replayed.
5. **Seeded randomness only.** Every probabilistic choice uses an RNG derived
   from the world seed and an entity id.

---

## 3. Module plan

```
scripts/social/
  personality.gd          Traits (0..1 floats) + drift rules
  personality_modifier.gd DecisionModifier: traits -> goal score bias
  memory.gd               Per-villager bounded memory store
  memory_record.gd        One remembered event (plain data)
  memory_policy.gd        Salience, decay, consolidation/summarization rules
  relationship_graph.gd   Tribe-wide sparse graph: (a_id, b_id) -> Relationship
  relationship.gd         affinity, trust, familiarity, tags (kin, partner, rival)
  social_modifier.gd      DecisionModifier: relationships -> cooperate/avoid bias
  knowledge_store.gd      Per-villager known facts (locations, events, beliefs)
  conversation_system.gd  Picks partners/topics, resolves deterministic outcomes
  dialogue_renderer.gd    Outcome -> text (templates; optional LLM, text only)
  social_tick.gd          Slow-cadence scheduler for the social layer
```

### 3.1 Personality
- `Personality` holds the 10 traits as floats in `[0, 1]`. They are generated
  from the world seed and villager id (later also inherited from parents).
- `PersonalityModifier extends DecisionModifier` multiplies goal scores. For
  example, industriousness scales work goals, sociability adds a `socialize`
  goal, and courage lowers the weight of danger. The brain then samples from
  the top candidates with seeded weighted randomness instead of a strict
  argmax, which makes outcomes probabilistic.
- **Drift:** consolidated memories nudge traits by tiny, bounded amounts
  (for example, repeated betrayal lowers trust).

### 3.2 Memory
- Input: the existing `EventBus.villager_event` stream. Payloads are already
  plain data with `villager_id`, `time`, `day`, `position` and stable ids.
  A `MemoryWitness` step also lets *nearby* villagers record events they saw
  (perception radius), which is what makes knowledge local.
- `MemoryRecord`: `{kind, time, day, position, actors: [ids], object_ids,
  valence (-1..1), salience (0..1), count}`.
- **Salience** = base importance by kind (death of kin ≫ ate berries)
  × emotional intensity × personal relevance (involves self / friend / kin).
- **Bounded store:** about 32 recent records plus about 16 long-term records
  per villager.
- **Decay:** salience decays over time. Trivial events (eating, routine
  delivery) never reach long-term memory.
- **Consolidation:** similar low-salience records merge into summaries
  ("worked with Bela on 6 huts", "Oren refused help 3 times"), keeping counts
  and the most recent time. Summaries feed relationships and trait drift.

### 3.3 Relationships
- `RelationshipGraph` (owned by the Tribe) stores sparse edges keyed by the two
  villager ids. Each edge has `affinity`, `trust`, `familiarity` and `tags`
  (kin, partner, friend, rival).
- Updated only from memories and conversation outcomes, through deterministic
  rules scaled by personality (empathy amplifies positive events, low trust
  amplifies negative ones).
- Social groups are *derived*, not stored: clusters of high mutual affinity are
  computed on demand for UI and planning.
- `SocialModifier extends DecisionModifier` makes villagers prefer joining
  friends' tasks, avoid rivals, and help kin in crisis.

### 3.4 Knowledge (no impossible information)
- `VillagerKnowledge` already exists and is the single interface for "where is
  X". Today it answers from complete world knowledge.
- Later it is backed by `KnowledgeStore`, holding facts the villager learned by
  **perception** (saw it within range), **experience** (gathered there), or
  **communication** (told in a conversation, with the source id and confidence).
- Facts can be stale or wrong (a told-about bush already eaten). Discovering
  this is a memory event, and lowers trust in the source if it was a lie.
- Conversations may only reference facts present in the speaker's store.

### 3.5 Conversations and dialogue
Two layers, strictly separated:

1. **ConversationSystem (deterministic, authoritative).** It selects pairs
   (proximity, idle or eating time, sociability, relationship), selects a topic
   from the participants' needs, goals, recent memories and shared knowledge,
   and resolves an **outcome** with seeded rules. Possible outcomes: share a
   fact, ask for or give help, apologize, insult, propose a plan. Outcomes are
   applied as validated state changes (relationship deltas, knowledge
   transfer, new memory records, new goals).
2. **DialogueRenderer (presentation only).** It turns an outcome into text,
   using templates by default. An optional LLM backend may *phrase* the
   exchange from a context packet built only from the participants' own
   knowledge. If an LLM proposes something (for example "let's build near the
   lake"), it returns a structured **intent** that goes through the same
   validation as any AI decision. It is ignored if invalid and never applied
   directly. The game must be fully playable with the LLM disabled.

### 3.6 Emergent settlement
- `SettlementPlanner` already owns "when and where to build" and exposes
  `score_site(def, pos)`.
- Later, a site is scored for a specific villager or family. Factors: distance
  to friends and kin (+), to rivals (−), to preferred work resources (+),
  terrain safety and flatness (+), and independence (prefers distance from the
  crowd). Huts become *owned* (`Building.owner_ids`), and villagers propose
  their own build sites instead of the tribe-wide housing rule.
- Because traits, relationships and memories differ per run, layouts diverge
  naturally between playthroughs.

### 3.7 Scheduling and performance
- Needs and tasks: the existing 4 Hz `sim_tick` with a decision budget.
- Social layer: a slower cadence (for example 1 Hz, staggered by villager id),
  with a per-tick budget for conversations and consolidation like
  `max_decisions_per_tick`.
- Social queries use the existing spatial hash in `Tribe._update_separation`
  (generalized into a reusable villager spatial index).

---

## 4. Existing seams in the codebase

| Seam | Where | Purpose for this milestone |
|---|---|---|
| `DecisionModifier` + `VillagerBrain.add_modifier()` | `scripts/villager/decision_modifier.gd`, `villager_brain.gd` | Personality and relationship bias without touching the brain or tasks (`HabitModifier` is a working example). |
| `VillagerBrain.score_goals()` / `last_scores` | `villager_brain.gd` | Adding goals such as `socialize` or `help`; inspecting why a choice was made. |
| `VillagerTask` subclasses | `scripts/villager/tasks/` | New activities (talk, help, share food) plug in as tasks. |
| `Villager.record_event()` → `EventBus.villager_event` | `villager.gd`, `event_bus.gd` | Memory input stream. Payloads are serializable (tested) with who/what/where/when. |
| `VillagerKnowledge` | `scripts/villager/villager_knowledge.gd` | Single point to replace omniscient lookups with learned knowledge. |
| `SettlementPlanner.score_site()` | `scripts/tribe/settlement_planner.gd` | Personal or family site preferences. |
| Stable ids: `villager_id`, `entity_id` (`WorldContext.allocate_entity_id()`) | `world_context.gd`, `building.gd`, `resource_node.gd` | Memories, relationships and saves refer to ids, not nodes (uniqueness tested). |
| Seeded per-villager RNG (`hash([world_seed, villager_id])`) | `villager_brain.gd` | Reproducible probabilistic decisions. |
| `Tribe.add_villager()` | `tribe.gd` | Single entry point for births (inherit traits, create kin edges). |
| `WorldContext` | `scripts/core/world_context.gd` | Place to register new tribe-wide systems (relationship graph, conversation system). |
| `VillagerBrain.mark_unreachable()` | `villager_brain.gd` | Early short-term memory, to be folded into the memory system. |

---

## 5. Foundation gaps (status)

1. **Full determinism.** Done: simulation time advances in whole ticks, and
   movement runs in fixed steps with interpolated visuals (state hash identical
   at 60 and 23 fps).
2. **Persistence.** Partly done: social state serializes; the rest of the world does not yet.
3. **Probabilistic choice.** Done: seeded weighted sampling among near-best goals.
4. **Blacklist ids.** Still uses instance ids (runtime-only, not persisted).
5. **Spatial index.** Done: `Tribe.villagers_near()` (rebuilt each tick)
   and `ResourceRegistry.nodes_near()`.

## 6. Original implementation order (followed)

1. Determinism plus save/load foundations (section 5, items 1–2).
2. Personality data, `PersonalityModifier` and weighted sampling.
   Test: trait distributions shift aggregate behaviour across many seeds.
3. Memory store with salience, decay and consolidation, fed by
   `villager_event` plus witnesses. Test: memory stays bounded over long runs.
4. Relationship graph plus `SocialModifier`, and kin from births.
5. Knowledge store replacing omniscient `VillagerKnowledge`.
   Test: a villager never targets a resource it has no fact about.
6. Conversation system (deterministic outcomes, template text).
7. Emergent settlement scoring and building ownership.
8. Optional generative dialogue renderer behind the intent-validation layer.

---

## 7. Audit of the previous version (why no couples formed)

Before this rewrite the social layer had personalities, memories and opinions,
but nothing that turned them into a living society:

- **Couples could never form after the start.** A partnership required mutual
  affection plus familiarity, but successful flirts never reached any
  romance logic. A flirt changed affinity a little and was forgotten. There
  was no attraction value, no courting stage and no proposal, so the two
  founding couples were the only couples there would ever be.
- **No reproduction.** `Tribe.add_villager()` was never called after the
  start. There was no sex, no age progression and no pregnancy.
- **Superficial items:** personality had 10 traits and mood was a single
  number. There were no skills or professions, no tribe-level decisions,
  leadership, culture or history, and no save/load beyond the social state.
- **Bugs found while auditing:** a freed resource node could still be targeted
  when two sim ticks shared a frame, which broke determinism. Text
  serialization rounded floats. Babies were given homes by the planner.

## 8. What is implemented

Everything is deterministic (seeded) and offline. Tribe-level systems live in
`scripts/society/` and are owned by `SocietySystem`, which staggers its
subsystems across ticks.

| Area | Implementation |
|---|---|
| **Personality** | 19 traits (sociability, ambition, empathy, aggressiveness, curiosity, courage, honesty, generosity, jealousy, patience, independence, loyalty, competitiveness, risk tolerance, creativity, industriousness, trust, status desire, social need). Each feeds into goal scoring, topic choice, conflict escalation, romance, voting and learning. Experiences cause small drifts. Children inherit a blend of both parents plus variation. |
| **Emotions** | 18 emotions (`Emotions`), each with intensity, a per-emotion half-life and personality-dependent reactivity, plus a list of causes such as "Went hungry with no food in sight". `EmotionModifier` changes decisions: grief and sadness lower work, fear lowers exploring, gratitude raises helping, anger raises confrontation. The inspector shows the emotions with their causes. |
| **Memory** | Many experience kinds (`MemoryPolicy`) with emotion and trait effects. Old memories become vague ("someone"). They are periodically **reinterpreted** in the light of the current opinion of the person. Two people remember the same fight or rumour differently (perspective and valence are personal). |
| **Relationships** | Directional affection, trust, respect, attraction and resentment, plus mutual familiarity and tags (kin, partner, spouse, ex-partner, friend, rival, enemy, mentor, courting). Resentment builds from wrongs and fades over time, faster for patient, empathetic and loyal people. Indexed for O(degree) queries. |
| **Romance** | `RomanceSystem` covers orientation, a stable chemistry "spark", compatibility, respect and age gap. **Longing:** people alone for a long time become less choosy and seek out free singles. The process runs attraction, then flirting (which can be refused), then courting, then a proposal (which can be refused, and depends on family opinion, trust and grudges). After that come a shared household, lifelong partnership, jealousy on witnessing flirts, infidelity, and breakup with a cooldown before rekindling. |
| **Families and demographics** | Conception needs a fertile opposite-sex couple, health, food stores per person, a home with room, and spacing between births. The inspector shows the reason when one is blocked. Pregnancy lasts 3 days, then birth with inherited traits and aptitudes. Life stages are child, youth, adult and elder, with visible size and grey hair. Old-age mortality and a population cap apply. Parent records survive death, which gives a family view in the inspector. |
| **Conversations** | About 25 intents chosen from personality, emotions, relationship, needs, knowledge and society state. Intents are repetition-penalised per pair. Continuity comes from promises (kept or broken later), grudges, reconciliation and debates. People can refuse, disagree, deny, escalate to fights, or be mediated. Each outcome is plain data, validated, then applied: this is the boundary for any future LLM. |
| **Skills and knowledge** | Nine skills improve with practice (diminishing returns), observation and teaching, and decay without use. Inborn aptitudes are inherited. Efficiency depends on skill, tools, life stage, stress and guild membership. There are five discoveries (agriculture, fishing, toolmaking, herbalism, carpentry). They are made independently, spread by teaching, and lost if every knower dies. |
| **Professions and guilds** | A profession is taken up when someone is competent and spends a large share of their recent work on one skill. It is kept for a minimum tenure and changed only for a better craft. Professions bias choices (`ProfessionModifier`). Work crews become guilds with apprenticeship once the tribe has at least 16 people and a master. |
| **Projects** | Villagers propose a farm, workshop, longhouse or shrine from their own concerns. Others support or oppose based on their concerns, relationship to the proposer, rivalry, cost and risk, and group alignment. The government decides. Approved projects get a site and effort. They can fail (deadline), and the proposer gains or loses prestige. |
| **Government** | Influence comes from prestige, respect, skills and endorsements. Government types emerge: none, informal leader, chief (elected in a crisis or as the tribe grows), hereditary succession (lineage tradition), or council (longhouse plus consensus culture). There are challenges, loss of leadership, succession on death, and mediation of disputes. |
| **Groups** | Friend circles, extended families, work crews and guilds, political factions and keepers. They affect conversation partners, votes, apprenticeship and work efficiency. Groups form and drift apart. |
| **Culture** | Norms (cooperation, hierarchy, spirituality, industry, consensus, tradition) drift with events and generations. Traditions include a sharing custom, strict rationing, funeral rites, a harvest feast, evening fires, lineage and peacekeeping. They change rationing, escalation, sharing and succession, and drive ceremonies attended by real villagers. |
| **Economy** | Every resource comes from the world. Tools are made in a workshop from wood and stone and wear out. Tools are held in common or privately depending on the cooperation norm, and are gifted, traded or bartered. Tool access is uneven, so efficiency is uneven. |
| **Chronicle** | `HistoryLog` keeps up to 600 entries (C key) and feeds conversation context ("since Aru died…"). |
| **Save/load** | `SaveSystem` uses a binary Variant encoding (exact floats). The world is regenerated from the seed, and then resources, buildings, villagers, every social and society subsystem and the clock are restored. This is verified with a fingerprint comparison. |
| **Inspection** | Inspector (I): the decision trace (scores and each modifier), needs, emotions with causes, traits, skills, techniques, family and conception blocker, relationships with all five dimensions, groups, memories and recent lines. There is also a tribe panel (T), a chronicle (C) and a relationship line overlay. |

### Test mapping (`tests/society_test.gd`)

Each requirement is checked twice. First the tribe is left alone for 30 days
and the test checks what emerged. Then each mechanism is exercised directly.

| Req. | Emergent check | Mechanism check |
|---|---|---|
| 1 Interaction | ≥30 conversations, ≥6 topics | — |
| 2 Friendship | friend links exist | repeated good times → friend tag |
| 3 Romance | ≥1 new couple formed during the run | interest → flirting → courting → accepted proposal |
| 4 Households | — | the couple share a home |
| 5 Reproduction | ≥1 birth | blocked while food is scarce, possible with food and a home; the child has both parents and kin links |
| 6 Life stages | — | a newborn is a child that doesn't work, then a youth who helps; children are visibly smaller |
| 7 Memories | — | being wronged unlocks "accuse" and lowers trust |
| 8 Emotions | — | grief lowers the score for work |
| 9 Skills | — | practice raises skill and real work speed; teaching raises skill |
| 10 Groups | groups form | group members back each other's proposals |
| 11 Projects | ≥1 completed (when a known technique allows one) | a supported proposal is approved and placed; completion raises prestige |
| 12 Professions | ≥1 profession emerges | steady practice leads to a profession |
| 13 Leadership | — | election with majority backing; an unpopular chief is replaced |
| 14 Disputes | — | after a fight, the person opposes the other's plans and won't settle next to them |
| 15 Different histories | not automated: compare the per-seed summaries below | — |
| 16 Save/load | — | save, reload, fingerprint equality, the tribe keeps living |
| 17 Inspection | — | inspector, chronicle and tribe panel contents |

Mechanisms present in the code but **not** covered by an automated check:
observation learning, skill decay, fear's effect on exploring, project
failure, mediation, guilds, ceremonies and traditions, tool trade, and
technology loss. They appear in long runs and the chronicle but are not
asserted.

These results were measured on the version being committed (30 days each):

| Seed | Pop. | Births | New couples | Government | Professions | Projects |
|---|---|---|---|---|---|---|
| 1234 | 14 | 6 | 1 | chief | 3 | 3 |
| 5 | 13 | 6 | 2 | chief | 4 | 2 |
| 777 | 13 | 5 | 1 | chief | 4 | 3 |
| 42 | 13 | 5 | 3 (1 breakup) | chief | 4 | 3 |
| 2024 | 14 | 6 | 1 | chief | 5 | 3 |
| 99 | 9 | 1 | 1 | none | 5 | 2 |

All six pass with 0 failures. Other results:

- **Determinism:** the state hash is identical at 60 and 23 fps.
- **Performance:** with 208 villagers the mean tick is about 12 ms and the
  maximum about 55 ms (headless).
- **Long run:** a 60-day run (seed 777) went through a full generation. Children
  grew up, courted, partnered and had their own children, founders became
  elders, and leadership changed.

## 9. Limitations and unfinished parts

- **Dialogue is template-based.** No language model is used. The
  `ConversationOutcome.validate()` boundary is ready for one but not connected.
- **Running tasks and graves are not saved.** After loading, villagers decide
  again from their restored state.
- **Economy:** only tools are private or communal goods. Food is always shared
  (with rationing traditions). There are no household stores, markets or
  currency.
- **No defence or warfare.** There is only one tribe by design, and no guards
  or defensive structures.
- **Biology:** biological children require an opposite-sex couple. Same-sex
  couples can form, but there is no adoption yet.
- **Settings:** fishing needs a reachable lake shore. The settlement planner
  can cause a one-off spike of tens of ms when choosing a site.
- **Short time scale.** A year is 2 days, so generations are visible. Founders
  in their forties age out of fertility within about 10–20 days, so population
  growth depends on the next generation.
- **Some emergent events are seed-dependent.** In some seeds no breakups,
  rivalries or council happen within 30 days. That is intended variability,
  but it means not every institution appears in every run.
