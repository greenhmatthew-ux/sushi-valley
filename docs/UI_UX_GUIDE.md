# Sushi Valley UI, UX, Maps, and Information Architecture

**Status:** locked destination guide, integrated with the active roadmap on 2026-07-13  
**Scope:** single-player pixel-art RPG; desktop, controller, touch, and narrow-screen presentation  
**Execution authority:** [`WORLD_AND_PRODUCT_EXPANSION_PLAN.md`](WORLD_AND_PRODUCT_EXPANSION_PLAN.md)  
**Mechanics authority:** current game data/code plus the learning, combat, gear, Raid, Expedition,
and level-design docs; when a historical plan disagrees with runtime, runtime and tests win

This guide defines how systems are presented; it does not silently change their mechanics or save
schemas. `Current` means present in the Phaser reboot, `Next` means an approved thin-slice target,
and `Later` means destination design only. Priorities are `Essential`, `Recommended`, or `Later`;
complexity is `Low`, `Medium`, or `High`.

The implementation rhythm remains `PLAN -> SMALL BUILD -> MANUAL TEST -> UX PASS -> COMMIT`.
UI-A is being delivered as bounded slices under the active roadmap; completed checkpoints are recorded
below so this destination guide does not overstate unfinished UI behavior.

## 1. Executive design summary

Sushi Valley should have a quiet world screen and a deep but shallowly navigated information layer.
The player sees only health, time/weather, the current tool or combat action, and one useful objective
or context prompt. One Pause Hub then exposes six durable domains: Character, Skills, Journal, Map,
Learning, and System. Stations, shops, dialogue, fishing, and combat remain contextual overlays rather
than duplicate menu branches.

Japanese learning is the game's knowledge progression: encountered language is recorded immediately,
mastered language makes signs, dialogue, maps, items, and clues more understandable. Icons and context
always preserve the main route; a failed recall can reduce a bonus, suggest study, or offer another
route, but cannot permanently block the core single-player game.

| Major decision | Why it suits this game | Reference | Adapt | Do not copy | Phase / priority | Complexity |
|---|---|---|---|---|---|---|
| Minimal world HUD plus one Pause Hub | Preserves authored environments while keeping many systems reachable | CrossCode, Fields of Mistria | Quick tabs, remembered state, clear focus | MMO hotbar/chat density | Next / Essential | Medium |
| Map as layered knowledge | Connects exploration, LDtk truth, completion, and language mastery | CrossCode, TUNIC, Core Keeper | Literal local maps plus illustrated world/region layers | Obscure mandatory navigation | Next / Essential | High |
| Japanese comprehension changes presentation | Makes learning part of exploration instead of a detached quiz app | TUNIC, Pokemon Legends: Arceus | Encountered/mastered states, contextual reveals, research-style records | Permanent failure gates | Next / Essential | High |
| Context-first life skills | Makes farming, fishing, crafting, shops, and NPC routines tactile | Stardew Valley, Fantasy Life i, Moonlighter | One-button world interaction, recipe/item detail on demand | Repeated confirmation dialogs | Current -> Next / Essential | Medium |
| Returning-player summary | Lets a solo player resume after days or weeks without rereading every log | Dragon Quest XI, Hades | Last goal, recent changes, ready activities, one Continue action | Long recap cutscenes | Next / Recommended | Medium |
| No multiplayer scaffolding | Keeps scope focused on a polished solo loop | All references, especially Stardew Valley and RuneScape's solo activities | Async-compatible data only where already useful | Party lists, chat, guild UI, shared-economy assumptions | Current / Essential | Low |

## 2. Core UX principles

1. **World first.** The normal view is scenery and play, not panels.
2. **One obvious action.** Context prompts name the action and input; nearby secondary actions do not
   compete until selected.
3. **Two layers for common work, three maximum for deep reference.** Back always returns one level and
   never unpredictably closes the whole menu.
4. **Progressive disclosure.** Show the decision first, then comparison, formula, history, or lore.
5. **Remember intent.** Reopen the last tab, filter, sort, map zoom, crafting quantity, and tracked goal.
6. **Redundant communication.** Color, icon, label, sound, and motion reinforce important state; color
   alone never carries meaning.
7. **Knowledge without punishment.** Japanese mastery adds understanding, efficiency, optional routes,
   relationships, and rewards; it never removes basic accessibility or the main route.
8. **Input parity.** Anything available on hover is available by focus, click/tap, or a details action.
9. **Return gracefully.** After absence, summarize what changed and offer useful choices rather than
   forcing the player into the oldest tracked task.
10. **No developer language.** Player-facing screens never expose entity IDs, internal flags, raw SRS
    fields, placeholder regions, or implementation terminology.
11. **Visual restraint.** Cozy framing and tactile response support information; decoration never wins
    over readable Japanese, statistics, controls, or comparison.
12. **Honest status.** A prototype map, unavailable activity, or unknown compendium entry looks
    intentionally unknown, not broken or falsely complete.

## 3. Reference-game breakdown

No screen should imitate a single title. Use each reference for one proven strength and reject the
parts that conflict with a readable solo learning RPG.

| Reference | Use for | Adapt | Do not copy |
|---|---|---|---|
| CrossCode | Information architecture, room-connected maps, completion, controller flow | Shallow tabs, local-to-region map drilldown, focus memory | Dense combat HUD or puzzle opacity everywhere |
| Fields of Mistria | Cozy chrome, inventory clarity, relationships, calendar, farming UX | Soft 9-slice frames, legible grids, warm social notes | Decorative density that reduces Japanese legibility |
| Sea of Stars | World map and landmark silhouettes | Miniature destinations and strong route previews | Cinematic scale that hides usable map information |
| Roots of Pacha | Community growth, relationships, gradual regional unlocks | Shared projects with visible world changes | Large dependency trees before the core loop works |
| Chained Echoes | Character, equipment, skills, party-style organization | Comparison panels and grouped progression | Party micromanagement in a solo-character game |
| Cassette Beasts | Compendium, quest tracking, ability configuration | Discovery-rich records and concise loadout editing | Creature-party systems unrelated to this project |
| Fantasy Life i | Professions, crafting, gathering, parallel activities | Clear profession milestones and activity switching | A separate tutorial/menu stack per profession |
| TUNIC | Discovery, maps as knowledge, language comprehension | Labels and clues that clarify through learning | Mandatory obscurity or inaccessible essential text |
| Pokemon Legends: Arceus | Research logs, mastery tasks, collection learning | Encountered vs mastered records and varied optional goals | Checklist volume or repetitive mastery padding |
| Dragon Quest XI | Quest clarity, story recap, returning-player UX | Previously summary and one useful next-step card | Long modal recap before control returns |
| Hades | Relationship cadence, evolving dialogue, codex updates | Memory-based NPC notes and subtle new-dialogue cues | Run-based repetition as the main social structure |
| Moonlighter | Item comparison, shops, selling, loot organization | Fast sell/keep/lock actions and price context | Inventory friction as the entire core challenge |
| Core Keeper | Fog of war, biomes, discovered-world maps | Exploration reveal, personal markers, resource filters | Always-on minimap clutter |
| Animal Well | Interconnected secrets and observation | Optional knowledge layers and memorable shortcuts | Essential progression dependent on opaque secrets |
| Blasphemous 2 | Verticality and connected-world readability | Floor/elevation selection and shortcut language | Severe tone, ornament, or punitive navigation |
| Songs of Conquest | Large-area composition and landmarks | Strong silhouettes, terrain districts, route hierarchy | Strategy-scale UI density in moment-to-moment play |
| Eastward | Town atmosphere, dialogue, environmental density | Framed streets, readable service facades, portrait dialogue | Prop density that blocks navigation or prompts |
| Into the Breach | Compact information certainty | Preview consequences, explicit status icons, short tooltips | Tactical grid language where world interaction is natural |
| Stardew Valley | Daily loop, toolbar, calendar, farming interaction | Fast tool/context actions, readable time pressure, seasonal cues | Excessive slot pressure or hidden quality-of-life rules |
| RuneScape | Skills, activity breadth, quests, long progression | Satisfying levels, milestone tables, broad solo goals | MMO chat/economy UI, grind without authored payoff |

