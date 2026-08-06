# Sushi Valley — Gameplay and Level Design Guide

This document defines how an LLM or developer should analyze, repair, redesign, implement, and validate gameplay spaces in Sushi Valley.

It is not a generic level-generation prompt.

Its purpose is to preserve Sushi Valley's identity as a Japanese-learning RPG while making every location readable, rewarding, memorable, and mechanically useful.

It replaces the Phaser/LDtk-era bible of the same name. The route grammar (§8.1), composition
rhythm and viewport test (§8.2), and water and fishing contract (§7.6) are carried forward from
that version with the LDtk authoring steps rewritten for `TileMapLayer`; its Whispering Woods
cove scores and per-slice TypeScript/LDtk acceptance gates were dropped as dead, along with the
audit documents they cited. Two rules survive from those gates and apply to any slice: **re-score
only what is visibly and mechanically implemented**, and **a human approves any new visual
baseline**.

---

## 1. Project Identity

Sushi Valley is a single-player Japanese-learning RPG built in Godot 4.7.

The core fantasy is:

> Live in and explore a Japanese-inspired world where gathering, crafting, farming, fishing, fighting, questing, and learning Japanese all support one another.

Primary inspirations include:

* RuneScape
* Stardew Valley
* Terraria

The educational system must remain part of the game loop rather than feeling like a separate quiz application.

Recall should affect meaningful progress, rewards, combat, access, or mastery.

---

## 2. Core Gameplay Loop

Every substantial area should support at least three parts of this loop:

1. Notice a goal, opportunity, mystery, or resource.
2. Travel through a readable space.
3. Gather, farm, fish, fight, craft, talk, study, or explore.
4. Make a meaningful gameplay decision.
5. Recall or apply Japanese knowledge when appropriate.
6. Receive progress, resources, information, access, or mastery.
7. Discover a reason to continue or return.

Do not create locations that only provide scenery.

Do not place activities merely because empty space exists.

Each activity must have a readable relationship to its environment.

Examples:

* Ore appears against cliffs, stone, caves, or exposed rock.
* Herbs appear in damp, shaded, wild, or cultivated areas.
* Bamboo appears in recognizable stands.
* Fishing spots appear where the shoreline and access point make sense.
* Farms connect visually and spatially to homes, storage, water, and paths.
* Enemies occupy believable habitats or guard meaningful routes.
* Lesson gates protect something the player understands and wants.

---

## 3. Design Pillars

### 3.1 Learning Through Play

Japanese recall must support gameplay rather than interrupt it without purpose.

A recall interaction should answer at least one question:

* What does success unlock?
* What gameplay advantage does mastery provide?
* Why does recall happen here?
* Why does the player care about answering now?
* How is failure handled without making the player want to avoid learning?

Good uses include:

* Maintaining a combat Flow streak.
* Unlocking a route or lesson gate.
* Improving gathering output.
* Identifying an object, enemy intent, recipe, or location.
* Strengthening a crafted item.
* Earning trust from an NPC.
* Revealing clues or secrets.
* Restoring energy or gaining a tactical advantage.

Avoid recall prompts that are detached from the current action.

---

### 3.2 Readable World Design

The player should usually understand:

* where they can walk;
* where they cannot walk;
* what can be interacted with;
* what an area is for;
* where major routes lead;
* what is dangerous;
* what is optional;
* what is likely to reward exploration.

Use paths, landmarks, terrain transitions, architecture, lighting, NPC placement, resource clusters, and sightlines to communicate this information.

Do not rely entirely on signs or UI markers to repair unclear geography.

---

### 3.3 Meaningful Density

Avoid both empty fields and cluttered activity parks.

Every location should have a deliberate rhythm:

* activity;
* transition;
* decision;
* reward;
* breathing room;
* discovery.

Breathing room may be quiet, but it must still contribute atmosphere, anticipation, orientation, or contrast.

---

### 3.4 Return Value

