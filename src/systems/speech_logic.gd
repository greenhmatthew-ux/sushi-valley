class_name SpeechLogic
extends RefCounted
## Pure logic for Japanese voice selection — split out from the Speech autoload so it stays
## headless-testable (see CLAUDE.md: pure logic lives in src/systems/ and must not touch
## nodes or the scene tree). Mirrors the Inv/InventoryLogic shape: the autoload owns
## DisplayServer calls and the one shared probe result; this class owns the actual scoring.
##
## Port of scoreVoice() in the TS build's Speech.ts.


## An actual Japanese-language voice wins outright; a name that merely mentions "Japanese"
## (some multi-lingual voices list it without their language tag saying so) is a much
## weaker signal; anything else scores 0. That 0 is the whole fix: it is what keeps
## Speech.speak() honestly silent instead of grabbing an English voice as a "close enough"
## fallback — which is what made the TS build's pronunciation sound like it was spelling
## words out.
static func score_voice(language: String, name: String) -> int:
	var lang := language.to_lower()
	var nm := name.to_lower()
	if lang.begins_with("ja"):
		return 100
	if nm.contains("japanese") or nm.contains("日本語"):
		return 50
	return 0


## Picks the id of the best-scoring voice from a DisplayServer.tts_get_voices()-shaped
## list ([{"id","name","language"}, ...]). Returns "" if nothing scores above 0, so the
## caller never falls back to a voice that has nothing to do with Japanese.
static func pick_best_voice(voices: Array) -> String:
	var best_score := 0
	var best_id := ""
	for v in voices:
		var score := score_voice(String(v.get("language", "")), String(v.get("name", "")))
		if score > best_score:
			best_score = score
			best_id = String(v.get("id", ""))
	return best_id