The primary stack is CrossCode for structure, Fields of Mistria for tone, RuneScape for progression,
TUNIC for language-as-knowledge, and Sea of Stars for landmark presentation. The other games are
specialists, not equal visual directions.

## 4. Recommended UI architecture

### Menu hierarchy

```text
Pause Hub
|-- Character
|   |-- Status & derived-stat explanations
|   |-- Equipment & comparison
|   `-- Bag, quick slots, storage link
|-- Skills
|   |-- Combat abilities & loadouts
|   |-- Professions & mastery
|   `-- Milestones & next unlocks
|-- Journal
|   |-- Quests, Requests, Community Goals, Personal Goals
|   |-- Raids and Expedition records
|   |-- NPC relationships, calendar, mail/messages
|   `-- Achievements and activity records
|-- Map
|   |-- Local / Town / Interior / Dungeon floor
|   |-- Region / World / Fast travel
|   `-- Filters, legend, completion, markers
|-- Learning
|   |-- Japanese Journal / Daily Review
|   |-- Vocabulary / Grammar / Listening
|   `-- Recent, Favorites, Weak Areas, Session History
`-- System
    |-- Settings, controls, accessibility
    |-- Tutorials & help
    |-- Save/load and return-to-title
    `-- Return-to-game summary/history

Context overlays (not Pause Hub duplicates)
|-- Dialogue / relationship update
|-- Shop / buyback / storage
|-- Crafting / cooking / crop picker
|-- Fishing / gathering result
|-- Combat / Raid / Expedition briefing and result
`-- Recall / reading / sentence breakdown
```

Direct shortcuts open the relevant domain without adding hierarchy: `I` Bag, `M` Map, `J` Journal,
`K` Skills, `N` Learning. Controller shoulders switch domains, triggers switch subtabs, and Back
returns one level. On touch, a six-icon bottom/domain rail replaces keyboard shortcuts.

### Navigation depth targets

Opening a direct panel counts as layer 1; a subtab/detail is layer 2; a focused history or breakdown
is layer 3.

| Task | Target layers | Rule / risk |
|---|---:|---|
| Resume, interact, use selected tool | 0 | Never require a menu |
| Open Bag, Map, Journal, Skills, Learning | 1 | Direct input and Pause Hub route both exist |
| Equip/compare a recent item | 2 | Recent filter and one-button compare; no Character -> slot -> Bag -> item chain |
| Track a quest/request | 2 | Journal list -> detail; track action remains pinned |
| Review due Japanese | 1 | HUD due cue/shortcut opens a prepared session |
| Inspect vocabulary/grammar detail | 2 | Learning collection -> entry; sentence breakdown may be layer 3 |
| Craft at a station | 1 | World interaction opens the recipe list directly |
| Find a service and route to it | 2 | Map -> filter/result; selecting closes to a navigation cue |
| NPC memory and schedule | 2 | Journal -> NPC; cross-links from dialogue update |
| Fast travel | 2 | Map -> destination confirmation; locked reason shown before confirm |
| Settings/remap | 2-3 | System -> category -> binding; high depth is acceptable only here |
| Save/load | 2 | System -> save slots; autosave remains default |

**Depth risks:** Journal and Learning can become encyclopedias. Both require search, favorites,
recent/history views, breadcrumbs, remembered filters, and cross-links. Compendium types should live
under Journal/Learning rather than becoming five top-level tabs. Crafting and Cooking remain one
station shell with a category switch, not parallel menu trees.

### Current-to-destination migration

| State | Reality / action |
|---|---|
| Current | `UIScene` owns HUD and overlays. `GameMenu` has Character, Bag, Skills, Quests, Map, World, Compendium, Notebook, Travel, Settings. Dialogue, Learn, Reading, Shop, Craft, GE, Storage, and touch controls exist. |
| Next | Introduce shared tokens, modal coordination, focus/navigation contracts, item comparison, and grouped domain labels without rewriting all panels at once. |
| Later | Split the large `GameMenu` after its layout contract stabilizes; add relationship/community/calendar/mail/achievement surfaces only when their underlying data is real. |

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Six-domain Pause Hub with direct shortcuts | Keeps broad systems findable without a 15-tab rail | CrossCode, Chained Echoes | Adapt grouped tabs; avoid deep nested lists | Next / Essential | Medium |
| One shared panel shell | Makes shop, craft, storage, Journal, and Learning predictable | Fields of Mistria, Into the Breach | Pinned header/footer and one scroll owner; avoid modal-within-modal | Next / Essential | Medium |
| Remembered menu state and favorites | Speeds repeated solo routines | RuneScape, Fantasy Life i | Persist harmless UI preferences; avoid changing gameplay state | Next / Recommended | Low |

## 5. HUD design

### Visibility contract

| Element | Visibility | Behavior |
|---|---|---|
| HP/primary resource and level | Always, but dim when full and safe | Top-left compact group; expands in combat/danger |
| Time, date, season, weather | Always in life/town play; optional in Expeditions | Top-right compact clock; weather icon plus text alternative |
| Current tool/weapon and quick item | Always when relevant | Bottom-left or bottom-center; hides empty slots |
| Context action | Interaction only | Bottom-center: verb + object + current input glyph |
| Tracked objective/navigation cue | Temporary or player-pinned | One objective, distance/region cue; no full checklist |
| Learning cue | Interaction/temporary | Short word/reading reveal near its source; expands only on request |
| Enemy target, resource bars, abilities | Combat only | Clear telegraphs, cooldowns, target intent, item access |
| Status effects | Only while active | Icon, short label, duration/rule in focus tooltip |
| Companion | Only when a real companion is active | HP/state and one command; no empty party frames |
| Loot, XP, skill levels, relationship notes | Queued temporary | One reserved toast lane; combine duplicates |
| Minimap | Hidden by default, customizable | Compact navigation indicator is default; minimap can be enabled |
| Coins, due reviews, objective, clock | Individually customizable | Presets: Minimal, Standard, Learning, Combat |

The current 460x56 all-in-one bar should evolve into smaller anchored groups so the center/top of the
world remains visible. The HUD disappears behind all modals. Notifications queue, aggregate repeated
loot/XP, and never overlap dialogue, combat actions, safe-area cutouts, or touch controls.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Auto-dimming modular HUD | Preserves environmental art without hiding important danger | Fields of Mistria, CrossCode | Adapt contextual groups; avoid MMO permanence | Next / Essential | Medium |
| One tracked objective plus compass cue | Gives direction without a checklist simulator | Dragon Quest XI, Pokemon Legends: Arceus | Adapt clear reminders; avoid a screen of pins | Next / Essential | Medium |
| Queued feedback lane | Makes rewards legible and calm | Hades, Into the Breach | Aggregate repeated drops; avoid notification rain | Next / Recommended | Medium |

## 6. Map system

### Map layers and representations