Sushi Valley is not a one-pass linear game.

Areas should support revisiting through some combination of:

* seasonal changes;
* weather;
* resource respawns;
* stronger enemies;
* new gathering tools;
* lesson mastery;
* quests;
* NPC schedules;
* farming;
* fishing variation;
* secrets;
* shortcuts;
* crafting requirements;
* raids or expeditions.

A return visit should not merely repeat the exact first visit.

---

### 3.5 Small Vertical Slices

Prefer small, playable improvements over broad speculative redesigns.

A level-design task should normally change one route, district, encounter cluster, activity loop, or interior at a time.

Do not rewrite unrelated systems while repairing a location.

---

### 3.6 Fun, Not Merely Correct

Most of this document lists ways an area can be wrong. An area can satisfy every rule here and still be boring. This pillar is the counterweight, and it outranks tidiness.

An area should produce at least one moment a player would describe to someone else.

Sources of that moment:

* **A reveal.** The route conceals something, then shows it — a treeline opening onto water, a stair that turns and drops the pass away below. Compose at least one deliberate sightline per area.
* **Treasure.** Not a reward *type* off the list in §7.5, but an actual find: something visible before it is reachable, something tucked behind a small terrain puzzle, a rare drop worth chasing. If every reward is handed over by an NPC or harvested from a node, the area contains no treasure.
* **A secret.** One thing per area that is off the critical path and unmarked by UI — a gap in a hedge, a cave mouth behind a fall, a chest that only reads as odd once noticed. Secrets must reward attention, never pixel-hunting.
* **A landmark with presence.** §3.2 treats landmarks as navigation aids. They are also how the player remembers the place. At least one should be oversized, strange, or story-bearing rather than merely tall enough to steer by.
* **A shortcut the player earns.** A gate that only opens from the far side, a rope dropped down a ledge, a repaired bridge. Opening it should visibly shorten a route the player has already walked and resented.
* **A character.** At least one NPC per populated area with a want, an opinion, or a running joke, rather than a service dispenser. Vendors and quest givers can carry this.

A primary route should reach its main destination in roughly **30–60 seconds** of walking. Longer than that with no beat in between is travel, not exploration.

Test: describe the finished area out loud. If it sounds like a list of features, it is not fun yet.

---

## 4. Sushi Valley Area Roles

Before analyzing a map, classify its primary role.

Possible roles include:

* Home or recovery hub
* Social hub
* Farming district
* Crafting district
* Resource-gathering region
* Fishing region
* Beginner combat area
* Dangerous combat region
* Lesson-gated route
* Quest destination
* Story location
* Raid preparation area
* Expedition staging area
* Dungeon
* Interior
* Transitional route
* Secret or optional area

A location may have secondary roles, but it must have one clear primary purpose.

The primary role should influence layout, activity density, navigation, risk, rewards, and visual identity.

---

## 5. Required Analysis Workflow

Never begin by proposing a replacement map.

Follow this order.

### Step 1 — Establish Evidence

Inspect the relevant:

* `.tscn` scene;
* attached GDScript;
* reusable entity scenes;
* content JSON;
* quest data;
* lesson or recall data;
* screenshots;
* collision;
* spawn points;
* entrances and exits;
* current tests;
* relevant design documentation.

Clearly separate:

* observed facts;
* likely interpretations;
* assumptions;
* missing evidence.

Never invent current behavior.

---

### Step 2 — State the Intended Experience

Describe:

* the area's primary role;
* the intended player emotion;
* the player's immediate objective;
* the likely first-visit route;
* the reasons to explore;
* the reasons to return;
* the Japanese-learning purpose;
* the expected danger level.

---

### Step 3 — Map the Player Journey

Describe the experience in sequence:

1. Entry
2. Initial orientation
3. First visible goal
4. First interaction
5. First decision
6. First challenge
7. First reward
8. Mid-area escalation
9. Optional branch
10. Main payoff
11. Exit, shortcut, or return hook

