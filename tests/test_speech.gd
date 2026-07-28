extends SceneTree
## Pins SpeechLogic — the pure half of pronunciation voice selection — so it stays headless-
## testable without touching DisplayServer. This is the exact bug fix from the TS build: a
## real Japanese-language voice must outscore everything else, and an unrelated voice must
## score 0, because 0 is what keeps Speech.speak() silent instead of guessing with a
## mismatched voice (see src/autoload/speech.gd for the full story).
##
##   godot --headless --path . --script res://tests/test_speech.gd

var failures: int = 0


func _initialize() -> void:
	_ja_language_wins()
	_name_hint_is_weaker_than_language()
	_unrelated_voice_scores_zero()
	_language_case_and_region_dont_matter()
	_pick_best_voice_picks_the_real_japanese_one()
	_pick_best_voice_returns_empty_with_no_japanese_voice()
	_finish()


func _ja_language_wins() -> void:
	check_eq("ja_JP language scores 100", SpeechLogic.score_voice("ja_JP", "Microsoft Haruka"), 100)
	check_eq("ja-JP (hyphen) language scores 100", SpeechLogic.score_voice("ja-JP", "Kyoko"), 100)


func _name_hint_is_weaker_than_language() -> void:
	check_eq("name-only 'Japanese' hint scores 50",
		SpeechLogic.score_voice("en_US", "Japanese Female"), 50)
	check_eq("name-only '日本語' hint scores 50",
		SpeechLogic.score_voice("", "日本語 Voice"), 50)


func _unrelated_voice_scores_zero() -> void:
	# This is the exact fallback the TS build's bug relied on — an English voice with no
	# Japanese hint at all must score 0, not "close enough".
	check_eq("plain English voice scores 0", SpeechLogic.score_voice("en_US", "Microsoft David"), 0)
	check_eq("empty language+name scores 0", SpeechLogic.score_voice("", ""), 0)


func _language_case_and_region_dont_matter() -> void:
	check_eq("uppercase JA_JP still scores 100", SpeechLogic.score_voice("JA_JP", "Ichiro"), 100)
	check_eq("bare 'ja' still scores 100", SpeechLogic.score_voice("ja", "Some Voice"), 100)


## Simulates picking the best of a mixed voice list — exactly what the Speech autoload's
## _probe_voice() does — to confirm a real Japanese voice always outranks an English voice,
## regardless of list order.
func _pick_best_voice_picks_the_real_japanese_one() -> void:
	var voices := [
		{"id": "david", "language": "en_US", "name": "Microsoft David"},
		{"id": "zira", "language": "en_US", "name": "Microsoft Zira"},
		{"id": "haruka", "language": "ja_JP", "name": "Microsoft Haruka"},
		{"id": "mark", "language": "en_US", "name": "Microsoft Mark"},
	]
	check_eq("mixed list picks the Japanese voice", SpeechLogic.pick_best_voice(voices), "haruka")


## No Japanese voice installed at all — this is the exact host state the TS build handled
## by silently mispronouncing. This port must return "" so Speech.speak() stays silent.
func _pick_best_voice_returns_empty_with_no_japanese_voice() -> void:
	var voices := [
		{"id": "david", "language": "en_US", "name": "Microsoft David"},
		{"id": "zira", "language": "en_US", "name": "Microsoft Zira"},
	]
	check_eq("no Japanese voice -> empty id", SpeechLogic.pick_best_voice(voices), "")


func _finish() -> void:
	print("")
	print(("PASS — Japanese voice scoring picks a real ja voice, never a fallback."
		if failures == 0 else "FAIL — %d speech check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s)" % [label, got], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
