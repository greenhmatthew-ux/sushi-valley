class_name Bestiary
extends RefCounted
## What the player has fought and beaten, matched against the real enemy roster.
##
## The legacy TS build's `GameMenu` had a Compendium tab; PORT_NOTES.md and
## COMBAT_DESIGN.md both mention it and "bestiary flags" but neither the tracking
## nor the tab ever made it into this port. This is that record: seen (fought,
## win or lose) and defeated (won at least once), read back from the two profile
## primitives `LearningProgression`-adjacent code writes on combat_started and
## enemy_died.
##
## Node-free so it stays headless-testable, matching quest_journal.gd's shape.

enum Stage { UNSEEN, SEEN, DEFEATED }


## One enemy's record. {} when the id has no matching entry in `content.enemies`.
static func entry(profile, content, enemy_id: String) -> Dictionary:
	var enemy: Dictionary = content.enemy(enemy_id)
	if enemy.is_empty():
		return {}
	var record: Dictionary = {}
	if profile != null:
		record = profile.bestiary_entry(enemy_id)

	var stage := Stage.UNSEEN
	if bool(record.get("defeated", false)):
		stage = Stage.DEFEATED
	elif bool(record.get("seen", false)):
		stage = Stage.SEEN

	return {
		"id": enemy_id,
		"name": String(enemy.get("name", enemy_id)),
		"stage": stage,
		"kills": int(record.get("kills", 0)),
		"level": int(enemy.get("level", 1)),
		"max_hp": int(enemy.get("maxHp", 0)),
		"atk": int(enemy.get("atk", 0)),
		"def": int(enemy.get("def", 0)),
		"drops": enemy.get("drops", []),
		"zone_hint": String(enemy.get("zoneHint", "")),
	}


## Every authored enemy, in table order — the order the roster is authored in,
## which is also roughly a difficulty ladder. Unlike the quest journal, there is
## no "what's actionable now" question here, so there is nothing to reorder for.
static func all_entries(profile, content) -> Array:
	var out: Array = []
	for enemy_id in content.enemy_order:
		var e: Dictionary = entry(profile, content, String(enemy_id))
		if not e.is_empty():
			out.append(e)
	return out


## An unencountered enemy must not be named: the bestiary is a record of fights
## the player actually had, not a spoiler list of the whole planned roster (most
## of the 76 authored enemies belong to regions that are not built yet).
static func is_spoiler(entry_data: Dictionary) -> bool:
	return int(entry_data.get("stage", Stage.UNSEEN)) == Stage.UNSEEN


static func counts(entries: Array) -> Dictionary:
	var out := {"seen": 0, "defeated": 0, "unseen": 0}
	for e in entries:
		match int(e.get("stage", Stage.UNSEEN)):
			Stage.DEFEATED: out["defeated"] += 1
			Stage.SEEN: out["seen"] += 1
			_: out["unseen"] += 1
	return out


static func stage_label(stage: int) -> String:
	match stage:
		Stage.DEFEATED: return "Defeated"
		Stage.SEEN: return "Encountered"
		_: return "Unknown"