Identify where this sequence is absent or weak.

---

### Step 4 — Diagnose Problems

For every problem, provide:

* evidence;
* player-visible symptom;
* likely root cause;
* severity;
* design principle affected;
* smallest viable repair;
* more ambitious alternative;
* risks and tradeoffs.

Use these severity levels:

* **Blocker:** broken progression, softlock, invalid collision, unreachable objective, save corruption risk.
* **Major:** persistent confusion, unfair difficulty, unusable route, broken learning loop, severe pacing failure.
* **Moderate:** repetitive encounter, weak reward, excessive travel, poor signposting, bland identity.
* **Minor:** polish, spacing, visual variety, small convenience issue.

Do not label subjective preferences as blockers.

---

### Step 5 — Generate Repair Options

Provide three levels of intervention:

#### Option A — Surgical Repair

The smallest change that fixes the root problem.

Examples:

* move a prop;
* clear a doorway;
* adjust collision;
* add a visible landmark;
* reposition an NPC;
* improve a path edge;
* move a reward;
* reduce one encounter;
* add one return shortcut.

#### Option B — Focused Redesign

Rework one route, encounter cluster, activity loop, or sub-area while preserving the scene.

#### Option C — Structural Redesign

Change the area's topology or purpose only when smaller repairs cannot solve the root issue.

Compare cost, risk, player benefit, and implementation complexity.

Recommend one option explicitly.

---

### Step 6 — Validate Against Project Rules

Confirm that the proposal:

* preserves existing functionality;
* uses Godot-native scenes and `TileMapLayer`;
* does not reintroduce LDtk or an external world builder;
* keeps pure logic out of scene scripts;
* communicates through existing systems and signals where appropriate;
* avoids save-schema changes unless migration is planned;
* supports keyboard and controller;
* remains web-export compatible;
* can be implemented as a small playable slice.

---

## 6. Map Construction Rules

### 6.1 Grid and Placement

Native tile size is 16 pixels.

Props draw from their bottom center.

Prop feet must land on a tile line:

```text
y % 16 == 0
```

For horizontal placement, the sprite edge must align to the grid:

```text
(x - texture_width / 2) % 16 == 0
```

This means:

* a 16-pixel-wide prop normally has `x % 16 == 8`;
* a 32-pixel-wide prop normally has `x % 16 == 0`;
* a 64-pixel-wide building normally has `x % 16 == 0`.

Do not blindly place every prop on a tile center.

---

### 6.2 Collision

Collision must match the solid visual footprint expected by the player.

Do not use the complete transparent image bounds.

For trees, collide with the trunk or grounded base rather than the canopy.

For buildings, collide with grounded walls and solid mass while preserving readable doorway access.

For rocks and props, block the visible grounded footprint.

The collision should never imply that open grass is solid or that a player can walk through visible structure.

---

### 6.3 Entrances

Keep doorway columns and immediate arrival tiles clear.

A player entering an interior or area should not:

* collide immediately;
* spawn behind decoration;
* enter inside an NPC;
* be forced around an unclear obstacle;
* face an interaction prompt before gaining control;
* lose sight of the return exit.

---

### 6.4 Paths

Do not create paths as large rectangles of one center tile.

Use:

* edges;
* corners;
* transitions;
* alternate centers;
* occasional widening;
* narrowing;
* branches;
* worn patches;
* environmental interruptions.

Paths must guide, not imprison.

Main routes should read clearly without removing optional exploration.

---

### 6.5 Spacing

Avoid visual tangents.

An object that almost touches a wall, pond, path, building, or another prop often appears accidental.

Provide roughly one tile of breathing room unless intentional contact is visually and mechanically justified.

Do not squeeze a building exactly between unrelated boundaries.

---

### 6.6 Y-Sorting

Use Y-sort for entities and props the player can walk behind.

Verify ordering at:

