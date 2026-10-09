# Future Milestone: Emergent Personalities and Social Simulation

> **Status: specified, NOT implemented.** This document preserves the design
> for a later milestone. The current game only contains the foundational
> gameplay systems, plus the architectural seams listed in
> [Existing seams](#existing-seams-in-the-codebase) so this can be added
> without a rewrite.

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

## 5. Gaps to close before or at the start of this milestone

1. **Full determinism.** Movement integrates per *frame* (scaled delta), so
   positions, and therefore later decisions, vary slightly with frame rate.
   Fix: advance movement in fixed sim steps and interpolate visuals only. This
   is required for replay-style tests of emergent behaviour.
2. **Persistence.** There is no save/load yet. Add a `to_dict()` /
   `from_dict()` per system, keyed by stable ids. Social state must be included.
3. **Probabilistic choice.** The brain picks the highest score plus a small
   jitter. Switch to seeded weighted sampling over the top candidates once
   traits exist.
4. **Blacklist ids.** `VillagerBrain` uses instance ids for its unreachable
   list. Move it to `entity_id` when it becomes part of persistent memory.
5. **Spatial index.** Extract the villager spatial hash from the tribe's
   separation code into a reusable index for proximity queries.

---

## 6. Suggested implementation order

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
