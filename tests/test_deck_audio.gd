extends SceneTree
## GUARD: the native-speaker audio imported from the source decks stays playable.
##
##   godot --headless --path . --script res://tests/test_deck_audio.gd
##
## Every card was imported with `mediaPolicy: excluded`, so 852 of 1,330 cards were
## silent while their own deck carried a recording for them — including 91 of the
## 100 travel phrasebook cards. `tools/import_deck_audio.py` pulls each recording
## off the exact Anki note the card came from, matched by the `sourceNoteId` the
## import kept.
##
## This asserts the manifest still resolves to real, loadable files, because the
## audio is only useful if Godot can actually import and play it: a stale path or
## a missing .import file fails silently at runtime as "no audio for this card".

var failures: int = 0
var db: Node

const MANIFEST_PATH := "res://data/learning/deck-audio.json"


func _initialize() -> void:
	db = load("res://src/autoload/db.gd").new()
	db.load_all()

	_manifest_is_consistent()
	_clips_are_real_loadable_audio()
	_the_travel_phrasebook_speaks()
	_borrowed_clips_cannot_teach_the_wrong_sound()
	_the_kana_ladder_speaks()
	_audited_clips_still_win()

	db.free()
	_finish()


func _manifest_is_consistent() -> void:
	check_true("deck audio manifest exists", FileAccess.file_exists(MANIFEST_PATH))
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(MANIFEST_PATH))
	var clips: Dictionary = manifest.get("clips", {})
	var cards: Dictionary = manifest.get("cards", {})
	check_true("manifest maps a meaningful number of cards", cards.size() >= 1300)
	check_eq("db loaded every clip", db.deck_audio_clips.size(), clips.size())
	check_eq("db loaded every card mapping", db.deck_audio_cards.size(), cards.size())

	var dangling := 0
	var unknown_card := 0
	for card_id in cards:
		if not clips.has(String(cards[card_id])):
			dangling += 1
		if not db.cards.has(card_id):
			unknown_card += 1
	check_eq("every mapping points at a clip that exists", dangling, 0)
	check_eq("every mapping points at a card that exists", unknown_card, 0)

	# The deck's own recording is attributed, even though its licence is unstated.
	var source: Dictionary = manifest.get("source", {})
	check_true("deck audio records where it came from",
		not String(source.get("provider", "")).is_empty()
		and not String(source.get("license", "")).is_empty())


## A path in the manifest is worthless if Godot never imported the file: it would
## resolve to {} at runtime and the card would just be quietly silent again.
func _clips_are_real_loadable_audio() -> void:
	var missing: Array[String] = []
	var unimported: Array[String] = []
	for clip_id in db.deck_audio_clips:
		var path := String(db.deck_audio_clips[clip_id].get("path", ""))
		if not FileAccess.file_exists(path):
			missing.append(path)
		elif not ResourceLoader.exists(path, "AudioStream"):
			unimported.append(path)
	check_eq("every clip file is on disk", missing.size(), 0)
	check_eq("every clip is imported as an AudioStream", unimported.size(), 0)

	# Actually decode one, so a directory of corrupt bytes cannot pass.
	var first := String(db.deck_audio_clips[db.deck_audio_clips.keys()[0]].get("path", ""))
	var stream := ResourceLoader.load(first, "AudioStream") as AudioStream
	check_true("a clip loads and reports a real duration",
		stream != null and stream.get_length() > 0.0)


## The point of the whole exercise: the travel phrasebook used to be silent.
func _the_travel_phrasebook_speaks() -> void:
	var total := 0
	var voiced := 0
	for lid in db.lesson_order:
		var category := String(db.lessons[lid].get("category", ""))
		if not (category == "phrases" or category == "travel"
				or category.begins_with("travel-")):
			continue
		for cid in db.lessons[lid].get("cardIds", []):
			total += 1
			if not db.pronunciation_for_card(cid).is_empty():
				voiced += 1
	print("  ..   travel/phrase cards with audio: %d / %d" % [voiced, total])
	check_true("nearly every travel/phrase card can be heard (%d of %d)" % [voiced, total],
		total > 0 and float(voiced) / float(total) >= 0.95)


## The authored curriculum was never part of a deck, so it borrows the recording of
## an identically-written imported card. That is only sound when the written form
## determines the pronunciation: kana is phonetic, kanji is not (十分 is じゅうぶん
## or じゅっぷん). A borrowed clip on an ambiguous form would teach the wrong word
## with total confidence, so the rule is re-checked here rather than trusted.
func _borrowed_clips_cannot_teach_the_wrong_sound() -> void:
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(MANIFEST_PATH))
	var linked: Dictionary = manifest.get("linkedCards", {})
	check_true("the manifest records what borrowed from what", linked.size() > 0)

	var mismatched: Array[String] = []
	var different_word: Array[String] = []
	for card_id in linked:
		var card: Dictionary = db.card(card_id)
		var twin: Dictionary = db.card(String(linked[card_id]))
		var prompt := String(card.get("prompt", "")).strip_edges()
		if prompt != String(twin.get("prompt", "")).strip_edges():
			different_word.append(card_id)
		elif not _is_all_kana(prompt):
			# Non-phonetic form: the readings themselves have to agree.
			var mine := String(card.get("reading", "")).strip_edges().to_lower()
			var theirs := String(twin.get("reading", "")).strip_edges().to_lower()
			if mine.is_empty() or mine != theirs:
				mismatched.append(card_id)
	check_eq("a borrowed clip always comes from the same written word",
		different_word.size(), 0)
	check_eq("a kanji card never borrows across a different reading",
		mismatched.size(), 0)


## Kana is the first thing a new player studies, and every one of those cards was
## silent while the imported kana decks held a recording of the same character.
func _the_kana_ladder_speaks() -> void:
	var total := 0
	var voiced := 0
	for lid in db.lesson_order:
		if not String(db.lessons[lid].get("category", "")).begins_with("kana"):
			continue
		for cid in db.lessons[lid].get("cardIds", []):
			if not LearningProgression.recall_eligible(db.card(cid)):
				continue   # the all-junk duplicate kana deck is not curriculum
			total += 1
			if not db.pronunciation_for_card(cid).is_empty():
				voiced += 1
	print("  ..   reviewable kana cards with audio: %d / %d" % [voiced, total])
	check_true("the kana ladder can be heard (%d of %d)" % [voiced, total],
		total > 0 and voiced == total)


func _is_all_kana(text: String) -> bool:
	if text.is_empty():
		return false
	for ch in text:
		var cp := ch.unicode_at(0)
		if not ((cp >= 0x3040 and cp <= 0x30FF) or ch == "・" or ch == "ー"):
			return false
	return true


## Kanji alive is verified against both the written form and the reading, so it
## must keep winning where it has a clip; the deck audio is only the fallback.
func _audited_clips_still_win() -> void:
	var checked := 0
	var overridden := 0
	for card_id in db.pronunciation_cards:
		checked += 1
		var resolved: Dictionary = db.pronunciation_for_card(card_id)
		var clip_id := String(db.pronunciation_cards[card_id])
		var audited: Dictionary = db.pronunciation_clips.get(clip_id, {})
		if resolved != audited:
			overridden += 1
	check_true("there are audited clips to defend", checked > 0)
	check_eq("deck audio never overrides an audited clip", overridden, 0)


func _finish() -> void:
	print("")
	print(("PASS — imported deck audio resolves, loads, and voices the phrasebook."
		if failures == 0 else "FAIL — %d deck-audio check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