| Map | Representation | Contents |
|---|---|---|
| World | Illustrated/node hybrid | Regions, major routes, production/frontier truth, miniature landmarks, fast travel |
| Region | Hybrid illustrated map over LDtk connectivity | Local areas, exits, activity/service clusters, completion, learned labels |
| Local/town | Literal LDtk-derived map | Player, routes, doors, landmarks, NPC/service/filter results, personal markers |
| Expedition/dungeon | Literal discovered rooms with node connections | Fog, floor selector, entrance/retreat, objectives, shortcuts, found secrets |
| Interior | Only for multi-room or navigational interiors | Doors, floors, services; omit tiny one-room homes |
| Fast travel | Filtered world/region layer | Unlocked stops, cost/rules, destination preview, return route |

LDtk is spatial authority. Map UI reads level bounds, tile layers, exits, spawns, landmarks, floors,
services, and semantic entities; it never recreates coordinates in `GameMenu.ts`. Fog is stored as
discovered cells/rooms, not screenshots. Automatic notes record entrances, blocked gates, services,
resources after first use, NPC schedule clues, and language labels after encounter/mastery. Players
may place named/color/icon markers with a conservative cap.

Filters are grouped and mutually understandable: Objectives; NPCs; Shops/Services; Activities;
Gathering; Learning; Entrances/Fast Travel; Secrets/Completion. `All` does not mean every icon at once;
it means the curated standard layer. Selecting a result centers it, shows its unlock/knowledge state,
and offers Track/Untrack, not an unexplained teleport.

Completion separates `Explored`, `Activities`, `Secrets`, and `Language`; it never counts unknown
future content. Learned vocabulary can reveal labels or improve descriptions, but icons and route
shapes keep essential navigation accessible.

### Mapshot/showcase mode

`Later` mapshot mode uses an offscreen Phaser scene and orthographic camera to render an entire LDtk
level in deterministic chunks, then stitches those chunks into a high-resolution PNG. It can hide all
UI or include selected overlay layers: labels, routes, entrances, NPC homes, services, objectives,
completion, and collision/debug data. Export presets: Clean Art, Player Guide, Design Review, and
Completion Map. It must render source-resolution pixels at integer scale, wait for every region asset,
and never depend on the current viewport or player camera.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Literal local + hybrid region + illustrated world maps | Each scale answers a different navigation question | CrossCode, Sea of Stars, Core Keeper | Adapt drilldown; avoid one unreadable map for every scale | Next / Essential | High |
| Knowledge-aware labels and notes | Directly connects Japanese learning to exploration | TUNIC, Pokemon Legends: Arceus | Add clarity/rewards; never hide essential icons | Next / Essential | High |
| Chunked mapshot exporter | Supports level review, marketing, and full-map references | Songs of Conquest, stitched community maps | Render LDtk truth; avoid viewport screenshots | Later / Later | High |

## 7. Japanese-learning UX

### Knowledge model

Every language unit has at least two independent states:

- **Encountered:** seen in a real context; journal records source, kana/kanji, reading, meaning, audio,
  sentence, and where it appeared.
- **Learned/mastered:** SRS evidence reaches a threshold; the world may show clearer translation,
  richer map labels, quicker item recognition, optional clues, social nuance, or a bonus route/reward.

Vocabulary can originate from dialogue, signs, items, recipes, combat intents, quests, environments,
shops, and NPC memories. Grammar records the sentence pattern plus a breakdown and multiple contexts.
Listening entries preserve replayable native audio when licensed/source-backed. The Learning domain
offers Daily Review, Recent, Favorites, Weak Areas, Vocabulary, Grammar, Listening, Personal Lists,
and Session History. It syncs through the shared `LearningProfile`; offline actions queue and reconcile
without losing local progress.

Display settings are global and quick-adjustable: Japanese only; Japanese + furigana; Japanese +
tap/focus translation; beginner assist with temporary romaji. Romaji is never the long-term default.
Audio replay, text speed, sentence breakdown, translation assistance, and simplified learning mode
remain available without lowering combat or exploration difficulty.

### World comprehension ladder

1. Unknown text retains its Japanese silhouette plus an accessible icon/context cue.
2. Encountered text can reveal a reading or one key meaning on focus.
3. Practiced text gains a stable translation/context note.
4. Mastered text reads naturally in dialogue/maps and may expose optional humor, clues, affinity, or
   efficiency bonuses.

Mandatory early mechanics are short recognition/recall at safe moments, contextual word discovery,
and a prepared daily review. Listening production, typed answers, advanced kanji, custom lists, and
strict no-assist modes are optional. Main-story gates always allow retry, study, an alternate task, or
an accessible hint; one wrong answer never consumes a unique reward or strands the player.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Encountered vs mastered knowledge | Makes discovery rewarding before memorization is complete | TUNIC, Pokemon Legends: Arceus | Context-rich records; avoid binary known/unknown punishment | Next / Essential | High |
| Contextual reveal with icon redundancy | Makes the world more understandable without blocking play | TUNIC, Dragon Quest XI | Learning adds nuance; essential actions remain clear | Next / Essential | High |
| Prepared daily review plus weak-area shortcuts | Connects the game to the wider learning app efficiently | RuneScape routines, SRS practice | Short sessions and resume state; avoid compulsory grind quotas | Current -> Next / Essential | Medium |

## 8. Combat UX

The shipped combat rules remain authoritative. The current menu/turn-resolution combat should first
gain clearer intent, status, comparison, item choice, victory exit, and Japanese pacing. If action
combat is later approved, the same HUD contract extends to targeting, telegraphs, cooldowns, weapon
switching, companion commands, dodge/parry timing, pause/slowdown, and damage-direction cues; the UI
guide alone does not authorize an engine rewrite.

### Combat presentation

- Player group: HP, energy/stamina/mana, compact status effects, selected weapon, and quick item.
- Enemy group: readable name/level, health only after engagement, icon + shape telegraphs, intent,
  break/stagger state, and accessible danger contrast.
- Action group: equipped abilities only, cooldown/cost, current target, input glyph, and one-line
  consequence preview. Long rules stay in focus tooltips or Pause.
- Boss group: named phase, large but bounded health bar, phase cue, important mechanic, and optional
  learning resonance; no unrelated HUD modules.
- Feedback: restrained hit stop/shake, damage numbers that can be reduced/disabled, clear miss/block/
  weakness text, combo/timing cue, and immediate reward/continue path after victory.

### Ranked Japanese integration methods

| Rank | Method | Use | Phase |
|---:|---|---|---|
| 1 | Redundant intent vocabulary | Enemy shows icon/animation plus a learned Japanese direction, element, or action word | Early / Essential |
| 2 | Ability-language resonance | Recognizing a known word improves timing window, Focus gain, or optional bonus without pausing | Early / Recommended |
| 3 | Pre-fight/between-wave recall | One short prompt during natural downtime changes a bonus, clue, or opening state | Early / Essential |
| 4 | Post-fight micro review | Revisit one word actually used in the encounter, then continue immediately | Next / Recommended |
| 5 | Listening/production challenge | Optional advanced boss modifier or training room, with slowdown/pause assist | Later / Later |

Never stop every attack for a quiz. Early combat uses recognition with icons; production and listening
belong in opt-in training, safe pauses, or advanced modifiers. Accessibility can slow telegraphs,
increase timing windows, reduce flashes/shake, pause on ability selection, and repeat audio.

### Ability identity contract

**No new attack, spell, or skill may replace an older one by being the same action with larger
numbers.** Every active ability must earn its slot through at least two meaningful differences:

