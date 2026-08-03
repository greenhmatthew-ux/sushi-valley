extends RefCounted
## The Expedition state machine. Port of ExpeditionSystem.ts (TS archive).
##
## An Expedition is a handcrafted instance (EXPEDITION_DESIGN.md): enter from
## the overworld, clear a guard encounter, recover the objective, clear a
## focused recall, defeat the boss, bank rewards, return. Five saved stages so
## a retreat at any point resumes exactly where the save says — the room
## drives these functions; every transition rule lives here for headless tests.
##
## Persisted shape is byte-compatible with the TS build:
## profile.data["expeditions"][id] =
##   { "stage": "active" | "encounter-cleared" | "objective-recovered"
##            | "recall-cleared" | "complete",
##     "startedAt": <ms>, "completedAt": <ms>, "completions": <int> }

const RaidLogic = preload("res://src/systems/raid_logic.gd")
const CraftRules = preload("res://src/systems/crafting_logic.gd")


static func states(profile) -> Dictionary:
	if not profile.data.has("expeditions") or profile.data["expeditions"] is not Dictionary:
		profile.data["expeditions"] = {}
	return profile.data["expeditions"]


## {} when the expedition has never been started.
static func progress(profile, expedition_id: String) -> Dictionary:
	return states(profile).get(expedition_id, {})


## Flags and raid completions only — the "is the gate lit up" question, which
## stays true after a non-repeatable completion (TS expeditionUnlockReady).
static func unlock_ready(profile, expedition: Dictionary) -> bool:
	if expedition.is_empty():
		return false
	for flag in expedition.get("requiredFlags", []):
		if not profile.get_flag(String(flag)):
			return false
	for raid_id in expedition.get("requiredRaidIds", []):
		if String(RaidLogic.progress(profile, String(raid_id)).get("stage", "")) != "complete":
			return false
	return true


static func can_enter(profile, expedition: Dictionary) -> bool:
	if expedition.is_empty() or String(expedition.get("status", "")) != "playable":
		return false
	var prog := progress(profile, String(expedition.get("id", "")))
	if String(prog.get("stage", "")) == "complete" and not bool(expedition.get("repeatable", false)):
		return false
	return unlock_ready(profile, expedition)


## Begin, resume, or (if repeatable and finished) restart. Mirrors TS
## startExpedition: a blocked entry hands back the existing progress (or {})
## so the gate can tell "sealed" from "already done"; an unfinished run always
## resumes its saved stage; a repeatable rerun keeps its completion count.
static func start(profile, expedition: Dictionary) -> Dictionary:
	var id := String(expedition.get("id", ""))
	if not can_enter(profile, expedition):
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


static func mark_encounter_cleared(profile, expedition_id: String) -> bool:
	return _advance(profile, expedition_id, "active", "encounter-cleared")


static func recover_objective(profile, expedition_id: String) -> bool:
	return _advance(profile, expedition_id, "encounter-cleared", "objective-recovered")


static func mark_recall_cleared(profile, expedition_id: String) -> bool:
	return _advance(profile, expedition_id, "objective-recovered", "recall-cleared")


## Boss down: rewards, unlock flags, recipe discovery, completion — exactly
## once. Returns the TS summary line, or "" when the run was not at the
## recall-cleared stage.
static func complete_boss(profile, content, inventory, expedition: Dictionary) -> String:
	var id := String(expedition.get("id", ""))
	var prog := progress(profile, id)
	if expedition.is_empty() or prog.is_empty() \
			or String(prog.get("stage", "")) != "recall-cleared":
		return ""

	var reward: Dictionary = expedition.get("reward", {})
	for item in reward.get("items", []):
		inventory.add(String(item.get("id", "")), int(item.get("qty", 0)))
	var coins := int(reward.get("coins", 0))
	if coins > 0:
		inventory.add_coins(coins)
	for flag in expedition.get("unlockFlags", []):
		profile.set_flag(String(flag))
	var recipe := CraftRules.discover_from_source(
		profile.data, content.recipes.values(), "expedition:%s" % id)
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
	return "%s complete — %s%s." % [
		String(expedition.get("displayName", id)), ", ".join(parts), recipe_note]


## One strictly ordered stage step; anything else is a no-op. The chain is the
## room's spine: guard -> lunchbox -> recall -> boss, no skipping, no repeats.
static func _advance(profile, expedition_id: String, from_stage: String, to_stage: String) -> bool:
	var prog := progress(profile, expedition_id)
	if prog.is_empty() or String(prog.get("stage", "")) != from_stage:
		return false
	prog["stage"] = to_stage
	profile.save()
	return true


static func _now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0