* the top edge;
* the bottom edge;
* the sides;
* nearby elevation or terrain changes.

---

### 6.7 Interiors

No two interiors may use the same layout with only superficial asset swaps.

Every interior must express its function.

A forge should communicate:

* production;
* heat;
* tools;
* material storage;
* safe movement around equipment.

A home should communicate:

* identity;
* routine;
* ownership;
* comfort;
* private versus public space.

A shop should communicate:

* service counter;
* merchandise;
* customer route;
* storage;
* proprietor position.

A classroom or study area should communicate:

* attention direction;
* learning materials;
* practice;
* progression.

Every interior should include:

* a clear entry;
* a readable focal point;
* a main interaction;
* one or more identity details;
* intentional circulation;
* no blocked exit.

---

## 7. Gameplay Placement Rules

### 7.1 Resources

A resource node must have:

* an environmental reason;
* a gameplay reason;
* enough visual distinction to be noticed;
* a route cost;
* a reward appropriate to that cost.

Do not evenly scatter resources.

Prefer readable clusters and gradients.

Example:

* common herbs beside the main route;
* better herbs in a shaded side branch;
* rare herbs beyond danger, a tool requirement, weather condition, or learned ability.

---

### 7.2 Enemies

Enemy placement should create decisions, not random friction.

For each encounter, define:

* what the enemy protects or interrupts;
* how early the player can see it;
* whether avoidance is possible;
* whether terrain changes the fight;
* whether the group composition is intentional;
* what Japanese recall contributes;
* what reward justifies the danger;
* how repeated traversal remains tolerable.

Avoid enemies directly on:

* spawn positions;
* door exits;
* narrow unavoidable transitions;
* interaction prompts;
* important dialogue;
* fishing or farming animations.

Beginner areas should introduce one demand at a time.

Later areas may combine known demands.

---

### 7.3 Lesson Gates

A lesson gate must visibly protect something meaningful.

Before reaching it, the player should understand:

* what is blocked;
* why it matters;
* what lesson or mastery is required;
* how to improve;
* whether partial progress is retained.

Do not hide an essential early-game service behind an unexplained gate.

A gate should feel like earned progression rather than arbitrary denial.

---

### 7.4 Recall During Combat

Sushi Valley's combat distinguishes Energy from Speed.

Flow rewards consecutive correct recall and may grant increasing attack power.

Combat spaces should support the mental load created by recall.

Avoid combining all of the following during the same beginner encounter:

* unfamiliar enemy behavior;
* environmental hazards;
* time pressure;
* new controls;
* multiple new Japanese concepts;
* severe resource loss.

Teach each layer before combining it.

---

### 7.5 Rewards

Use several reward types:

* useful item;
* crafting material;
* recipe;
* lesson access;
* shortcut;
* lore;
* NPC relationship;
* rare gathering node;
* safe rest point;
* visual reveal;
* combat advantage;
* new service;
* map knowledge.

Dead ends must usually contain a payoff.

A scenic view may count as a payoff only when it is genuinely composed and memorable.

---

### 7.6 Water and Fishing

Water is authored terrain, not a runtime effect.

* Author the water body and shoreline in the Godot editor with `TileMapLayer` terrain sets, from inspected edge, corner, center, and transition tiles. Never generate a rectangular field of animated water sprites at runtime.
* Keep shoreline silhouettes static. Ripples, fish movement, foam, weather, and reflections are sparse ambience layered on top; they never define the shape.
* Water is solid at the visible wet band. Use partial collision on shoreline cells and full collision on interior cells, and exclude any authored dock, bridge, ford, or stepping-stone route so it stays walkable.
* Boats and tall waterfront props render at their full visual bounds while collision comes from the water or the visible hull and ground-contact band — not the transparent image rectangle.

A fishing site is a destination, not a row of duplicated resource icons.

Give it:

* a readable approach;
* negative space at the water's edge;
* one primary casting point that reads as *the* spot;
* at most a few deliberately separated alternatives, each with its own reason to be used.

