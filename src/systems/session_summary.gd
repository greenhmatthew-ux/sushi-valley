class_name SessionSummary
extends RefCounted
## The returning player's "Previously" card: what is actionable right now.
##
## UI_UX_GUIDE section 6 asks that a solo player coming back after days away see
## ready activities and one Continue action instead of rereading every log. This
## assembles that card's lines from QuestJournal entries and live counts; deciding
## what deserves attention is game logic, so it lives here where a headless test
## can pin it, and the panel that renders it stays dumb.

const Journal = preload("res://src/systems/quest_journal.gd")

## The card must stay a glance, not a report: the 640x360 shell fits about eight
## short lines before the panel needs a scrollbar, which would defeat the point.
const MAX_QUEST_LINES := 3

## `entries` is QuestJournal.all_entries() output. Returns
##   {"show": bool, "lines": [{"kind": String, "text": String}]}
## kinds: "ready" | "active" | "more" | "review" | "points".
## Ready quests lead because they are finished work awaiting a reward — the
## strongest possible "pick up where you left off" hook.
static func build(entries: Array, due: int, talent_points: int,
		attribute_points: int) -> Dictionary:
	var lines: Array = []
	var ready: Array = entries.filter(
		func(e): return int(e.get("stage", -1)) == Journal.Stage.READY)
	var active: Array = entries.filter(
		func(e): return int(e.get("stage", -1)) == Journal.Stage.ACTIVE)

	for e in ready.slice(0, MAX_QUEST_LINES):
		lines.append({"kind": "ready",
			"text": "Ready to turn in: %s — see %s" % [e["title"], e["giver"]]})
	var active_room := maxi(0, MAX_QUEST_LINES - ready.size())
	for e in active.slice(0, active_room):
		lines.append({"kind": "active",
			"text": "In progress: %s — %d/%d" % [e["title"], int(e["progress"]), int(e["goal"])]})
	var overflow := ready.size() + active.size() - mini(ready.size(), MAX_QUEST_LINES) \
		- mini(active.size(), active_room)
	if overflow > 0:
		lines.append({"kind": "more",
			"text": "…and %d more in the Journal" % overflow})

	if due > 0:
		lines.append({"kind": "review", "text": "%d words due for review" % due})

	# One combined line: two separate "points" rows would crowd out a quest line,
	# and both spend in the same place (the Pause Hub).
	if talent_points > 0 or attribute_points > 0:
		var parts: Array[String] = []
		if talent_points > 0:
			parts.append("%d Talent" % talent_points)
		if attribute_points > 0:
			parts.append("%d Attribute" % attribute_points)
		lines.append({"kind": "points",
			"text": "Points to spend: %s" % " · ".join(parts)})

	return {"show": not lines.is_empty(), "lines": lines}
