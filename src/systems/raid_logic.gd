extends RefCounted
## The Raid state machine. Port of src/game/systems/RaidSystem.ts (TS archive).
##
## A Raid is a structured mission (RAID_DESIGN.md): briefing NPC, focused recall,
## a boss encounter, then rewards, unlock flags, and a discovered recipe. This
## file is the whole tracker — the entity that talks to the player (raid_teacher)
## drives it, and the pure functions here decide every transition, so a headless
## test can pin the TS behavior.
##
## Persisted shape is byte-compatible with the TS build (cloud-save rule:
## save-compatible IDs). profile.data["raids"][raid_id] =
##   { "stage": "active" | "recall-cleared" | "complete",
##     "startedAt": <ms>, "completedAt": <ms>, "completions": <int> }

const CraftRules = preload("res://src/systems/crafting_logic.gd")


## The per-raid progress table, created on first touch like the TS `states()`.
static func states(profile) -> Dictionary:
	if not profile.data.has("raids") or profile.data["raids"] is not Dictionary:
		profile.data["raids"] = {}
	return profile.data["raids"]


## {} when the raid has never been started.
static func progress(profile, raid_id: String) -> Dictionary:
	return states(profile).get(raid_id, {})


static func can_start(profile, raid: Dictionary) -> bool:
	if raid.is_empty():
		return false
	var prog := progress(profile, String(raid.get("id", "")))
	if String(prog.get("stage", "")) == "complete" and not bool(raid.get("repeatable", false)):
		return false
	for flag in raid.get("requiredFlags", []):
		if not profile.get_flag(String(flag)):
			return false
	return true


## Begin (or resume) a raid. Mirrors TS startRaid: when the raid cannot start,
## the existing progress (or {}) comes back so the caller can tell "locked"
## from "already done"; an unfinished attempt is resumed, never restarted.
static func start(profile, raid: Dictionary) -> Dictionary:
	var id := String(raid.get("id", ""))
	if not can_start(profile, raid):
		return progress(profile, id)
	var existing := progress(profile, id)
	if not existing.is_empty() and String(existing.get("stage", "")) != "complete":
		return existing
	var prog := {
		"stage": "active",
		"startedAt": _now_ms(),
		"completions": int(existing.get("completions", 0)),
	}
	states(profile)[id] = prog
	profile.save()
	return prog


static func mark_recall_cleared(profile, raid_id: String) -> bool:
	var prog := progress(profile, raid_id)
	if prog.is_empty() or String(prog.get("stage", "")) == "complete":
		return false
	prog["stage"] = "recall-cleared"
	profile.save()
	return true


## Boss down: grant rewards, set unlock flags, discover the raid recipe, and
## save the completion. Returns the TS summary line for a toast, or "" when the
## raid was not at the recall-cleared stage (nothing is granted twice).
## `content` is DB (item names + recipes), `inventory` the Inv autoload.
static func complete_boss(profile, content, inventory, raid: Dictionary) -> String:
	var id := String(raid.get("id", ""))
	var prog := progress(profile, id)
	if raid.is_empty() or prog.is_empty() or String(prog.get("stage", "")) != "recall-cleared":
		return ""

	var reward: Dictionary = raid.get("reward", {})
	for item in reward.get("items", []):
		inventory.add(String(item.get("id", "")), int(item.get("qty", 0)))
	var coins := int(reward.get("coins", 0))
	if coins > 0:
		inventory.add_coins(coins)
	for flag in raid.get("unlockFlags", []):
		profile.set_flag(String(flag))
	var recipe := CraftRules.discover_from_source(
		profile.data, content.recipes.values(), "raid:%s" % id)
	prog["stage"] = "complete"
	prog["completedAt"] = _now_ms()
	prog["completions"] = int(prog.get("completions", 0)) + 1
	profile.save()

	var parts: Array[String] = []
	if coins > 0:
		parts.append("%d coins" % coins)
	for item in reward.get("items", []):
		var item_id := String(item.get("id", ""))
		parts.append("%d× %s" % [int(item.get("qty", 0)),
			String(content.item(item_id).get("name", item_id))])
	var recipe_note := ""
	if not recipe.is_empty():
		recipe_note = ", recipe: %s" % String(recipe.get("name", ""))
	# "Forest Expedition unlocked." is literal in the TS message too — with one
	# raid in the game they are the same sentence. Generalise when a second raid
	# exists, not before (RAID_DESIGN.md: no speculative split).
	return "%s complete — %s%s. Forest Expedition unlocked." % [
		String(raid.get("displayName", id)), ", ".join(parts), recipe_note]


static func _now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0
