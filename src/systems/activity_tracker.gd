class_name ActivityTracker
extends RefCounted
## One normalized view of actionable work for the Journal, objective HUD, and
## returning-player summary. Quest, Raid, and Expedition state machines remain
## authoritative; this only translates their existing state into shared copy and
## a single saved selection.
##
## `trackedActivity` is additive and optional. Old saves without it keep the
## automatic highest-priority objective until the player explicitly tracks one.

const Journal = preload("res://src/systems/quest_journal.gd")
const RaidLogic = preload("res://src/systems/raid_logic.gd")
const ExpeditionLogic = preload("res://src/systems/expedition_logic.gd")

const TRACKED_KEY := "trackedActivity"


static func quest_entries(profile, content, inventory) -> Array:
	var entries: Array = []
	for raw in Journal.all_entries(profile, content, inventory):
		if Journal.is_spoiler(raw):
			continue
		entries.append(_quest_entry(raw, content))
	return entries


static func structured_entries(profile, content) -> Array:
	var entries: Array = []
	for raw_id in content.raids:
		var raid: Dictionary = content.raids[raw_id]
		var raid_entry := _raid_entry(profile, content, raid)
		if not raid_entry.is_empty():
			entries.append(raid_entry)
	for raw_id in content.expeditions:
		var expedition: Dictionary = content.expeditions[raw_id]
		var expedition_entry := _expedition_entry(profile, content, expedition)
		if not expedition_entry.is_empty():
			entries.append(expedition_entry)
	return entries


static func all_entries(profile, content, inventory) -> Array:
	var entries := quest_entries(profile, content, inventory)
	entries.append_array(structured_entries(profile, content))
	return entries


static func actionable_entries(profile, content, inventory) -> Array:
	var entries: Array = all_entries(profile, content, inventory).filter(
		func(entry): return bool(entry.get("trackable", false)))
	entries.sort_custom(func(a, b):
		var priority_a := int(a.get("priority", 99))
		var priority_b := int(b.get("priority", 99))
		if priority_a != priority_b:
			return priority_a < priority_b
		return String(a.get("key", "")) < String(b.get("key", "")))
	return entries


static func tracked_key(profile) -> String:
	return String(profile.data.get(TRACKED_KEY, ""))


static func track(profile, content, inventory, key: String) -> bool:
	var valid := false
	for entry in actionable_entries(profile, content, inventory):
		if String(entry.get("key", "")) == key:
			valid = true
			break
	if not valid or tracked_key(profile) == key:
		return false
	profile.data[TRACKED_KEY] = key
	profile.save()
	return true


static func clear(profile) -> bool:
	if not profile.data.has(TRACKED_KEY):
		return false
	profile.data.erase(TRACKED_KEY)
	profile.save()
	return true


## The saved choice wins while it remains actionable. Otherwise the strongest
## current hook wins: reward/boss ready, mission step, active quest, then a new
## or repeatable structured mission.
static func current(profile, content, inventory) -> Dictionary:
	var entries := actionable_entries(profile, content, inventory)
	var selected := tracked_key(profile)
	if not selected.is_empty():
		for entry in entries:
			if String(entry.get("key", "")) == selected:
				return entry
	return entries[0] if not entries.is_empty() else {}


## A completed/invalid saved selection must not strand the HUD. Reconcile only
## when a selection already existed; an old save without one stays migration-free
## and simply uses current()'s automatic choice.
static func reconcile(profile, content, inventory) -> Dictionary:
	var selected := tracked_key(profile)
	var entry := current(profile, content, inventory)
	if selected.is_empty():
		return entry
	var next_key := String(entry.get("key", ""))
	if next_key == selected:
		return entry
	if next_key.is_empty():
		profile.data.erase(TRACKED_KEY)
	else:
		profile.data[TRACKED_KEY] = next_key
	profile.save()
	return entry


static func _quest_entry(raw: Dictionary, content) -> Dictionary:
	var id := String(raw.get("id", ""))
	var stage := int(raw.get("stage", Journal.Stage.UNMET))
	var giver := String(raw.get("giver", "the giver"))
	var state := Journal.stage_label(stage)
	var detail := String(raw.get("desc", ""))
	var hud_detail := detail
	var trackable := false
	var priority := 99
	var summary_kind := ""
	var summary_text := ""
	match stage:
		Journal.Stage.READY:
			detail = "Return to %s to claim the reward." % giver
			hud_detail = "Return to %s" % giver
			trackable = true
			priority = 0
			summary_kind = "ready"
			summary_text = "Ready to turn in: %s — see %s" % [raw["title"], giver]
		Journal.Stage.ACTIVE:
			var item_name := String(content.item(String(raw.get("item", ""))).get(
				"name", raw.get("item", "")))
			var objectives: Array = raw.get("objectives", [])
			if objectives.size() > 1:
				var checks: Array[String] = []
				var completed := 0
				for objective in objectives:
					var row: Dictionary = objective
					var is_complete := bool(row.get("complete", false))
					if is_complete:
						completed += 1
					checks.append("[%s] %s %d/%d" % [
						"x" if is_complete else " ", row.get("label", row.get("item", "")),
						row.get("progress", 0), row.get("goal", 0)])
				detail = "   |   ".join(checks)
				summary_text = "In progress: %s - %d/%d objectives" % [
					raw["title"], completed, objectives.size()]
			else:
				detail = "%s  %d/%d   ·   for %s" % [
					item_name, raw.get("progress", 0), raw.get("goal", 0), giver]
			hud_detail = "%s  %d/%d" % [
				item_name, raw.get("progress", 0), raw.get("goal", 0)]
			trackable = true
			priority = 2
			summary_kind = "active"
			if summary_text.is_empty():
				summary_text = "In progress: %s — %d/%d" % [
					raw["title"], int(raw.get("progress", 0)), int(raw.get("goal", 0))]
		Journal.Stage.DONE:
			detail = "Finished for %s." % giver
	return {
		"key": "quest:" + id, "id": id, "kind_id": "quest", "kind": "Quest",
		"title": String(raw.get("title", id)), "state": state,
		"stage": str(stage), "stage_code": stage,
		"detail": detail, "hud_detail": hud_detail,
		"reward": _reward_summary(content, raw.get("reward", {}), ""),
		"trackable": trackable, "priority": priority,
		"summary_kind": summary_kind, "summary_text": summary_text,
	}


