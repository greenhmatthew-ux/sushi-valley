extends SceneTree
## GUARD: every Japanese character shown to the player must come from an attributed source.
##
##   godot --headless --path . --script res://tests/test_japanese_sourcing.gd
##
## Why this test exists. LEARNING_PROGRESSION.md: "Learning content must come from the
## project's attributable flashcard sources. Do not invent an uncited parallel deck or
## hardcode lesson text in scenes, gates, dialogue, or UI components."
## SITE_WIDE_LEARNING_ARCHITECTURE.md: "Curated content only — no auto-generated Japanese."
##
## Those rules were broken: 19 invented Japanese strings had been authored into world.tscn
## and the NPC scripts — including a shopkeeper greeting with いただきます (which is said
## before eating, not as a greeting) and a literal translation of the English idiom
## "greetings open every door", which is not how the thought is expressed in Japanese.
## Being wrong in a language-teaching game is worse than being absent.
##
## A promise not to do it again is unenforceable, so this asserts it instead: scan every
## scene and script for kana/kanji and fail on anything that is not a prompt or reading in
## data/learning/cards.json. Entities take card IDs rather than Japanese strings, so the
## normal way to add Japanese now has nowhere to put an invention.

var failures: int = 0

## Japanese that is legitimately NOT curriculum. Keep this list tiny and justified.
const ALLOWED := {
	# Matched against OS voice names to find a Japanese TTS voice — see speech_logic.gd.
	"日本語": "TTS voice-name matching, never displayed",
}


func _initialize() -> void:
	await process_frame
	var db := root.get_node("DB")

	var sourced := {}
	for card in db.cards.values():
		for key in ["prompt", "reading"]:
			var v := String(card.get(key, "")).strip_edges()
			if not v.is_empty():
				sourced[v] = true
	print("  sourced Japanese strings available: %d" % sourced.size())

	var offenders := _scan(sourced)
	for o in offenders:
		print("  FAIL unsourced Japanese %s  in %s" % [o["text"], o["file"]])
		failures += 1
	if offenders.is_empty():
		print("  ok   every Japanese string in src/ traces to a sourced card")

	_finish()


## Walk src/ and collect Japanese string literals that aren't sourced or allow-listed.
## Comments are skipped: they document the code and are never shown to a player.
func _scan(sourced: Dictionary) -> Array:
	var offenders: Array = []
	for path in _files("res://src", [".gd", ".tscn"]):
		var text := FileAccess.get_file_as_string(path)
		for raw_line in text.split("\n"):
			var line := String(raw_line)
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue   # comment, not player-facing
			for literal in _string_literals(line):
				if not _has_japanese(literal):
					continue
				# Bilingual lines are "japanese|english"; only the Japanese half is content.
				var ja: String = String(literal.split("|")[0]).strip_edges()
				if sourced.has(ja) or ALLOWED.has(ja):
					continue
				offenders.append({"text": ja, "file": path.get_file()})
	return offenders


func _string_literals(line: String) -> Array:
	var out: Array = []
	var parts := line.split("\"")
	# odd indices sit between quote pairs
	for i in range(1, parts.size(), 2):
		out.append(String(parts[i]))
	return out


func _has_japanese(s: String) -> bool:
	for c in s:
		var cp := c.unicode_at(0)
		if (cp >= 0x3040 and cp <= 0x30FF) or (cp >= 0x4E00 and cp <= 0x9FFF):
			return true
	return false


func _files(dir_path: String, suffixes: Array) -> Array:
	var found: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			found.append_array(_files(full, suffixes))
		else:
			for suffix in suffixes:
				if name.ends_with(suffix):
					found.append(full)
					break
		name = dir.get_next()
	dir.list_dir_end()
	return found


func _finish() -> void:
	print("")
	print(("PASS — all player-facing Japanese is sourced and attributable."
		if failures == 0 else
		"FAIL — %d unsourced Japanese string(s). Use a card id from data/learning/cards.json instead of writing Japanese." % failures))
	quit(1 if failures > 0 else 0)