- delivery: line, cone, arc, point-blank, projectile, ground zone, chain, summon, stance, or counter;
- timing: fast interrupt, charged commitment, delayed detonation, channel, reaction, or combo finisher;
- purpose: burst, sustain, control, armor break, displacement, defense, mobility, setup, payoff, or rescue;
- resource behavior: generates, spends, reserves, refunds, converts, or risks a resource differently;
- target rule: single, clustered, marked, wounded, airborne, behind cover, self, ally, or environmental;
- style: weapon family, elemental interaction, status package, animation rhythm, and player positioning.

Higher tiers may unlock augments or alternate follow-ups for an existing favorite, but the original
remains viable because of cost, speed, safety, range, or build synergy. The ability screen labels each
skill's role and compatible tags; it does not present a red/green damage ladder as the main choice.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Sidegrade-first ability tiers | Keeps all earned tools relevant and makes builds expressive | CrossCode, Chained Echoes, Hades | Distinct geometry/timing/setup; avoid rank-II replacements | Next / Essential | High |
| Six-slot loadouts with clear role tags | Creates meaningful preparation without exposing every skill at once | Cassette Beasts, CrossCode | Tags and saved presets; avoid one mathematically correct bar | Next / Essential | Medium |

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Intent-first combat HUD | Makes action/turn decisions readable without a dense skill spreadsheet | Into the Breach, CrossCode | Preview costs/effects; avoid permanent panels | Next / Essential | Medium |
| Icon-redundant Japanese intent | Uses language during engagement without surprise failure | Hades, TUNIC | Reward recognition; avoid quiz interruption | Next / Essential | Medium |
| Optional slowdown/pause assists | Preserves accessibility and learning time | Dragon Quest XI, modern action RPG assists | Player-controlled support; avoid tying assist to lower rewards | Next / Recommended | Medium |

## 9. Inventory and equipment

Use a generous stack-based bag with separate key-item, currency, recipe, and language collections.
Do not use weight-per-item simulation. The current 300-unit soft encumbrance remains until a dedicated
save-safe migration; the destination is expandable unique-stack capacity with overflow sent to a
clearly announced parcel/storage queue instead of rejecting ordinary loot.

### Bag model

- Categories: All, Recent, Favorites, Equipment, Tools, Consumables, Materials, Seeds/Farming,
  Fish/Food, and Quest Items.
- Every cell shows icon, quantity, equipped/quick-slot state, new pip, and favorite/lock marker.
  Rarity uses a named tier and border motif as well as color.
- One consistent action strip: `Use / Equip / Assign / Favorite / Lock / Move / Split / Sell`.
  Disabled actions explain why.
- Search covers localized name, Japanese name/reading, type, slot, and discovered tags. Filters, sort,
  grid position, and last selected item are remembered.
- Storage shares the same grid and controls. `Deposit materials` preserves favorite, locked, equipped,
  and quick-slotted items. Home/town crafting may pull from nearby storage and names the source.
- Shops use Buy, Sell, and same-day Buyback; selling shows exact totals and rejects locked/quest items.

### Equipment

Keep the current paper doll and readable slots. Selecting gear previews the target slot and shows only
changed stats first (`current -> new`), with Full Details for formulas. Quick Equip changes state;
Compare never does. Requirements use player language. Set bonuses show active pieces/required pieces.
Saved loadouts are `Later` and must not duplicate or destroy items.

### Consumable identity contract

Food and potions cannot remain a pile of weaker healing numbers. Each family needs a different use
window, stacking rule, and reason to craft:

| Family | Purpose | Rule |
|---|---|---|
| Emergency potion | Immediate survival | Fast, limited shared potion cooldown; scarce/expensive |
| Snack | Small safe sustain | Cheap modest heal outside danger or slow use during combat |
| Meal | Preparation/build choice | One long-duration meal buff; no instant burst healing |
| Tonic | Resource tempo | Restore/generate Energy, Focus, stamina, or cooldown tempo |
| Remedy | Counterplay | Cleanse or prevent one named status family |
| Resistance brew | Encounter preparation | Element/biome/boss-specific mitigation with clear duration |
| Gathering dish | Life-skill utility | Yield, quality, weather, bait, mining, farming, or crafting niche |
| Comfort food | Town/social value | Relationship, rest, morale, or festival/quest purpose |

Every consumable tooltip states `When to use`, effect, duration, stack rule, cooldown family, and current
active meal. Redundant items are consolidated or assigned a real niche while preserving save IDs through
data migration/aliases. Combat has a player-chosen item bar; it never auto-consumes the most valuable item.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Generous stack bag, no weight math | Broad gathering/learning play should not stop for inventory chores | Fields of Mistria, RuneScape | Strong storage and filters; avoid 28-slot friction | Next / Essential | Medium |
| Persistent detail and comparison pane | Makes gear/loot decisions fast on every input | Moonlighter, Chained Echoes | Changed stats first; avoid spreadsheet overload | Next / Essential | Medium |
| Distinct consumable families | Gives Cooking/Alchemy and shops tactical value | Stardew Valley, Fantasy Life i, Hades | Preparation plus emergency niches; avoid same heal at five prices | Next / Essential | High |

## 10. Quest, Raid, and Expedition systems

The player-facing **Journal** may contain Quests, Requests, Community Goals, Raids, Expeditions,
Learning Goals, and Personal Goals. Existing system IDs/save data keep their names until a deliberate
migration; presentation must not silently rename stored mechanics.

| Type | Acceptance and tracking | Markers | Completion / failure / return |
|---|---|---|---|
| Story Quest | Explicit story dialogue; one primary tracked objective | Landmark/area hints, exact pin only when known | Strong recap and next chapter; no abandonment |
| Side Quest | NPC/world discovery; opt-in Track | Region/area clue first | Reward preview; may pause and resume without decay |
| NPC Request | Short contextual ask | NPC and broad source area | Compact toast/journal memory; expires only if clearly seasonal |
| Community Goal | Project board and world need | Contribution sites | Visible world change; partial contribution persists |
| Daily/repeatable | Activity context, not an inbox flood | No pin unless tracked | Quiet reset; missed tasks carry no penalty |
| Raid | Structured authored mission briefing | Entry and staged objectives | Loadout/reward preview, explicit retry/retreat, saved result |
| Expedition | Dungeon/adventure preparation | Discovered room/floor map | Checkpoints, safe retreat, resume/abandon rules, run record |
| Learning Goal | Journal suggestion or player-created | Source/location links | SRS/session summary; never blocks the main story permanently |
| Personal Goal | Player pin/favorite/progress target | Optional custom marker | Player completes, edits, or removes freely |

Track at most one main and two optional goals on the HUD. The Journal can recommend three useful next
actions, but never turns every activity into a mandatory checklist. Objectives use verbs and context,
rewards show before commitment, and a returning player sees `Previously`, current state, and the next
safe action. Abandoned content remains in an Archive with its last known state and a Resume path.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| One Journal with typed records | Keeps different activity promises clear without top-level clutter | Dragon Quest XI, Cassette Beasts | Strong type labels and resume state; avoid one undifferentiated quest list | Next / Essential | Medium |
| Area clues before exact pins | Preserves discovery while preventing aimless wandering | TUNIC, Pokemon Legends: Arceus | Graduated hints; avoid compulsory GPS trails | Next / Recommended | Medium |
| Explicit Raid/Expedition contracts | Prevents two major modes from feeling interchangeable | Current design docs, Chained Echoes | Briefing, failure, retreat, rewards; avoid hidden rules | Current -> Next / Essential | Medium |

## 11. Relationships

