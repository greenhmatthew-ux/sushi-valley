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
