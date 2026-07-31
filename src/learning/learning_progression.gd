class_name LearningProgression
extends RefCounted
## High-level facade every surface calls. Port of
## src/shared/learning/LearningProgressionSystem.ts.
##
## Wraps the profile + SRS so callers never touch scheduling internals: it builds
## review prompts, records answers, awards XP, and auto-unlocks the next lesson
## when the current one is mastered. The Learning autoload owns one instance and
## forwards its lesson-unlock notice to a Bus toast; tests construct it directly.

## XP awarded per correct grade. "again" (wrong) earns nothing.
const XP_BY_GRADE := {"easy": 12, "good": 10, "hard": 6}

## Recall eligibility. Several imported Anki decks map the answer field to page
## numbers, stroke counts, or whole explanation paragraphs (282 of 1330 source
## cards). Those can never be a sane rune or choice in a four-option recall UI —
## as prompts they ask gibberish, and as distractors one paragraph of English
## blows the combat/recall panels past the viewport. They are filtered out of
## every selection path here; the imported data itself stays untouched.
const MAX_CHOICE_LENGTH := 60

var profile: LearningProfile
var _content
## Fired with a lesson title when auto-progression unlocks a new lesson. The game
## wires this to a toast; the webapp ignored it.
var on_lesson_unlock: Callable = Callable()
## Fired with (amount, new_total) whenever XP changes. Same pattern as on_lesson_unlock: this
## file must stay node-free (it is pure logic), so the Learning autoload owns turning this into
## a Bus signal. Without it, XP moved silently — Bus.xp_gained had two listeners and no
## emitter, so level-derived player stats never grew until the scene reloaded.
var on_xp_changed: Callable = Callable()


func _init(learning_profile: LearningProfile, content) -> void:
	profile = learning_profile
	_content = content


## Build a micro-review prompt from a specific card, the next due card, or (when
## allowed) a low-pressure practice card. `focus_lesson` narrows selection to that
## lesson's unlocked cards first — recall gates use this so their sessions drill
## the gated lesson, not whatever is least-recent across the whole pool. Falls
## back to the global pool when the focus lesson has nothing unlocked.
##
## Returns {} when there is nothing to review.
func build_prompt(card: Dictionary = {}, allow_practice: bool = false,
		focus_lesson: String = "", focus_category: String = "") -> Dictionary:
	var c := card
	var is_due := false

	if c.is_empty() and not focus_lesson.is_empty():
		var lesson: Dictionary = _content.lesson(focus_lesson)
		var pool: Array = []
		for id in lesson.get("cardIds", []):
			var lc: Dictionary = profile.card(id)
			if not lc.is_empty() and lc.get("unlocked", false) and recall_eligible(lc):
				pool.append(lc)
		var due_pool := Srs.due(pool)
		due_pool.shuffle()
		if not due_pool.is_empty():
			c = due_pool[0]
			is_due = true
		elif allow_practice:
			c = _least_recently_reviewed(pool)
			is_due = false

	if c.is_empty():
		c = next_due(focus_category)
		is_due = not c.is_empty()
		if c.is_empty() and allow_practice:
			c = next_practice(focus_category)

	if c.is_empty():
		return {}

	var distractors := _pick_distractors(c, 3)
	var choices: Array = [c.get("answer", "")]
	choices.append_array(distractors)
	choices.shuffle()
	return {
		"card": c,
		"question": c.get("prompt", ""),
		"choices": choices,
		"answer": c.get("answer", ""),
		"reading": c.get("reading", ""),
		"meaning": c.get("meaning", ""),
		"mode": "due" if is_due else "practice",
	}


func next_due(focus_category: String = "") -> Dictionary:
	var due_pool := Srs.due(_category_pool(focus_category))
	if due_pool.is_empty():
		return {}
	due_pool.shuffle()
	return due_pool[0]


func due_count() -> int:
	var eligible := profile.unlocked_cards().filter(
		func(c): return recall_eligible(c))
	return Srs.due(eligible).size()


## Least-recently reviewed unlocked card, for low-pressure practice when nothing
## is due. {} when the pool is empty.
func next_practice(focus_category: String = "") -> Dictionary:
	return _least_recently_reviewed(_category_pool(focus_category))


## Unlocked cards whose lesson's category equals or is prefixed by focus_category
## (e.g. "travel" matches "travel", "travel-arrival", ...). All unlocked cards
## when no filter is given.
func _category_pool(focus_category: String) -> Array:
	var cards := profile.unlocked_cards().filter(
		func(c): return recall_eligible(c))
	if focus_category.is_empty():
		return cards
	var matching := {}
	for lid in _content.lesson_order:
		var l: Dictionary = _content.lessons[lid]
		var cat := String(l.get("category", ""))
		if cat == focus_category or cat.begins_with(focus_category + "-"):
			for cid in l.get("cardIds", []):
				matching[cid] = true
	return cards.filter(func(c): return matching.has(c.get("id", "")))


## Record an answer. Updates SRS, stats, xp; saves. Returns whether it was correct.
func answer(card: Dictionary, chosen: String) -> bool:
	var correct := _normalize(chosen) == _normalize(String(card.get("answer", "")))
	grade(card, Srs.grade_from_correct(correct))
	return correct