Relationships are evolving shared histories, not exposed hidden arithmetic. Each known NPC page shows
portrait, role, broad relationship chapter (`New Face`, `Acquaintance`, `Trusted`, `Close`), two or three
meaningful memories, current personal concern, discovered preferences, recent gifts, important dates,
social connections, schedule hints, service/community contribution, and Japanese encountered together.

Do not show raw favor points as the primary representation. A narrative ribbon may say what kind of
moment could advance the relationship. Schedules become discovered human hints (`usually at the forge
on odd days`), not raw coordinates. New-dialogue indicators appear only for genuinely new conversation.
Dialogue history supports search, translation, and audio replay without exposing dialogue-node IDs.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Memory/chapter relationship journal | Supports attachment and returning-player recall | Hades, Fields of Mistria | Evolving notes and cadence; avoid visible optimization math | Next / Recommended | Medium |
| Community contribution changes the world | Connects relationships to the solo world loop | Roots of Pacha | Small persistent upgrades; avoid giant dependency boards | Current -> Next / Recommended | High |

## 12. Skills and professions

Use three progression families rather than one enormous web:

1. **Combat build:** level, role, attributes, equipment, active abilities, loadout tags.
2. **Life professions:** Gather (Farming, Fishing, Mining, Woodcutting, Gathering), Make (Cooking,
   Smithing, Crafting, Alchemy), Adventure (Combat, Exploration, Trading), and Community.
3. **Japanese mastery:** Reading, Listening, Vocabulary, and Grammar evidence from encounters/reviews.

The current combined tracks may remain for the MVP; the UI names contributing activities. Split a track
only when each side has distinct unlocks and loops. Every page shows current level/progress, last XP
source, next concrete unlock, nearby recommended activities, milestone history, known outputs, and later
specialization. Mastery after cap uses authored challenges, not another hidden prestige currency.

Combat ability respec is free during onboarding and later available at a safe hub with full preview;
unlocked abilities are never deleted. Japanese mastery is never purchased with combat points and uses
`Encountered / Learning / Familiar / Mastered` rather than one misleading score.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Milestone-first skill pages | Modernizes RuneScape's satisfying long growth | RuneScape, Fantasy Life i | Next unlock and activities; avoid empty thin skill bars | Next / Essential | Medium |
| Separate combat/life/language families | Prevents one overwhelming dependency graph | Chained Echoes, TUNIC | Cross-links through activities; avoid a universal skill currency | Next / Essential | Medium |

## 13. New-player and returning-player flows

| Moment | Teach / show | Rule |
|---|---|---|
| First 15 minutes | Move, interact, one NPC, one tool, one contextual Japanese word | One prompt at a time; no full menu tour |
| First hour | Town loop, farm/gather action, shop/craft result, first choice of goal | Unlock domains when they become useful |
| First combat | Intent, attack/defend, item, victory exit | Recognition cue is redundant and low-pressure |
| First life skill | Action -> feedback -> item/XP -> visible next unlock | Do not open three progression screens |
| First learning interaction | Encountered word, optional audio, short recall, journal record | Explain why the world changed |
| First town | Landmark, service facades, Journal/Map cross-link | Arrival faces a readable destination |
| First Quest | Accept/decline, Track, area clue, reward | Journal entry stays concise |
| First Raid | Briefing, special rules, loadout, retry, rewards | Separate from ordinary Quest UI |
| First Expedition | Prepare, map/fog, checkpoint, retreat | Resume state explained before entry |
| First major menu unlock | Open directly to the new useful panel | Never display every future tab disabled |

After one day, show a tiny `Since last time` card only if something changed. After one week, show
Previously, current tracked goal, ready farm/resources, due review, recent unlocks, and three optional
next actions. After one month, add a short controls reminder and world-state recap. `Continue` is always
the primary action; recommendations never auto-start content. Saved filters, loadout, last station
category, map zoom, and tracked goal remain intact.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Contextual unlock tutorials | Teaches a broad game without walls of text | Stardew Valley, Fantasy Life i | One real action per lesson; avoid preloading rules | Current -> Next / Essential | Medium |
| Absence-scaled return summary | Makes long-term solo play comfortable | Dragon Quest XI, Hades | Three useful choices; avoid forced recap sequence | Next / Recommended | Medium |

## 14. Controls

The destination contract is one abstract action vocabulary with current-device glyphs. Current support
covers keyboard/mouse and touch-like input for the world prompt, title, dialogue confirm hint, HUD
hotkey strip, and virtual controls. Existing panel/minigame copy is not yet uniformly adopted, and the
controller column below remains destination-only until controller actions are real.

| Action | Keyboard/mouse | Controller | Touch |
|---|---|---|---|
| Move | WASD/arrows | Left stick/D-pad | Virtual stick |
| Interact/Confirm | E, Space, Enter, click | South button | Tap / `USE` |
| Back/Cancel | Escape, Backspace | East button | Back control |
| Pause Hub | Tab | Menu/Start | Menu icon |
| Map / Journal / Learning | M / J / N | View plus radial/domain shortcut | Domain icons |
| Quick slots | 1-4 | D-pad or bumper radial | Thumb-zone quick buttons |
| Tool/weapon cycle | R / wheel | Right bumper | Tap selected tool |
| Details/context | F / right click / hover | West button / stick click | Long press |
| Tabs/pages | Q/E, Page Up/Down | Bumpers/triggers | Tap/swipe |

Bindings are remappable. Exactly one element and one modal own focus. Opening a modal stores world/menu
focus; Back closes tooltip -> context menu -> subpage -> hub -> game. Focus starts on the safest useful
action, destructive defaults to Cancel, and controller neighbors are authored rather than guessed from
geometry. Drag-and-drop always has a select-then-place alternative.

Touch uses 44 CSS-pixel minimum targets (48-56 preferred), safe-area insets, thumb-zone movement/action,
full-screen menu layouts, and bottom-sheet details. Long press opens details and never destroys/sells.

## 15. Accessibility

- UI scale 80/100/120/140/160%, independent body-text scale, high contrast, opaque panel option,
  dyslexia-friendly Latin font, and legible Japanese fallback.
- Colorblind presets plus icon/pattern/text redundancy; color never carries state alone.
- Reduced motion, flash reduction, screen-shake Off/Low/Full, damage-number density, camera motion,
  instant menu transitions, and ambient/water animation intensity.
- Full remapping, hold/toggle alternatives, long-press timing, one-handed touch layout, virtual-stick
  size/position/dead zone, vibration controls, and no required mashing or simultaneous holds.
- Text speed, instant/manual/auto advance, searchable dialogue history, subtitle controls, separate
  voice/pronunciation/audio channels, visual audio cues, and replay without penalty.
- Furigana Off/New/All; translation Hidden/On request/After attempt/Always; beginner romaji assist;
  simplified learning mode and reduced prompt timing pressure.
- Independent combat assistance for damage, aggression, telegraph time, timing windows, targeting,
  command pause/slowdown, encounter retry, and language-prompt frequency. Assists do not reduce rewards.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Independent assist controls | Combat, Japanese, and presentation difficulty are different needs | Hades, Dragon Quest XI | Granular previews; avoid one opaque Easy mode | Next / Essential | Medium |
| Japanese-specific display assistance | Preserves learning goals and readable access | TUNIC plus modern localization practice | Player-controlled reveal; avoid forced romaji | Next / Essential | Medium |

## 16. Visual design system

Evolve the current dark navy/warm gold UI with pixel-crafted nine-slice chrome, warm material accents,
and highly legible body/Japanese text. Japanese inspiration comes from restraint, material warmth, clear
seasonal color, and authored iconography—not generic stereotypes or decoration on every edge.

