extends SceneTree
## GUARD: the travel and phrase decks stay playable after an import.
##
##   godot --headless --path . --script res://tests/test_card_content.gd
##
## The Travel Japanese (Nihongo Fun & Easy) export glued each card's romaji onto
## the end of its Japanese prompt ("はいhai", "英語は話せますか。Eigo wa hanasemasu ka.")
## and left `reading` unset on all 100 cards. That is not cosmetic: the prompt
## renders as broken Japanese, and `recall_panel`'s hint scaffolding — reading
## after two misses, reading + meaning after three — had nothing to show for the
## entire travel phrasebook, so the player who was struggling got no help at all.
##
## `tools/normalize_travel_deck.py` splits those fields back apart and moves the
## deck's glued usage notes to `note`. This asserts the result, because the fix
## lives in imported data that a future re-import would silently undo.

var failures: int = 0
var db: Node

## The deck this suite guards, by its `source.deckId`.
const TRAVEL_DECK := "travel-japanese-w-audio-nihongo-fun-easy-2nd-edition"


func _initialize() -> void:
	db = load("res://src/autoload/db.gd").new()
	db.load_all()

	_travel_deck_is_split()
	_usage_notes_are_kept_not_deleted()
	_every_travel_phrase_card_can_hint()
	_no_travel_phrase_card_is_unreachable()
	_no_travel_phrase_lesson_is_hollowed_out()

	db.free()
	_finish()


func _deck_cards() -> Array:
	var out: Array = []
	for card in db.cards.values():
		if String(card.get("source", {}).get("deckId", "")) == TRAVEL_DECK:
			out.append(card)
	return out


func _travel_deck_is_split() -> void:
	var cards := _deck_cards()
	check_eq("the travel phrasebook is fully imported", cards.size(), 100)

	var missing_reading := 0
	var glued := 0
	var trailing_romaji := 0
	var unusable := 0
	var leftover_separator := 0
	for card in cards:
		var prompt := String(card.get("prompt", ""))
		var reading := String(card.get("reading", ""))
		if reading.strip_edges().is_empty():
			missing_reading += 1
		# The defect itself: the romaji sitting inside the Japanese prompt.
		elif prompt.to_lower().contains(reading.to_lower()):
			glued += 1
		if not prompt.is_empty() and _is_latin_letter(prompt[prompt.length() - 1]):
			trailing_romaji += 1
		if not LearningProgression.recall_eligible(card):
			unusable += 1
		for field in ["prompt", "reading", "answer", "meaning"]:
			if String(card.get(field, "")).contains("*"):
				leftover_separator += 1
				break

	check_eq("every travel card carries its romaji reading", missing_reading, 0)
	check_eq("no prompt still has the reading glued into it", glued, 0)
	check_eq("no Japanese prompt trails off into romaji", trailing_romaji, 0)
	check_eq("every travel card can sit on a rune button", unusable, 0)
	check_eq("no field still carries the deck's note separator", leftover_separator, 0)


## Trimming an answer must not throw the deck's explanation away — it moves to
## `note`, which the recall reveal shows once the answer is on screen.
func _usage_notes_are_kept_not_deleted() -> void:
	var noted: Array = []
	for card in _deck_cards():
		if not String(card.get("note", "")).strip_edges().is_empty():
			noted.append(card)
	check_true("the deck's usage notes survived normalization", noted.size() >= 4)
	var short_answers := true
	for card in noted:
		if not LearningProgression.recall_eligible(card):
			short_answers = false
	check_true("a card with a note still has a usable answer", short_answers)


## The hint scaffolding is only as good as the readings behind it, so this covers
## everything the player studies in this area, not just the deck fixed above.
func _every_travel_phrase_card_can_hint() -> void:
	var missing := 0
	for cid in _travel_phrase_card_ids():
		if String(db.card(cid).get("reading", "")).strip_edges().is_empty():
			missing += 1
	check_eq("every travel/phrase card can show a reading hint", missing, 0)


## An answer too long for a rune button is dropped from prompts, distractors, due
## counts, and mastery alike — unreachable content rather than a visible failure.
## 13 phrase cards were stuck that way behind glued-on explanations.
func _no_travel_phrase_card_is_unreachable() -> void:
	var unreachable: Array[String] = []
	for cid in _travel_phrase_card_ids():
		if not LearningProgression.recall_eligible(db.card(cid)):
			unreachable.append(cid)
	check_true("no travel/phrase card is too long to ever be asked (%s)" % str(unreachable),
		unreachable.is_empty())


## Ineligible imported cards are skipped everywhere, so a lesson made mostly of
## them would look full and play empty. Two usable cards is the floor at which a
## lesson can still pose a question with a real distractor.
func _no_travel_phrase_lesson_is_hollowed_out() -> void:
	var thin: Array[String] = []
	for lid in db.lesson_order:
		var lesson: Dictionary = db.lessons[lid]
		if not _is_travel_or_phrases(String(lesson.get("category", ""))):
			continue
		var usable := 0
		for cid in lesson.get("cardIds", []):
			if LearningProgression.recall_eligible(db.card(cid)):
				usable += 1
		if usable < 2:
			thin.append(lid)
	check_true("no travel/phrase lesson is left without usable cards (%s)" % str(thin),
		thin.is_empty())


func _travel_phrase_card_ids() -> Array:
	var ids: Array = []
	for lid in db.lesson_order:
		var lesson: Dictionary = db.lessons[lid]
		if _is_travel_or_phrases(String(lesson.get("category", ""))):
			ids.append_array(lesson.get("cardIds", []))
	return ids


func _is_travel_or_phrases(category: String) -> bool:
	return category == "phrases" or category == "travel" or category.begins_with("travel-")


func _is_latin_letter(ch: String) -> bool:
	var cp := ch.unicode_at(0)
	return (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)


func _finish() -> void:
	print("")
	print(("PASS — travel and phrase cards are split, sourced, and playable."
		if failures == 0 else "FAIL — %d card-content check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