static func _raid_entry(profile, content, raid: Dictionary) -> Dictionary:
	var id := String(raid.get("id", ""))
	var progress := RaidLogic.progress(profile, id)
	if progress.is_empty() and not RaidLogic.can_start(profile, raid):
		return {}
	var stage := String(progress.get("stage", "available"))
	var giver := String(raid.get("npcId", "the mission giver")).capitalize()
	var state := "Available"
	var detail := "%s Talk to %s to begin." % [String(raid.get("description", "")), giver]
	var hud_detail := "Talk to %s to begin" % giver
	var priority := 4
	match stage:
		"active":
			state = "Recall"
			detail = "Complete the focused recall with %s." % giver
			hud_detail = "Complete the focused recall with %s" % giver
			priority = 1
		"recall-cleared":
			state = "Boss ready"
			var enemy: Dictionary = content.enemy(String(raid.get("encounterId", "")))
			var enemy_name := String(enemy.get("name", raid.get("encounterId", "the boss")))
			detail = "Defeat %s to finish the mission." % enemy_name
			hud_detail = "Defeat %s" % enemy_name
			priority = 0
		"complete":
			state = "Complete"
			detail = "Finished %d time%s. The Forest Expedition is unlocked." % [
				int(progress.get("completions", 1)),
				"" if int(progress.get("completions", 1)) == 1 else "s"]
	return _structured_model(content, "raid", id, "Raid",
		String(raid.get("displayName", id)), state, stage, detail, hud_detail,
		raid.get("reward", {}), "raid:" + id, stage != "complete", priority)


static func _expedition_entry(profile, content, expedition: Dictionary) -> Dictionary:
	var id := String(expedition.get("id", ""))
	var progress := ExpeditionLogic.progress(profile, id)
	if progress.is_empty() and not ExpeditionLogic.unlock_ready(profile, expedition):
		return {}
	var stage := String(progress.get("stage", "available"))
	var state := "Available"
	var detail := "%s Start at its marked gate." % String(
		expedition.get("description", "A structured field mission."))
	var hud_detail := "Start at the marked gate"
	var priority := 4
	match stage:
		"active":
			state = "In progress"
			detail = "Clear the expedition's opening encounter."
			hud_detail = "Clear the opening encounter"
			priority = 1
		"encounter-cleared":
			state = "Objective"
			detail = "Recover the expedition objective."
			hud_detail = "Recover the expedition objective"
			priority = 1
		"objective-recovered":
			state = "Recall"
			detail = "Complete the focused recall at the recovered objective."
			hud_detail = "Complete recall at the objective"
			priority = 1
		"recall-cleared":
			state = "Boss ready"
			var enemy: Dictionary = content.enemy(String(expedition.get("bossEncounterId", "")))
			var enemy_name := String(enemy.get(
				"name", expedition.get("bossEncounterId", "the boss")))
			detail = "Defeat %s and bank the rewards." % enemy_name
			hud_detail = "Defeat %s" % enemy_name
			priority = 0
		"complete":
			state = "Repeatable" if bool(expedition.get("repeatable", false)) else "Complete"
			detail = "Finished %d time%s.%s" % [
				int(progress.get("completions", 1)),
				"" if int(progress.get("completions", 1)) == 1 else "s",
				" Return to its gate to run it again." if bool(
					expedition.get("repeatable", false)) else ""]
			hud_detail = "Return to the gate to run it again"
	var trackable := stage != "complete" or bool(expedition.get("repeatable", false))
	return _structured_model(content, "expedition", id, "Expedition",
		String(expedition.get("displayName", id)), state, stage, detail, hud_detail,
		expedition.get("reward", {}), "expedition:" + id, trackable, priority)


static func _structured_model(content, kind_id: String, id: String, kind: String,
		title: String, state: String, stage: String, detail: String, hud_detail: String,
		reward: Dictionary, source: String, trackable: bool, priority: int) -> Dictionary:
	return {
		"key": "%s:%s" % [kind_id, id], "id": "%s_%s" % [kind_id, id],
		"raw_id": id, "kind_id": kind_id, "kind": kind,
		"title": title, "state": state, "stage": stage, "detail": detail,
		"hud_detail": hud_detail, "reward": _reward_summary(content, reward, source),
		"trackable": trackable, "priority": priority,
		"summary_kind": "mission" if trackable else "",
		"summary_text": "%s: %s — %s" % [kind, title, hud_detail] if trackable else "",
	}


static func _reward_summary(content, reward: Dictionary, source: String) -> String:
	var parts: Array[String] = []
	var tangible := QuestLogic.describe_reward(
		reward, func(item_id): return content.item(item_id).get("name", item_id))
	if not tangible.is_empty():
		parts.append(tangible)
	if not source.is_empty():
		for raw_id in content.recipes:
			var recipe: Dictionary = content.recipes[raw_id]
			if String(recipe.get("discoverySource", "")) == source:
				parts.append("%s recipe" % String(recipe.get("name", raw_id)))
	return "Rewards: %s" % " · ".join(parts) if not parts.is_empty() else ""