| Token | Value | Use |
|---|---:|---|
| `surface.backdrop` | `#05080C` at 66% | modal dim |
| `surface.base` | `#141B24` | panels |
| `surface.raised` | `#1B2530` | cards/rows |
| `surface.deep` | `#0E151D` | inset areas |
| `border.subtle` / `strong` | `#2A3744` / `#3C5168` | dividers/focus containers |
| `text.primary` / `muted` | `#EEF1F5` / `#9FB0C3` | hierarchy |
| `accent.gold` | `#FFD27D` | focus/headings |
| `state.success/info/danger` | `#9BE7A3` / `#9FD6FF` / `#FF9B9B` | states |
| `learning.violet` | `#C27BA0` | learning identity |

- Panels align to integer pixels, use an 8px spacing unit, 1-2px inner border, and restrained shadow.
- Buttons expose idle, hover, focus, pressed, selected, disabled, loading, destructive, error, and
  success states. Focus uses outline/cursor shape as well as color; disabled explains why.
- Tooltips wait about 250ms, stay in safe bounds, and never cover selection. Progress bars label values
  when decisions depend on them. Rarity uses name + motif + optional color.
- Pixel display font is for short headings; body/UI uses a legible sans. Japanese fallback:
  bundled Japanese font -> `Noto Sans JP` -> `Yu Gothic UI` -> `Meiryo` -> sans-serif.
- At the 800x600 logical size: 22px title, 16px section, 14px body, 12px metadata minimum. Narrow
  screens reflow instead of shrinking.
- Motion: 60-90ms press, 80ms focus, 120-160ms panel, 180ms toast in/out; none blocks input.
- World and icons use nearest-neighbor integer scaling. UI text renders at target resolution.

| Recommendation | Why | Reference | Adapt / avoid | Phase / priority | Complexity |
|---|---|---|---|---|---|
| Shared tokens and nine-slice shell | Makes many systems cohesive without rewriting mechanics | Fields of Mistria, Sea of Stars | Crafted edges and readable interiors; avoid ornate content loss | Next / Essential | Medium |
| Hybrid pixel/body typography | Protects Japanese and small-screen readability | Into the Breach, Eastward | Pixel identity in chrome; avoid pixel font paragraphs | Next / Essential | Medium |

## 17. Wireframes

These diagrams define hierarchy, not final art.

### Normal gameplay HUD

```text
HP 42/50 · Lv 12                                  Day 8 · Spring · Cloudy · 14:20
[weapon/tool] Energy                              [small compass: tracked place]

                         WORLD

                         [E / A / USE] Talk to Bramble
                         森  もり  forest     [temporary cue]

[1 Tool] [2 Food] [3 Favorite] [4 Favorite]       +12 Fishing XP · River Fish x1
```

### Combat HUD

```text
River Kappa · Lv 12        HP ███████░░        Intent: sweeping water arc
Status: Exposed                            [icon + shape, not color alone]

                         COMBAT SPACE

HP 42/50 · Focus 3/5       Attack  Guard  Skill  Item  Inspect  End
Selected: Tide Step · flank movement + counter window            [Pause/Slow]
```

### Inventory

```text
Bag · All Recent Favorites Gear Food Materials Seeds · Search · Sort
24 stacks · 132 units                                      1,240 coins
+------------------------------------+-------------------------------+
| [icon][icon][icon][icon][icon]     | Moonsteel Hookblade          |
|  x12    ★     E                    | Arc weapon · Rare · Lv 24    |
| [icon][icon][icon][icon][icon]     | ATK +4 · SPD -1              |
| [icon][icon][icon][icon][icon]     | Style: pull -> close strike  |
|                                    | Japanese name/reading [audio]|
+------------------------------------+-------------------------------+
  Equip  Assign  Favorite  Lock  Move  Split  Back
```

### Equipment

```text
Character · Equipment
[Head] [Amulet]          Stats             Current -> Preview
    +--------+           HP 86             ATK 18 -> 22  +4
[W] | player | [Body]    ATK 24            SPD  9 ->  8  -1
[H] | sprite | [Legs]    DEF 13            Requires Lv 24
[R] +--------+ [Feet]    SPD  9            Set 1/2 inactive
  Equip selected · Unequip · Open Bag · Full details
```

### World map

```text
World · 42% discovered                 Search · Filters · Legend
+----------------------+-----------------------------------------+
| Sushi Valley   68%   |        illustrated region nodes         |
| Northern Reach 21%   |    landmarks + honest known routes      |
| Eastern Wilds    ?   |           unknown/fogged space          |
+----------------------+-----------------------------------------+
  Objectives  Services  Learning  Resources  Secrets  Travel
```

### Region map

```text
Sushi Valley · Region · Surface
Valley Hub ---- Whispering Woods ---- Mountain Pass ---- ?
    |                    |
Greenhouse          Fishing Cove
Landmarks 4/7 · Activities 3/5 · Language 8/12 · Secrets 2/?
```

### Local map

```text
Whispering Woods · Local       [-] 100% [+]       Floor 1
+---------------------------------------------------------+
| literal LDtk-derived ground, paths, shore, doors, player|
| discovered NPC/service/resource icons and personal pins |
+---------------------------------------------------------+
  Track route · Place pin · Center · Legend · Showcase
```

### Quest log

```text
Journal · Story Side Requests Community Raids Learning
+---------------------------+----------------------------------+
| > Broken Mountain Path    | Kaji needs moonwood supports.    |
|   Hana's Garden           | [x] Speak to Kaji                |
|   Dock Lessons            | [ ] Gather Moonwood 2/4          |
|                           | [ ] Return to the forge          |
|                           | Reward: 300c · named recipe      |
+---------------------------+----------------------------------+
  Track · Show area · Archive · Back
```

### Raid screen

```text
Raid: Pantry Oni Preparation · Recommended Lv 12 · about 15 min
Rules: staged kitchen mission · food recall · boss · checkpoints
+-------------------------------+-------------------------------+
| Current loadout               | First-clear rewards           |
| six abilities + item slots    | recipe · materials · story    |
| Japanese focus: food words    | Retry: checkpoint             |
+-------------------------------+-------------------------------+
  Practice terms · Prepare · Begin Raid
```

### Expedition screen

```text
Expedition: Forest Lunchbox · Hand-authored route · 1 floor
Objective: recover lunchbox · Current checkpoint: encounter cleared
Supplies: Food 6 · Tonics 2        Hazards: thorns · Forest Wraith
Rewards: Moonwood · recipe · record
  Resume · Prepare · Retreat safely · Abandon record
```

### Japanese Journal

```text
Learning · Today Vocabulary Grammar Listening Reading
Ready when you are: 12         [Start 5-card review]
+-----------------------------+--------------------------------+
| Recent                      | Weak areas                     |
| 川 · Fishing Cove           | long vowels · counters        |
| 鍛冶 · Kaji's forge         | listening: shop phrases      |
| 森 · Woods sign             | [Practice weak areas]        |
+-----------------------------+--------------------------------+
Encountered 184 · Learning 62 · Familiar 48 · Mastered 74
```

### Vocabulary entry

```text
川 · かわ · river                         Favorite · Audio
State: Familiar · next review tomorrow
Encountered at: Woods sign · Bramble dialogue · Region Map
Example: 川で魚を釣ります。  I fish in the river.
  Sentence breakdown · Add to list · Show locations · Practice
```

### Grammar entry