func grade(card: Dictionary, grade_str: String) -> void:
	Srs.review(card, grade_str)
	var s: Dictionary = profile.data["stats"]
	s["totalReviews"] = int(s.get("totalReviews", 0)) + 1
	if grade_str != "again":
		s["totalCorrect"] = int(s.get("totalCorrect", 0)) + 1
		var gain := int(XP_BY_GRADE.get(grade_str, 6))
		s["xp"] = int(s.get("xp", 0)) + gain
		_announce_xp(gain, int(s["xp"]))
	# Auto-progression: if this card's lesson is now mastered, unlock the next one.
	_check_lesson_progression(String(card.get("lessonId", "")))
	profile.save()


func award_xp(amount: int) -> void:
	profile.data["stats"]["xp"] = int(profile.data["stats"].get("xp", 0)) + amount
	_announce_xp(amount, int(profile.data["stats"]["xp"]))
	profile.save()


func _announce_xp(amount: int, total: int) -> void:
	if amount != 0 and on_xp_changed.is_valid():
		on_xp_changed.call(amount, total)


## A lesson is mastered when every card is unlocked, answered correctly at least
## once, and each card's accuracy is >= 60% — slowing progression while the player
## struggles and letting a clean run move forward smoothly.
func _is_lesson_mastered(lesson: Dictionary) -> bool:
	for id in lesson.get("cardIds", []):
		var c: Dictionary = profile.card(id)
		if c.is_empty():
			return false
		if not recall_eligible(c):
			continue   # imported remark/page-number cards can never be reviewed
		if not c.get("unlocked", false) or int(c.get("correctCount", 0)) < 1:
			return false
		var reviews := int(c.get("correctCount", 0)) + int(c.get("incorrectCount", 0))
		if reviews == 0:
			return false
		if float(c.get("correctCount", 0)) / reviews < 0.6:
			return false
	return true


## If the current lesson is mastered, unlock the next lesson in the same category.
func _check_lesson_progression(lesson_id: String) -> void:
	var lesson: Dictionary = _content.lesson(lesson_id)
	if lesson.is_empty() or not _is_lesson_mastered(lesson):
		return

	# Lessons of this category, in authored order (matches Lessons.filter in TS).
	var category := String(lesson.get("category", ""))
	var category_lessons: Array = []
	for lid in _content.lesson_order:
		var l: Dictionary = _content.lessons[lid]
		if String(l.get("category", "")) == category:
			category_lessons.append(l)

	var idx := -1
	for i in category_lessons.size():
		if String(category_lessons[i].get("id", "")) == lesson_id:
			idx = i
			break
	if idx < 0 or idx >= category_lessons.size() - 1:
		return

	var next_lesson: Dictionary = category_lessons[idx + 1]
	var already_unlocked := true
	for id in next_lesson.get("cardIds", []):
		var c: Dictionary = profile.card(id)
		if c.is_empty() or not c.get("unlocked", false):
			already_unlocked = false
			break
	if not already_unlocked:
		profile.unlock_lesson(String(next_lesson.get("id", "")))
		if on_lesson_unlock.is_valid():
			on_lesson_unlock.call(String(next_lesson.get("title", "")))


## Up to n wrong-answer options for a card. Always includes the card's authored
## distractors, then widens the pool with other unlocked answers from the same
## lesson category (or same card type if the lesson is unknown) so the exact same
## four options don't recur every review.
func _pick_distractors(card: Dictionary, n: int) -> Array:
	var answer_norm := _normalize(String(card.get("answer", "")))
	var own: Array = []
	for choice in card.get("choices", []):
		if _normalize(String(choice)) != answer_norm and choice_plausible(String(choice)):
			own.append(choice)

	var lesson: Dictionary = _content.lesson(String(card.get("lessonId", "")))
	var category := String(lesson.get("category", ""))
	var card_id := String(card.get("id", ""))
	var card_type := String(card.get("type", ""))

	var fallback: Array = []
	for c in profile.all_cards():
		if String(c.get("id", "")) == card_id or not c.get("unlocked", false) \
				or not recall_eligible(c):
			continue
		var matches: bool
		if category.is_empty():
			matches = String(c.get("type", "")) == card_type
		else:
			var cl: Dictionary = _content.lesson(String(c.get("lessonId", "")))
			matches = String(cl.get("category", "")) == category
		if matches and _normalize(String(c.get("answer", ""))) != answer_norm:
			fallback.append(c.get("answer", ""))

	# de-dup, preserving own-first order, then shuffle and take n
	var seen := {}
	var merged: Array = []
	for a in own + fallback:
		var key := _normalize(String(a))
		if not seen.has(key):
			seen[key] = true
			merged.append(a)
	merged.shuffle()
	return merged.slice(0, n)


## Least-recently reviewed card. Shuffles first so ties (and never-reviewed cards,
## which all read as 0) don't always cycle in the same id order. {} if empty.
func _least_recently_reviewed(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	var shuffled := pool.duplicate()
	shuffled.shuffle()
	shuffled.sort_custom(func(a, b):
		var av: float = a.get("lastReviewedAt") if a.get("lastReviewedAt") != null else 0.0
		var bv: float = b.get("lastReviewedAt") if b.get("lastReviewedAt") != null else 0.0
		return av < bv)
	return shuffled[0]


## A card is reviewable only when its answer could actually sit on a rune button:
## non-empty, short, and not a bare number (page refs / stroke counts from import).
static func recall_eligible(card: Dictionary) -> bool:
	return choice_plausible(String(card.get("answer", "")))


static func choice_plausible(text: String) -> bool:
	var t := text.strip_edges()
	return not t.is_empty() and t.length() <= MAX_CHOICE_LENGTH and not t.is_valid_int()


static func _normalize(s: String) -> String:
	return s.strip_edges().to_lower()
