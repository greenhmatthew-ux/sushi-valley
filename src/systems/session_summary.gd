class_name SessionSummary
extends RefCounted
## The returning player's "Previously" card: what is actionable right now.
##
## ActivityTracker normalizes Quests, Raids, and Expeditions. This model chooses
## the few lines worth showing after a break while the rendering panel stays dumb.

## The card must stay a glance, not a report: the 640x360 shell fits about eight
## short lines before a scrollbar would defeat the point.
const MAX_ACTIVITY_LINES := 3
const MAX_TOTAL_LINES := 7


## `entries` is ActivityTracker.actionable_entries() output. Returns
##   {"show": bool, "lines": [{"kind": String, "text": String}]}
## kinds: "ready" | "active" | "mission" | "more" | "review" | "points".
## The saved selection leads; otherwise tracker priority puts ready rewards and
## bosses before ordinary work in progress.
static func build(entries: Array, due: int, talent_points: int,
		attribute_points: int, tracked_key: String = "",
		daily_lines: Array = []) -> Dictionary:
	var lines: Array = []
	var actionable: Array = entries.filter(
		func(entry): return bool(entry.get("trackable", false)) \
			and not String(entry.get("summary_text", "")).is_empty())
	actionable.sort_custom(func(a, b):
		var a_tracked := String(a.get("key", "")) == tracked_key
		var b_tracked := String(b.get("key", "")) == tracked_key
		if a_tracked != b_tracked:
			return a_tracked
		var priority_a := int(a.get("priority", 99))
		var priority_b := int(b.get("priority", 99))
		if priority_a != priority_b:
			return priority_a < priority_b
		return String(a.get("key", "")) < String(b.get("key", "")))

	for entry in actionable.slice(0, MAX_ACTIVITY_LINES):
		lines.append({"kind": String(entry.get("summary_kind", "active")),
			"text": String(entry.get("summary_text", ""))})
	var overflow := maxi(0, actionable.size() - MAX_ACTIVITY_LINES)
	if overflow > 0:
		lines.append({"kind": "more",
			"text": "…and %d more in the Journal" % overflow})

	# Daily life-skill alerts fill only the room left after activities and the two
	# progression reminders. The card remains a glance even on a busy save.
	var reserved := (1 if due > 0 else 0) \
		+ (1 if talent_points > 0 or attribute_points > 0 else 0)
	var daily_room := maxi(0, MAX_TOTAL_LINES - lines.size() - reserved)
	for raw_line in daily_lines.slice(0, daily_room):
		var daily: Dictionary = raw_line
		if not String(daily.get("text", "")).is_empty():
			lines.append({"kind": String(daily.get("kind", "active")),
				"text": String(daily.get("text", ""))})

	if due > 0:
		lines.append({"kind": "review", "text": "%d words due for review" % due})

	# One combined line: two separate points rows would crowd out an activity,
	# and both pools spend in the same Pause Hub.
	if talent_points > 0 or attribute_points > 0:
		var parts: Array[String] = []
		if talent_points > 0:
			parts.append("%d Talent" % talent_points)
		if attribute_points > 0:
			parts.append("%d Attribute" % attribute_points)
		lines.append({"kind": "points",
			"text": "Points to spend: %s" % " · ".join(parts)})

	return {"show": not lines.is_empty(), "lines": lines}