Fishing follows a complete loop:

```text
approach → cast feedback → bite / control challenge → catch quality
        → item and XP → saved cooldown → reason to return
```

Skipping a step reduces the site to a click target.

---

## 8. Pacing Model

Use this pattern as a starting point, not a rigid formula:

1. Orientation
2. Low-pressure interaction
3. Small reward
4. First challenge
5. Breathing room
6. Choice or branch
7. Increased challenge
8. Meaningful payoff
9. Shortcut, revelation, or return hook

Avoid long sequences consisting only of:

* walking;
* repeated gathering;
* identical fights;
* dialogue;
* recall prompts;
* menus.

Alternate cognitive demands.

After a difficult recall or combat sequence, provide space to orient and enjoy the reward.

---

### 8.1 Route Grammar

Every production outdoor route needs six readable beats:

1. **Arrival read** — the spawn faces a landmark and the safe route.
2. **Primary path** — a clear 30–60 second route reaches the main destination.
3. **Optional loop** — a useful branch rejoins the route instead of ending in empty space.
4. **Risk pocket** — danger visibly protects a reward, resource, or shortcut.
5. **Shortcut** — progress makes repeat travel faster or safer where appropriate.
6. **Exit preview** — the next destination is foreshadowed before the transition.

A dead-end branch is not automatically wrong, but it must pay off (§7.5). A branch that neither rejoins nor rewards is filler.

---

### 8.2 Composition Rhythm and the Viewport Test

Compose space in this rhythm:

```text
open → narrow → reveal → pocket → landmark → return
```

Then apply the viewport test:

> Any viewport the player can stand in should contain a destination cue, a meaningful interaction, a composition change, or a landmark.

It must not contain uniform field fill or decorative confetti.

This is the fastest check for a flat area and it is checkable from a screenshot. Scrub the whole map, not only the primary route.

---

## 9. Learning Design Rules

For every learning interaction, answer:

1. What Japanese material is being practiced?
2. Has it already been introduced?
3. Is the interaction recognition, recall, production, or application?
4. Why does it occur at this location?
5. What does success change?
6. What does failure change?
7. Can the player retry?
8. Does failure teach anything?
9. Does the interaction preserve game flow?
10. Will repeating it remain tolerable?

The SRS system intentionally uses short early intervals so cards can recur within a single play session.

Do not "fix" this by pushing all early reviews to later real-world days.

Lesson gates may run recall batches repeatedly until their mastery threshold is met.

Do not replace this with a single fixed batch unless the progression design is intentionally changed and tested.

---

## 10. Evaluation Rubric

Score each category from 1 to 5.

Explain every score with evidence.

### Navigation

* 1: frequent disorientation or unclear routes
* 3: understandable but weak or overly dependent on markers
* 5: naturally readable with strong landmarks and route hierarchy

### Spatial Composition

* 1: accidental, cramped, empty, or grid-stamped
* 3: functional but generic
* 5: intentional, balanced, distinctive, and readable

### Activity Placement

* 1: arbitrary placement
* 3: mostly sensible with weak clusters
* 5: every activity reinforces environment and player goals

### Gameplay Variety

* 1: one repeated action
* 3: several actions with weak relationships
* 5: complementary actions create meaningful rhythm

### Learning Integration

* 1: detached quiz interruption
* 3: mechanically connected but repetitive
* 5: recall has clear contextual and strategic meaning

### Combat Design

* 1: unfair, random, or tedious
* 3: functional but predictable
* 5: readable, varied, tactical, and appropriately rewarded

### Exploration

* 1: no reason to leave the main route
* 3: optional branches with inconsistent payoff
* 5: curiosity is consistently rewarded without obscuring navigation

### Pacing

* 1: exhausting, empty, or monotonous
* 3: generally functional with noticeable dead zones
* 5: strong alternation of action, decision, reward, and rest