```text
～で · place of action                              Audio
Formation: place + で + action
川で魚を釣ります。   [川で] [魚を] [釣ります]
Seen in: fishing lesson · Bramble conversation · 4 more
  More examples · Practice · Related: ～に / ～を
```

### Review session

```text
Review 3/10 · Listening                         Exit and save
                          [Play audio]
                   What did the speaker say?
                [A 川] [B 山] [C 森] [D 海]
                    Hint · Replay · Slow

After: Correct · 川（かわ）river · example · breakdown · audio
       Again · Hard · Good · Easy
```

### NPC relationship page

```text
Bramble · Trail Crafter · Trusted             New dialogue
[portrait] “Bramble trusts you with the cedar workshop.”
Recent memories                    Discovered preferences
* Repaired the trail loom          * Likes moonwood tools
* Shared a river meal              * Dislikes: unknown
Schedule hint: workshop on clear mornings
Language together: 森 · 木 · 道                  [Open]
```

### Profession page

```text
Fishing & Cooking · Lv 14 · 320/480 XP
Next: Cedar-Smoked River Fish at Lv 15
+----------------------------+-------------------------------+
| Useful now                 | Milestones                    |
| Fish the Woods cove        | First catch               [x] |
| Cook 3 river dishes        | Ten recipes               [x] |
| Try a rain-quality catch   | Five master dishes        [ ] |
+----------------------------+-------------------------------+
Known fish 8/20 · Recipes 11/24 · Mastery 2/8
```

### Crafting

```text
Woods Workshop · Search · Craftable · Known · Favorites
+-------------------------+-----------------------------------+
| > Moonwood Rod          | Moonwood Rod · trail fishing     |
|   Cedar Travel Pack     | Moonwood 5/3 · Fiber 8/1         |
|   Silkwind Charm locked | Output x1 · +24 Crafting XP      |
|                         | Quantity [-] 1 [+]               |
+-------------------------+-----------------------------------+
  Craft · Track materials · Compare · Back
```

### Shop

```text
Bramble's Trail Counter · Buy Sell Buyback · Search    1,240c
+-------------------------+-----------------------------------+
| River Remedy       35c  | River Remedy · clears Soaked     |
| Cedar Bait         12c  | Owned 4 · cooldown: Remedy       |
| Trail Meal         50c  | Japanese name/reading [audio]    |
|                         | Quantity [-] 1 [+] = 35c         |
+-------------------------+-----------------------------------+
  Buy · Favorite · Compare · Back
```

### Calendar

```text
Spring · Year 1                                      [<] [>]
 Mon Tue Wed Thu Fri Sat Sun
  1   2   3   4   5   6   7
  8*  9  10  11  12! 13  14
 15  16  17  18B 19  20  21
Today: rain · Bramble at the workshop
Upcoming: River Day 12 · Kaji birthday 18
Filters: Events · Birthdays · Crops · Tracked goals
```

### Return-to-game summary

```text
Welcome back · Last played 8 days ago
Previously
* Opened the Mountain Pass route
* Learned six travel words
* Bramble requested cedar fibers

Useful next choices
[Resume tracked goal] [Five-card refresher] [Check farm]
Recent unlocks: Woods Workshop · Region Map
                          Continue · Open Journal
```

## 18. Technical implementation plan

### Scene and input architecture

