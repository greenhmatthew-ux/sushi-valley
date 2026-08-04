class_name QuestJournal
extends RefCounted
## What the player has taken on, finished, and not yet met.
##
## Node-free so it stays headless-testable, matching the other files in
## src/systems/. The quest-giver entity already resolves the *current* quest's
## dialogue stage; this answers the different question of what the whole run
## looks like, which nothing could previously see.
##
## Quest progress is persisted as two profile flags per quest —
## `quest_<id>_started` and `quest_<id>_done` — written by the giver. Reading
## them back is what lets a finished quest still exist somewhere, instead of
## disappearing the moment its giver stops offering it.

enum Stage { UNMET, ACTIVE, READY, DONE }

## Order the journal reads in: what to do now, then what is waiting, then a
## record of what was finished. An unmet quest is deliberately last — it is the
## least actionable, and listing it first would read as a demand.
const STAGE_ORDER := [Stage.READY, Stage.ACTIVE, Stage.DONE, Stage.UNMET]


static func started_flag(quest_id: String) -> String:
	return "quest_%s_started" % quest_id


static func done_flag(quest_id: String) -> String:
	return "quest_%s_done" % quest_id


## Normalize both quest shapes into one checklist. Existing authored quests keep
## their single `goal` block; new quests can opt into an `objectives` array. This
## first objective-list slice deliberately supports held items only, which is the
## behavior the live quest giver can prove atomically today. `consume: false`
## lets a commission inspect permanent gear/tools without taking them away.
static func objectives(quest: Dictionary, content, inventory) -> Array:
	var authored: Array = []
	var raw_objectives: Variant = quest.get("objectives", [])
	if raw_objectives is Array:
		authored.assign(raw_objectives)
	if authored.is_empty():
		var legacy_goal: Variant = quest.get("goal", {})
		if legacy_goal is Dictionary and not (legacy_goal as Dictionary).is_empty():
			var legacy: Dictionary = (legacy_goal as Dictionary).duplicate(true)
			legacy["consume"] = bool(quest.get("consumeGoal", true))
			authored.append(legacy)

	var rows: Array = []
	for raw in authored:
		if not (raw is Dictionary):
			continue
		var objective: Dictionary = raw
		var item_id := String(objective.get("item", ""))
		var target := maxi(1, int(objective.get("qty", 1)))
		if item_id.is_empty():
			continue
		var carried := 0
		if inventory != null:
			carried = int(inventory.count(item_id))
		var item_name := item_id
		if content != null:
			item_name = String(content.item(item_id).get("name", item_id))
		rows.append({
			"item": item_id,
			"label": String(objective.get("label", item_name)),
			"goal": target,
			"progress": mini(carried, target),
			"complete": carried >= target,
			"consume": bool(objective.get("consume", true)),
		})
	return rows


static func objectives_met(rows: Array) -> bool:
	if rows.is_empty():
		return false
	for row in rows:
		if not bool((row as Dictionary).get("complete", false)):
			return false
	return true


## The HUD remains one clear next action even when the Journal owns a checklist.
## Once every row is complete, retain the final row for stable ready-state copy.
static func next_objective(rows: Array) -> Dictionary:
	for row in rows:
		if not bool((row as Dictionary).get("complete", false)):
			return row
	return rows[-1] if not rows.is_empty() else {}


## One quest's state. The top-level item/progress fields always describe the next
## unfinished row for compact HUD compatibility; `objectives` retains the full
## checklist for the Journal.
static func entry(profile, content, inventory, quest_id: String) -> Dictionary:
	var quest: Dictionary = content.quest(quest_id)
	if quest.is_empty():
		return {}
	var started: bool = profile != null and profile.get_flag(started_flag(quest_id))
	var done: bool = profile != null and profile.get_flag(done_flag(quest_id))
	var objective_rows := objectives(quest, content, inventory)
	var current := next_objective(objective_rows)
	var item := String(current.get("item", ""))
	var target := int(current.get("goal", 0))
	var carried := int(current.get("progress", 0))

	var stage := Stage.UNMET
	if done:
		stage = Stage.DONE
	elif started:
		stage = Stage.READY if objectives_met(objective_rows) else Stage.ACTIVE

	return {
		"id": quest_id,
		"title": String(quest.get("title", quest_id)),
		"giver": String(quest.get("giver", "")),
		"desc": String(quest.get("desc", "")),
		"stage": stage,
		"item": item,
		"goal": target,
		"progress": carried if stage == Stage.ACTIVE or stage == Stage.READY else 0,
		"objectives": objective_rows,
		"reward": quest.get("reward", {}),
	}


## Every quest the player has touched, plus the ones they have not, in reading
## order. Unmet quests keep their titles hidden by the caller — see `is_spoiler`.
static func all_entries(profile, content, inventory) -> Array:
	var entries: Array = []
	for quest_id in content.quest_order:
		var e: Dictionary = entry(profile, content, inventory, String(quest_id))
		if not e.is_empty():
			entries.append(e)
	entries.sort_custom(func(a, b):
		var rank_a: int = STAGE_ORDER.find(a["stage"])
		var rank_b: int = STAGE_ORDER.find(b["stage"])
		if rank_a != rank_b:
			return rank_a < rank_b
		return String(a["title"]) < String(b["title"]))
	return entries


## An unmet quest must not be listed by name: the journal is a record of the
## player's own run, not a table of contents for content they have not found.
## Counting them is fine, and is what tells them there is more out there.
static func is_spoiler(entry_data: Dictionary) -> bool:
	return int(entry_data.get("stage", Stage.UNMET)) == Stage.UNMET


static func counts(entries: Array) -> Dictionary:
	var out := {"active": 0, "ready": 0, "done": 0, "unmet": 0}
	for e in entries:
		match int(e.get("stage", Stage.UNMET)):
			Stage.READY: out["ready"] += 1
			Stage.ACTIVE: out["active"] += 1
			Stage.DONE: out["done"] += 1
			_: out["unmet"] += 1
	return out


static func stage_label(stage: int) -> String:
	match stage:
		Stage.READY: return "Ready to turn in"
		Stage.ACTIVE: return "In progress"
		Stage.DONE: return "Completed"
		_: return "Not found yet"
