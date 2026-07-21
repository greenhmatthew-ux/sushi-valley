class_name Srs
extends RefCounted
## Spaced-repetition scheduler. 1:1 port of src/shared/learning/SrsSystem.ts.
##
## Deliberately simple. Not Anki. It must work, save, and feel good. Intervals are
## gentle; wrong answers reschedule soon without punishment.
##
## The port keeps the exact interval numbers, because they are tuned: early
## intervals are short (30s / 10min / 1h / 4h) so a card recycles WITHIN a single
## play session rather than being pushed to tomorrow. Only once a card has been
## seen a few times do intervals expand to real spaced-repetition pacing. Change
## these and the moment-to-moment feel of studying changes.
##
## Cards are plain Dictionaries (the SrsCard shape), mutated in place — matching
## the TS, where review() mutates and returns the same object. Times are epoch
## milliseconds, as in the TS build, so saved `dueAt` values stay comparable.

const MIN_EASE := 1.3
const DEFAULT_EASE := 2.3

const MIN := 60 * 1000            # one minute in ms
const HOUR := 60 * MIN
const DAY := 24 * HOUR


## Fresh scheduling state for a card that has never been reviewed. dueAt = now, so
## a newly unlocked card is immediately eligible.
static func new_card_defaults(now: float = -1.0) -> Dictionary:
	return {
		"dueAt": _now(now),
		"intervalDays": 0.0,
		"ease": DEFAULT_EASE,
		"correctCount": 0,
		"incorrectCount": 0,
		"lastReviewedAt": null,
	}


static func is_due(card: Dictionary, now: float = -1.0) -> bool:
	return card.get("unlocked", false) and card.get("dueAt", 0.0) <= _now(now)


## Cards due for review, soonest first.
static func due(cards: Array, now: float = -1.0) -> Array:
	var t := _now(now)
	var result: Array = cards.filter(func(c): return is_due(c, t))
	result.sort_custom(func(a, b): return a.get("dueAt", 0.0) < b.get("dueAt", 0.0))
	return result


## Apply a review grade, mutating and returning the card.
static func review(card: Dictionary, grade: String, now: float = -1.0) -> Dictionary:
	var t := _now(now)
	card["lastReviewedAt"] = t
	var correct := grade != "again"
	if correct:
		card["correctCount"] = int(card.get("correctCount", 0)) + 1
	else:
		card["incorrectCount"] = int(card.get("incorrectCount", 0)) + 1

	var ease: float = card.get("ease", DEFAULT_EASE)
	var interval: float = card.get("intervalDays", 0.0)

	match grade:
		"again":
			card["ease"] = maxf(MIN_EASE, ease - 0.2)
			card["intervalDays"] = 0.0
			card["dueAt"] = t + 30 * 1000   # ~30 seconds: see it again almost immediately

		"hard":
			card["ease"] = maxf(MIN_EASE, ease - 0.15)
			if interval < 1.0:
				card["intervalDays"] = 0.04   # ~1 hour
				card["dueAt"] = t + HOUR
			else:
				card["intervalDays"] = interval * 1.2
				card["dueAt"] = t + card["intervalDays"] * DAY

		"good":
			if interval < 0.01:
				# First good: 10 minutes — comes back within the session
				card["intervalDays"] = 0.007
				card["dueAt"] = t + 10 * MIN
			elif interval < 0.05:
				# Second good: 1 hour
				card["intervalDays"] = 0.04
				card["dueAt"] = t + HOUR
			elif interval < 0.2:
				# Third good: 4 hours
				card["intervalDays"] = 0.17
				card["dueAt"] = t + 4 * HOUR
			else:
				card["intervalDays"] = interval * ease
				card["dueAt"] = t + card["intervalDays"] * DAY

		"easy":
			card["ease"] = ease + 0.1
			if interval < 0.01:
				# First easy: 30 minutes
				card["intervalDays"] = 0.02
				card["dueAt"] = t + 30 * MIN
			elif interval < 0.1:
				# Second easy: 4 hours
				card["intervalDays"] = 0.17
				card["dueAt"] = t + 4 * HOUR
			else:
				card["intervalDays"] = interval * card["ease"] * 1.3
				card["dueAt"] = t + card["intervalDays"] * DAY

	return card


## Convenience: grade from a correct/incorrect boolean (used by combat/world prompts).
static func grade_from_correct(correct: bool) -> String:
	return "good" if correct else "again"


## Resolve the epoch-ms "now", defaulting to the wall clock. Injectable so tests
## can pin scheduling to a fixed instant — GDScript can't evaluate a function in a
## default parameter the way TS evaluates `now = Date.now()`, hence the sentinel.
static func _now(now: float) -> float:
	return now if now >= 0.0 else Time.get_unix_time_from_system() * 1000.0
