extends RefCounted
## Decides what the toast strip shows, so no message silently vanishes.
##
## The layer used to overwrite the visible toast the instant another arrived, so
## a burst (loot + XP + quest complete) kept only its last line. UI_UX_GUIDE
## section 5 asks that notifications queue and aggregate repeated loot/XP
## instead. This is that policy as pure logic: callers push raw toast text and
## tick with a clock, and it answers what to display — which keeps the burst
## rules pinned by a headless test while the CanvasLayer stays a dumb label.
##
## Rules:
##   - A message identical to the visible one folds into it as a ×N count and
##     keeps it on screen (the pickup spam case).
##   - A message identical to the newest waiting one folds into that instead,
##     so the queue never holds the same line twice in a row.
##   - Anything else waits its turn, first in first out.
##   - A backlog shortens each message's stay, so a burst drains quickly
##     without any line becoming unreadable.

## How long one message stays up alone. Matches the old layer's feel.
const HOLD_SECONDS := 2.2
## The shorter stay while others wait. Long enough to read a short line.
const BACKLOG_HOLD_SECONDS := 1.0

var _current := {}      ## {"text": String, "count": int, "since": float}
var _queue: Array = []  ## same shape, not yet shown


## Accept a toast. `now` is seconds from any monotonic clock. Returns true when
## the visible message changed (new text or a bumped count) and needs redrawing.
func push(text: String, now: float) -> bool:
	if not _current.is_empty() and _current["text"] == text:
		_current["count"] = int(_current["count"]) + 1
		# Still happening, so keep showing it — the count is the history.
		_current["since"] = now
		return true
	if not _queue.is_empty() and _queue.back()["text"] == text:
		_queue.back()["count"] = int(_queue.back()["count"]) + 1
		return false
	var entry := {"text": text, "count": 1, "since": now}
	if _current.is_empty():
		_current = entry
		return true
	_queue.append(entry)
	return false


## Advance the clock. Returns true when the display changed: either the next
## waiting message came up, or the last one expired (is_showing() says which).
func tick(now: float) -> bool:
	if _current.is_empty():
		return false
	var hold := BACKLOG_HOLD_SECONDS if not _queue.is_empty() else HOLD_SECONDS
	if now - float(_current["since"]) < hold:
		return false
	if _queue.is_empty():
		_current = {}
		return true
	_current = _queue.pop_front()
	_current["since"] = now
	return true


func is_showing() -> bool:
	return not _current.is_empty()


func display_text() -> String:
	if _current.is_empty():
		return ""
	var count := int(_current["count"])
	return String(_current["text"]) if count == 1 else "%s  ×%d" % [_current["text"], count]


func backlog() -> int:
	return _queue.size()