### Return Value

* 1: no reason to revisit
* 3: resources or quests provide limited return
* 5: multiple systems create evolving revisits

### Visual Identity

* 1: placeholder or interchangeable
* 3: coherent but generic
* 5: memorable and specific to its function and region

### Memorability

* 1: nothing here would be described to another player
* 3: one competent reveal, secret, set piece, or character
* 5: several earned moments — a reveal, a find, a shortcut, and someone worth quoting

### Technical Reliability

* 1: broken collisions, routes, or progression
* 3: functional with edge cases
* 5: stable, tested, accessible, and safe for saves

---

## 11. Required Output Format for LLM Reviews

Every review must use this structure.

### A. Current Area Summary

* Area:
* Scene:
* Primary role:
* Secondary roles:
* Intended emotion:
* Main activities:
* Learning function:
* First-visit objective:
* Return hooks:

### B. Evidence Inspected

List the files, scene nodes, data, screenshots, and tests inspected.

### C. Player Journey

Describe the likely first-time journey from entry to exit.

### D. What Already Works

Do not redesign working features without reason.

### E. Problems

Use a table:

| Severity | Location | Evidence | Player symptom | Root cause |
| -------- | -------- | -------- | -------------- | ---------- |

### F. Repair Options

For each major issue:

* Surgical repair
* Focused redesign
* Structural redesign
* Recommendation
* Tradeoffs

### G. Proposed Revised Flow

Describe the new player experience step by step.

### H. Godot Implementation Plan

List:

* scenes to edit;
* scripts to edit;
* data to edit;
* new reusable scenes;
* collision changes;
* signal changes;
* tests;
* manual validation.

### I. Validation

Confirm:

* no blocked entrances;
* no unreachable content;
* no softlocks;
* no unclear collision;
* grid rules respected;
* controller and keyboard supported;
* Japanese learning remains integrated;
* existing saves remain safe;
* web export remains viable.

### J. Risks and Open Questions

Only include questions that cannot be answered from repository evidence.

---

## 12. Master Prompt

Use the following prompt when reviewing a Sushi Valley area.

```text
You are the principal gameplay, level, and learning-experience designer for Sushi Valley, a Godot 4.7 Japanese-learning RPG.

Do not give generic level-design advice.

Base every conclusion on the project files, scene structure, content data, screenshots, tests, and established Sushi Valley rules.

The game loop is:

explore → gather/farm/fish/fight → recall or apply Japanese → gain resources, access, mastery, or progression → return stronger

Follow this workflow exactly:

1. Inspect the relevant .tscn scene, attached scripts, reusable entities, content JSON, quest data, learning data, tests, and screenshots.
2. Separate observed facts from assumptions.
3. State the area's primary role, intended emotion, first-visit objective, learning function, and return value.
4. Describe the likely first-time player journey.
5. Identify what already works and must be preserved.
6. Diagnose navigation, collision, pacing, activity placement, combat, exploration, rewards, learning integration, visual identity, and technical risks.
7. Rank problems as Blocker, Major, Moderate, or Minor.
8. For each significant problem, explain:
   - evidence;
   - player-visible symptom;
   - root cause;
   - violated design principle;
   - smallest viable fix;
   - focused redesign;
   - structural alternative;
   - tradeoffs.
9. Recommend the smallest option that solves the root problem.
10. Produce a Godot-specific implementation plan naming exact scenes, scripts, data files, nodes, signals, and tests.
11. Validate the proposal against Sushi Valley's project and map rules.
12. Describe how to test the result manually in the full scene.

Mandatory constraints:

- Preserve existing functionality.
- Prefer small playable vertical slices.
- Use GDScript only.
- Use TileMapLayer rather than deprecated TileMap.
- Do not reintroduce LDtk, the old world builder, or an in-game creator.
- Keep pure gameplay logic out of scene-tree-dependent scripts.
- Respect 16-pixel placement rules.
- Match collision to grounded visual footprints.
- Keep entrances and doorway columns clear.
- Use Y-sort where the player can walk behind an object.
- Avoid flat filler, repeated interiors, rectangular stamped paths, random resource placement, and arbitrary enemy placement.
- Preserve the distinction between Energy, Speed, and Flow.
- Preserve deliberate short early SRS intervals unless explicitly redesigning and testing them.
- Make Japanese recall contextually meaningful.
- Do not invent files, nodes, data, or current behavior.
- Mark uncertainty plainly.
```

