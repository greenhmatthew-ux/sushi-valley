class_name QuestJournal
extends RefCounted
## What the player has taken on, finished, and not yet met.
##
## Node-free so it stays headless-testable, matching the other files in
## src/systems/. The quest-giver entity already resolves the *current* quest's
## dialogue stage; this answers the different question of what the whole run
## looks like, which nothing could previously see.
##
## Quest stage is persisted as two profile flags per quest —
## `quest_<id>_started` and `quest_<id>_done`. Typed activity quests additionally
## snapshot lifetime counters under `questProgress`, so only post-acceptance work
## advances them. Finished quests remain visible after their giver stops offering.

enum Stage { UNMET, ACTIVE, READY, DONE }

## Order the journal reads in: what to do now, then what is waiting, then a
## record of what was finished. An unmet quest is deliberately last — it is the
## least actionable, and listing it first would read as a demand.
const STAGE_ORDER := [Stage.READY, Stage.ACTIVE, Stage.DONE, Stage.UNMET]


static func started_flag(quest_id: String) -> String:
	return "quest_%s_started" % quest_id


static func done_flag(quest_id: String) -> String:
	return "quest_%s_done" % quest_id


## Resolve the first unfinished quest in a data-authored chain. A giver keeps one
## stable root id in the scene, while completed quests can point to a follow-up.
## Missing links and accidental cycles stop safely at the last valid row.
static func current_in_chain(profile, content, root_quest_id: String) -> Dictionary:
	var current_id := root_quest_id
	var current: Dictionary = {}
	var visited := {}
	while not current_id.is_empty() and not visited.has(current_id):
		var candidate: Dictionary = content.quest(current_id)
		if candidate.is_empty():
			return current
		current = candidate
		visited[current_id] = true
		if profile == null or not profile.get_flag(done_flag(current_id)):
			return current
		var next_id := String(current.get("followUpQuest", ""))
		if next_id.is_empty():
			return current
		current_id = next_id
	return current


## Accept once and snapshot lifetime activity totals. Activity objectives then
## count only work performed after this conversation, while item objectives keep
## their live Bag semantics.
static func begin(profile, quest: Dictionary) -> bool:
	var quest_id := String(quest.get("id", ""))
	if profile == null or quest_id.is_empty() or profile.get_flag(started_flag(quest_id)):
		return false
	profile.set_flag(started_flag(quest_id))
	var baselines := {}
	var authored: Variant = quest.get("objectives", [])
	if authored is Array:
		for raw in authored:
			if raw is Dictionary and String(raw.get("type", "item")) == "activity":
				var activity_id := String(raw.get("activity", ""))
				if activity_id in LearningProfile.ACTIVITY_IDS:
					baselines[activity_id] = profile.activity_count(activity_id)
	if not baselines.is_empty():
		if not profile.data.has("questProgress") \
				or profile.data["questProgress"] is not Dictionary:
			profile.data["questProgress"] = {}
		profile.data["questProgress"][quest_id] = {"activityBaselines": baselines}
	return true


## Normalize both quest shapes into one checklist. Existing authored quests keep
## their single item `goal`; objective lists may mix held-item checks with saved
## activity counters. `consume: false` lets a commission inspect permanent gear.
static func objectives(quest: Dictionary, content, inventory, profile = null) -> Array:
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
		var objective_type := String(objective.get("type", "item"))
		if objective_type == "activity":
			var activity_id := String(objective.get("activity", ""))
			if activity_id not in LearningProfile.ACTIVITY_IDS:
				continue
			var target := maxi(1, int(objective.get("qty", 1)))
			var current: int = profile.activity_count(activity_id) if profile != null else 0
			var baseline: int = _activity_baseline(profile,
				String(quest.get("id", "")), activity_id)
			var progress: int = mini(target, maxi(0, current - baseline))
			rows.append({
				"type": "activity",
				"activity": activity_id,
				"item": "",
				"label": String(objective.get("label", activity_id.replace("_", " ").capitalize())),
				"goal": target,
				"progress": progress,
				"complete": progress >= target,
				"consume": false,
			})
			continue
		if objective_type != "item":
			continue
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
			"type": "item",
			"item": item_id,
			"label": String(objective.get("label", item_name)),
			"goal": target,
			"progress": mini(carried, target),
			"complete": carried >= target,
			"consume": bool(objective.get("consume", true)),
		})
	return rows


static func _activity_baseline(profile, quest_id: String, activity_id: String) -> int:
	if profile == null:
		return 0
	var quest_progress: Dictionary = profile.data.get("questProgress", {})
	var progress: Dictionary = quest_progress.get(quest_id, {})
	var baselines: Dictionary = progress.get("activityBaselines", {})
	return maxi(0, int(baselines.get(activity_id, 0)))


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
	var objective_rows := objectives(quest, content, inventory, profile)
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
		"objective_type": String(current.get("type", "item")),
		"objective_label": String(current.get("label", item)),
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
