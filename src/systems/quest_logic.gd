class_name QuestLogic
extends RefCounted
## Pure state resolution for a simple "clear N enemies" fetch/hunt quest.
##
## Node-free and headless-testable: the quest-giver entity feeds it the persisted
## flags plus the live kill count and gets back which line to say, so the branching
## rules are asserted in isolation instead of by clicking through dialogue.

## Which stage the quest is in, from its persisted flags and progress:
##   "intro"  — never accepted; offer it.
##   "active" — accepted, not enough kills yet; nudge.
##   "turnin" — accepted and the kill goal is met; hand out the reward now.
##   "done"   — already turned in; a friendly repeat line.
static func stage(started: bool, done: bool, kills: int, target: int) -> String:
	if done:
		return "done"
	if not started:
		return "intro"
	if kills >= target:
		return "turnin"
	return "active"


## Kills still needed (never negative), for the nudge line.
static func remaining(kills: int, target: int) -> int:
	return maxi(0, target - kills)


## Fill the {progress} / {goal} / {remaining} placeholders the authored quest lines in
## data/game/quests.json use, e.g. "Those spore caps — {progress} of {goal} so far?".
## Unknown placeholders are left alone rather than blanked, so a typo in the data is visible
## instead of silently swallowing text.
static func fill(line: String, progress: int, goal: int) -> String:
	return line \
		.replace("{progress}", str(progress)) \
		.replace("{goal}", str(goal)) \
		.replace("{remaining}", str(remaining(progress, goal)))


## Pick the line list for a stage from a quest definition, falling back sensibly so a quest
## missing one of the optional arrays still speaks rather than going silent.
static func lines_for(quest: Dictionary, stage_name: String) -> Array:
	match stage_name:
		"intro":
			return quest.get("offerLines", [])
		"active":
			return quest.get("progressLines", quest.get("offerLines", []))
		"turnin":
			return quest.get("turnInLines", [])
		_:
			# Repeat visits after completion reuse the thank-you rather than re-offering.
			return quest.get("turnInLines", [])


## Summarise a reward block ({ "coins": 40, "items": [{id, qty}] }) for a toast.
## `namer` maps an item id to its display name.
static func describe_reward(reward: Dictionary, namer: Callable) -> String:
	var parts: Array[String] = []
	var coins := int(reward.get("coins", 0))
	if coins > 0:
		parts.append("%d coins" % coins)
	for entry in reward.get("items", []):
		if not (entry is Dictionary):
			continue
		var id := String(entry.get("id", ""))
		if id.is_empty():
			continue
		var qty := int(entry.get("qty", 1))
		var name := String(namer.call(id)) if namer.is_valid() else id
		parts.append(name if qty == 1 else "%dx %s" % [qty, name])
	return " and ".join(parts)