---

## 13. Repair Prompt for an Existing Scene

```text
Audit and repair this existing Sushi Valley scene:

SCENE:
[scene path]

PLAYER COMPLAINT OR GOAL:
[describe the problem]

Do not replace the scene immediately.

First inspect its scene hierarchy, scripts, exits, spawn points, collisions, props, activities, NPCs, enemies, lesson gates, rewards, and relevant content data.

Then:

1. Reconstruct the intended player flow.
2. Identify what currently works.
3. Find the exact points where navigation, pacing, collision, learning, combat, or rewards fail.
4. Rank issues by severity.
5. Propose the smallest safe repair.
6. Explain which existing nodes should move, change, or remain untouched.
7. Give exact implementation steps.
8. Define one headless or structural test where practical.
9. Define a manual full-scene screenshot and playtest checklist.
10. State remaining risks.
```

---

## 14. New Area Prompt

```text
Design a new Sushi Valley area from this brief:

AREA NAME:
[name]

PRIMARY ROLE:
[role]

PLAYER PROGRESSION:
[current lessons, equipment, systems, and expected power]

CORE ACTIVITIES:
[activities]

JAPANESE LEARNING PURPOSE:
[material and recall/application type]

CONNECTIONS:
[entrances, exits, neighboring areas]

REQUIRED CONTENT:
[NPCs, quests, enemies, resources, services, gates, landmarks]

Start with a text topology, not decorative detail.

Define:

1. Primary route
2. Optional branches
3. Landmarks
4. Entry and orientation
5. First low-pressure interaction
6. Main activity loop
7. Learning integration
8. Encounter escalation
9. Rewards
10. Return hooks
11. Shortcuts
12. Safe spaces
13. Resource ecology
14. Enemy ecology
15. Interior requirements
16. Scene and reusable-node plan
17. Tests and manual validation

Then challenge the design:

- Is any branch unrewarded?
- Is any area present only as filler?
- Is Japanese recall detached from the action?
- Is the player forced through repetitive combat?
- Does every gate visibly protect something desirable?
- Can the area be built as a small playable vertical slice?
```

---

## 15. Screenshot Review Prompt

```text
Review this complete Sushi Valley scene screenshot together with its .tscn file.

Inspect the whole composition rather than isolated details.

Check:

- entrance clarity;
- route hierarchy;
- building spacing;
- prop grid alignment;
- visible collision expectations;
- visual tangents;
- doorway clearance;
- path variation;
- landmark strength;
- resource ecology;
- encounter readability;
- dead space;
- clutter;
- repeated patterns;
- flat filler;
- visual identity;
- likely Y-sort failures.

For every issue, point to a concrete region or node.

Do not claim collision is correct from the screenshot alone. Verify it from the scene.
```

---

## 16. Definition of Done

A gameplay-area task is complete only when:

* the intended area role is clear;
* the player can enter, orient, act, and leave;
* main routes and optional routes are readable;
* collision matches visual expectations;
* doors and spawn points remain clear;
* activities are environmentally justified;
* rewards match route cost and danger;
* recall has a contextual gameplay purpose;
* pacing includes activity and breathing room;
* the area has at least one memorable identity feature;
* revisiting has a purpose when appropriate;
* affected tests pass;
* the whole scene has been inspected in a screenshot;
* the full loop has been played manually;
* risks and follow-up work are documented.