```text
World scenes -> semantic UI events
Persistent UIScene
|-- HUD and context prompt
|-- queued feedback
|-- root modal coordinator
|-- focus/input router
`-- touch controls
CombatScene -> owns combat presentation; world HUD hidden
Mapshot capture harness -> development-only offscreen/chunk rendering
```

Preserve the current `UIScene` and typed event bus. Add an input-context enum (`world`, `dialogue`,
`menu`, `map`, `combat`, `textEntry`, `touch`) and one `FocusManager` that owns D-pad neighbors, scroll-
into-view, device glyphs, disabled controls, focus restoration, and Back behavior. One root modal may
own input; one child tooltip/context menu may sit above it. An opening input cannot also activate the
first control.

Implementation checkpoint (2026-07-14): `UIScene` now enforces one tokenized root claim across
Dialogue, Learn, Notebook, Menu, Shop, Craft, Exchange, Storage, and Reading. Same-tick root handoffs
share one physical lock; invalid/empty opens roll back; Back targets the sole active root and Dialogue
cancels without invoking completion; combat permits Learn only and preserves modal HUD hiding on exit.
Valley, House, and Woods now also count the lock events each scene observes, disabling on the first
producer and enabling only after the final release; a real CropPicker + Menu overlap is covered. Counts
are scene-local and do not transfer a lease across replacement of a world scene.

Layout checkpoint (2026-07-14): `Layout.ts` now derives `regular`, `compact-portrait`, and
`compact-landscape` from Phaser's real parent/display size while retaining 800x600 logical coordinates.
`GameMenu` consumes the shared panel, rail, and content geometry. Toast text wraps to bounded
regular/compact widths, stacks by measured height, and uses an upward modal lane that stays inside the
logical canvas for the covered long and two-toast cases. Browser gates cover desktop, portrait,
rotation, invalid fallback, menu geometry, and normal/modal toast containment. Burst aggregation remains
UI-B work.

Focus checkpoint (2026-07-14): the canvas is a labeled programmatic focus fallback outside normal Tab
order. `UIScene` captures one valid DOM origin per continuous root lease, focuses the game surface while
the root owns input, preserves the origin across same-tick handoffs/rollback, restores it after the final
release, and falls back when it is missing or no longer usable. The real portrait guidance also returns
focus to the canvas when dismissed. This is browser DOM focus restoration only; selected Phaser controls,
visible focus rings, modal-internal Tab order/trapping, controller actions/neighbors/glyphs, device-inset
ingestion, per-panel responsive reflow, and complete per-surface input-copy adoption remain later slices.

Listener lifecycle checkpoint (2026-07-14): Reading and Grand Exchange now track/cancel delayed input
binds, exact-unbind only their own stable handlers, and expose callback-free disposal for UI shutdown.
`UIScene` disposes both panels and removes its global Tab capture only when it introduced that capture;
a pre-existing host/scene capture is preserved. Browser coverage proves repeated and same-tick reopen,
unrelated listener survival, pending-bind shutdown, single-callback input, and repeated UI restarts.

Input-device checkpoint (2026-07-14): `InputDevice.ts` owns one app-level
`keyboardMouse`/`touch` signal. Capability selects the initial fallback; only deliberate keydown or
mouse/touch/pen pointerdown changes it. World scenes emit semantic prompt text, while
`InteractionPrompt` owns and live-swaps one `E`/`USE` keycap. Title, dialogue, HUD guidance, and
virtual-control visibility follow the same signal. Subscriptions and world bus listeners release on
both scene shutdown and destruction, and a full game destroy does not send unlock events into already
destroyed worlds. Focused hybrid-browser coverage proves first-touch action ordering, exact interaction
counts, UI/world restart ownership, open-modal game destroy/recreate, live copy changes, and clean
console health. No controller behavior or glyph is claimed.

### Responsive and pixel rules

- Keep 800x600 as the world logical baseline. Wide screens center it; narrow menus reflow to full-page
  layouts and bottom sheets rather than shrinking two columns.
- Respect safe-area insets and 44 CSS-pixel minimum touch targets.
- World art and UI icons use nearest filtering/integer scale; panels align to integer coordinates;
  text renders at readable target resolution.
- Use a complete Japanese font fallback. A reusable `JapaneseText` component owns mixed script,
  furigana/reading lines, wrapping, audio, and assistance modes.

### Data and save ownership

- LDtk: terrain, path, water, collision, spawns, exits, landmarks, floors, and permanent placement.
- JSON/TS data: items, abilities, professions, tasks, NPC records, dialogue, recipes, language content,
  Raid and Expedition definitions.
- TypeScript: behavior, state transitions, validation, view-model composition, and UI orchestration.
- UI receives view models; it does not query arbitrary scene coordinates or duplicate economy values.

Add versioned optional save fields only through a migration: harmless `uiPrefs`, compressed discovery/
fog and markers, task tracking/checkpoints, return-summary history, and language encounter sources.
Never resume an open modal after reload. Supabase account/cloud persistence is an optional current
capability: unconfigured builds retain the local-first path, while configured builds establish the
account and character before Phaser starts. Cloud writes are debounced and revision-checked; a stale
document produces an explicit conflict instead of an automatic inventory/economy merge.

### Content identity and naming contract

Names must communicate actual role, mechanic, material, region, and visual identity.

- Player-facing NPCs use a proper name plus a separate duty/title (`Bramble` / `Trail Crafter`), never
  `Old Woman`, `NPC`, `Vendor`, or an internal sprite name.
- Abilities name their behavior/style (`Cedar Hook`, `Riposte Step`, `Ember Line`), not `Power Strike II`.
- Consumables name ingredient/form/purpose (`River-Mint Remedy`, `Cedar-Smoked Fish`), not `Potion 3`.
- Buildings/services name the place and function; enemies name silhouette/biome/behavior; resource
  nodes name the harvestable thing and formation.
- Runtime asset keys follow `{domain}_{subject}_{variant}_{state}` such as
  `npc_bramble_trail_crafter_walk`, `prop_cedar_dock_boat`, or `ui_item_river_mint_remedy`.
- Asset metadata records source pack, license, source path, intended use, visual description, native
  size, frame/cut, scale, anchor, solid footprint, and animation states.
- Stable save/LDtk IDs may remain behind clear display names. An internal rename requires an alias map,
  migration, generated-map update, reference search, and tests; never break saves for cosmetic tidiness.
- Texture keys and entity IDs never appear in player UI or fallback dialogue.

Rename order: safe display labels -> duties/descriptions -> misleading asset aliases -> stable internal
IDs only when the migration is justified. Tests should reject generic player-facing fallbacks and verify
that each visible model/icon matches its declared purpose.

### Reusable components and validation

Target primitives: `Panel`, `Tabs`, `CategoryRail`, `List`, `Grid`, `ItemSlot`, `StatRow`,
`ProgressBar`, `Tooltip`, `Modal`, `ConfirmDialog`, `ToastQueue`, `ContextPrompt`, `FocusRing`,
`MapLegend`, `JapaneseText`, `EmptyState`, and `ScrollPane`. Build them only as an active panel needs
them; do not create a speculative UI framework.

Automated gates cover modal/input ownership, keyboard/controller/pointer/touch paths, safe bounds at
desktop and phone sizes, visible focus/back, missing assets, map/LDtk parity, save migration, menu state,
learning/task persistence, mapshot dimensions, and console errors.

## 19. MVP version

This is an integration MVP over working systems, not a greenfield UI rebuild.

1. **UI-A - Foundation truth:** inventory current surfaces/tokens, unify safe areas, modal ownership,
   Back, focus, device glyphs, and responsive rules.
2. **UI-B - Core play shell:** split/dim the HUD, aggregate feedback, improve combat intent/item choice,
   and add the returning-player summary.
3. **UI-C - Core information loop:** grouped Pause Hub, Bag/equipment comparison, ability identity tags,
   profession milestones, and typed Journal records.
4. **UI-D - LDtk-derived navigation:** local/region/world views, discovery, filters, learned labels, and
   a developer mapshot command.
5. **UI-E - Learning/social depth:** encountered/mastered language records, unified Learning Journal,
   relationship memories, calendar/community surfaces only when backed by real state.

Continue `UI-A` with one bounded per-surface input-copy adoption slice: migrate static close, scroll,
pickup, fishing, and combat-continuation hints only where equivalent keyboard/mouse and pointer/touch
actions already work. Do not add controls merely to support matching copy. Controller input, Phaser
focus, device insets, and panel reflow remain separate slices; then ship one complete `UI-C`
Bag/Character slice. Combat ability/consumable rebalancing remains a separate data/system slice with
save-compatible IDs, followed by UI presentation. Each slice gets the relevant current input checks and
its own commit.

## 20. Later-phase improvements

- relationship stories, richer schedules, family/social graph, mail, festivals, and community history;
- advanced profession specialization, saved loadouts, and reversible respec;
- advanced listening/production/typing/speaking and richer sentence breakdown;
- player-facing mapshot/showcase export, floor/elevation tools, and deeper map annotations;
- cross-device webapp/game merge, additional save slots, import/export;
- companions/party management only after real companions exist;
- handcrafted-room Expedition assembly only after several authored routes prove the grammar;
- a distinctly named Deck Trial only if the legacy deckbuilder earns a rebuild;
- multiplayer only after the complete single-player loop is polished.

## 21. Major risks and anti-patterns

| Risk / anti-pattern | Decision |
|---|---|
| Treating this guide as one implementation epic | Execute UI-A through UI-E as separate vertical slices |
| Ten tabs becoming twenty | Six durable domains and direct shortcuts |
| Journal/Learning nesting | One secondary tab row, search, cross-links, no tertiary trees |
| Learning interruption | Contextual discovery and player-invoked review |
| Wrong Japanese blocks progress | Assist, retry, alternate task, or optional bonus only |
| Higher-level ability replaces an old one | Sidegrades with distinct geometry/timing/resource/style |
| Food/potions differ only by number | Distinct use windows, cooldown families, preparation/counterplay |
| Generic/misleading names or models | Identity contract, display-name audit, aliases for stable IDs |
| LDtk and TypeScript duplicate map truth | LDtk owns spatial fields; behavior data owns rules |
| Controller/touch added after desktop | Validate every active surface on every supported input |
| Tiny pixel fonts harm Japanese | Complete font fallback, scalable text, pixel font only for headings |
| Notification/checklist clutter | Aggregate feedback; one tracked main plus two optional goals |
| Save schema churn | Additive versioned fields and migration tests |
| Mapshot exceeds GPU limits | Deterministic chunk render and stitch |
| Reference collage becomes imitation | Borrow a purpose-specific pattern, never layouts/art/characters |
| Multiplayer/party placeholders | Hide absent systems; single-player first |

## 22. Final recommended reference stack

**Foundation:** CrossCode for information architecture/controller maps; Fields of Mistria for cozy
readability; RuneScape for meaningful long-term skills; TUNIC for comprehension as progression; Sea of
Stars for landmark/world presentation.

**System specialists:** Chained Echoes for equipment/abilities; Moonlighter for item/shop decisions;
Pokemon Legends: Arceus for encountered/mastered records; Hades for relationship memory; Dragon Quest
XI for returning-player clarity; Core Keeper for fog/markers; Into the Breach for concise consequence.

**World composition:** Eastward for atmospheric districts; Songs of Conquest for terrain/landmark
hierarchy; Animal Well and Blasphemous 2 for secrets, shortcuts, and vertical connection; Stardew Valley
and Fantasy Life i for fast everyday activity language.

The final blend is **CrossCode clarity + Fields of Mistria warmth + RuneScape progression + TUNIC
language discovery + Sea of Stars landmarks**, expressed through Sushi Valley's own LDtk-authored
world, named content, and shared Japanese-learning profile.
