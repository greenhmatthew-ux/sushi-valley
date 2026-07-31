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


## One quest's state. `progress` is how many of the goal item are carried right
## now, which is only meaningful while the quest is active.
static func entry(profile, content, inventory, quest_id: String) -> Dictionary:
	var quest: Dictionary = content.quest(quest_id)
	if quest.is_empty():
		return {}
	var started: bool = profile != null and profile.get_flag(started_flag(quest_id))
	var done: bool = profile != null and profile.get_flag(done_flag(quest_id))
	var goal: Dictionary = quest.get("goal", {})
	var item := String(goal.get("item", ""))
	var target := int(goal.get("qty", 0))
	var carried := 0
	if inventory != null and not item.is_empty():
		carried = int(inventory.count(item))

	var stage := Stage.UNMET
	if done:
		stage = Stage.DONE
	elif started:
		stage = Stage.READY if carried >= target and target > 0 else Stage.ACTIVE

	return {
		"id": quest_id,
		"title": String(quest.get("title", quest_id)),
		"giver": String(quest.get("giver", "")),
		"desc": String(quest.get("desc", "")),
		"stage": stage,
		"item": item,
		"goal": target,
		"progress": carried if stage == Stage.ACTIVE or stage == Stage.READY else 0,
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
