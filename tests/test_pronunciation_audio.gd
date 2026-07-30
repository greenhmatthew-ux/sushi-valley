extends SceneTree
## Licensed Japanese pronunciation manifest guard.
##
##   godot --headless --path . --script res://tests/test_pronunciation_audio.gd
##
## This test deliberately inspects the shipped bytes rather than playing them.
## Playback devices are unreliable in headless CI, while the manifest, Ogg header,
## checksum, card mapping, and DB lookup are all deterministic.

const MANIFEST_PATH := "res://data/learning/pronunciation-audio.json"
const APPROVED_AUDIO_DIR := "res://assets/audio/japanese/kanji_alive/"
const EXPECTED_VERSION := 1
const EXPECTED_CLIP_COUNT := 366
const EXPECTED_CARD_COUNT := 459
const EXPECTED_PROVIDER := "Kanji alive"
const EXPECTED_REVISION := "2d2a4931eec6e0cb532d5102766273c2323f96db"
const EXPECTED_LICENSE := "CC BY 4.0"

## Exact surface-and-reading matches. These also cover furigana notation.
const KNOWN_MATCHED := {
	"core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-2": "\u4e00\u3064",
	"core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-38": "\u5206\u304b\u308b",
	"core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-96": "\u5148\u751f",
}

## Same-looking text is not enough when the intended reading differs. The importer
## must leave these unmapped rather than teaching the wrong pronunciation.
const KNOWN_UNMATCHED := {
	"core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-142": "\u5341\u5206",
	"core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-148": "\u4f55",
	"kaishi-15k-basic-japanese-vocabulary-8": "\u4eba",
	"japanese-common-words-and-phrases-with-audio-kanji-romaji-62": "\u5927\u304d\u3044",
	# Kanji Alive's newer catalog has an example without a corresponding archive
	# clip at this revision, so it is intentionally excluded too.
	"japanese-common-words-and-phrases-with-audio-kanji-romaji-192": "\u79cb",
}

var failures: int = 0
var _db: Node


func _initialize() -> void:
	_db = load("res://src/autoload/db.gd").new()
	_db.load_all()

	var manifest: Dictionary = _read_manifest()
	if manifest.is_empty():
		_finish()
		return

	_validate_topology(manifest)
	_validate_clips(manifest.get("clips", {}))
	_validate_card_mappings(
		manifest.get("cards", {}),
		manifest.get("clips", {}),
	)
	_validate_spot_checks(manifest.get("cards", {}))
	_validate_db_contract()

	_db.free()
	_finish()


func _read_manifest() -> Dictionary:
	check_true("pronunciation manifest exists", FileAccess.file_exists(MANIFEST_PATH))
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	check_true("pronunciation manifest is valid JSON object", parsed is Dictionary)
	return parsed if parsed is Dictionary else {}


func _validate_topology(manifest: Dictionary) -> void:
	check_eq("manifest version", int(manifest.get("version", -1)), EXPECTED_VERSION)
	check_true("manifest has source object", manifest.get("source") is Dictionary)
	check_true("manifest has stats object", manifest.get("stats") is Dictionary)
	check_true("manifest has clips object", manifest.get("clips") is Dictionary)
	check_true("manifest has cards object", manifest.get("cards") is Dictionary)

	var source: Dictionary = manifest.get("source", {})
	check_eq("source provider", String(source.get("provider", "")), EXPECTED_PROVIDER)
	check_eq("source revision", String(source.get("revision", "")), EXPECTED_REVISION)
	check_eq("source license", String(source.get("license", "")), EXPECTED_LICENSE)
	check_true("source attribution is explicit",
		not String(source.get("attribution", "")).strip_edges().is_empty())

	var clips: Dictionary = manifest.get("clips", {})
	var cards: Dictionary = manifest.get("cards", {})
	check_eq("unique licensed clips", clips.size(), EXPECTED_CLIP_COUNT)
	check_eq("mapped cards", cards.size(), EXPECTED_CARD_COUNT)

	# Stats are a human-readable summary, but they must not drift from the payload.
	var stats: Dictionary = manifest.get("stats", {})
	check_eq("stats uniqueClips", int(stats.get("uniqueClips", -1)), clips.size())
	check_eq("stats cardsMapped", int(stats.get("cardsMapped", -1)), cards.size())


func _validate_clips(clips: Dictionary) -> void:
	var failures_before := failures
	var seen_paths: Dictionary = {}
	for raw_clip_id: Variant in clips:
		var clip_id := String(raw_clip_id)
		var raw_clip: Variant = clips[raw_clip_id]
		_require("clip %s is an object" % clip_id, raw_clip is Dictionary)
		if raw_clip is not Dictionary:
			continue
		var clip: Dictionary = raw_clip
		var path := String(clip.get("path", ""))
		var prompt := String(clip.get("prompt", "")).strip_edges()
		var reading := String(clip.get("reading", "")).strip_edges()
		var source_file := String(clip.get("sourceFile", "")).strip_edges()
		var expected_hash := String(clip.get("sha256", "")).to_lower()

		_require("clip id is non-empty", not clip_id.is_empty())
		_require("%s has a prompt" % clip_id, not prompt.is_empty())
		_require("%s has a reading" % clip_id, not reading.is_empty())
		_require("%s identifies its source file" % clip_id, not source_file.is_empty())
		_require("%s has a SHA-256 digest" % clip_id,
			expected_hash.length() == 64 and expected_hash.is_valid_hex_number())
		_require("%s stays in the approved audio folder" % clip_id,
			path.begins_with(APPROVED_AUDIO_DIR)
			and not path.contains("..")
			and path.simplify_path() == path)
		_require("%s path is unique" % clip_id, not seen_paths.has(path))
		seen_paths[path] = clip_id

		_require("%s OGG exists" % clip_id, FileAccess.file_exists(path))
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		_require("%s OGG opens" % clip_id, file != null)
		if file != null:
			_require_eq("%s has OggS header" % clip_id,
				file.get_buffer(4).get_string_from_ascii(), "OggS")
			file.close()
		_require_eq("%s SHA-256 matches" % clip_id,
			FileAccess.get_sha256(path).to_lower(), expected_hash)
	check_true("all %d clip files and checksums are valid" % clips.size(),
		failures == failures_before)


func _validate_card_mappings(cards: Dictionary, clips: Dictionary) -> void:
	var failures_before := failures
	var seen_card_mappings: Dictionary = {}
	var safely_compared_readings := 0
	var romaji_or_ambiguous_readings := 0
	for raw_card_id: Variant in cards:
		var card_id := String(raw_card_id)
		var clip_id := String(cards[raw_card_id])
		_require("mapped card id is non-empty", not card_id.is_empty())
		_require("%s maps to one non-empty clip id" % card_id, not clip_id.is_empty())
		_require("%s has no conflicting duplicate mapping" % card_id,
			not seen_card_mappings.has(card_id)
			or seen_card_mappings[card_id] == clip_id)
		seen_card_mappings[card_id] = clip_id
		_require("%s exists in current card data" % card_id, _db.cards.has(card_id))
		_require("%s resolves to clip %s" % [card_id, clip_id], clips.has(clip_id))
		if not _db.cards.has(card_id) or not clips.has(clip_id):
			continue

		var card: Dictionary = _db.cards[card_id]
		var clip: Dictionary = clips[clip_id]
		_require_eq("%s audio prompt matches current card" % card_id,
			String(clip.get("prompt", "")), String(card.get("prompt", "")))

		var card_readings := _reading_variants(String(card.get("reading", "")))
		var clip_reading := _normalise_reading(String(clip.get("reading", "")))
		if _are_comparable_kana(card_readings) and _is_comparable_kana(clip_reading):
			safely_compared_readings += 1
			_require("%s audio reading matches current card" % card_id,
				card_readings.has(clip_reading))
		else:
			# Romanisation and unresolved kanji are not guessed here. Exact prompt
			# matching plus the source-file record preserves the importer's trusted
			# validation without introducing a second transliteration algorithm.
			romaji_or_ambiguous_readings += 1

	check_true("at least one Japanese/furigana reading was cross-checked",
		safely_compared_readings > 0)
	check_true("romaji or ambiguous readings are explicitly accounted for",
		safely_compared_readings + romaji_or_ambiguous_readings == cards.size())
	check_true("all %d card-to-clip mappings are valid" % cards.size(),
		failures == failures_before)


func _validate_spot_checks(cards: Dictionary) -> void:
	for card_id: String in KNOWN_MATCHED:
		check_true("known match exists: %s" % card_id, _db.cards.has(card_id))
		if _db.cards.has(card_id):
			check_eq("known match prompt: %s" % card_id,
				String(_db.cards[card_id].get("prompt", "")),
				String(KNOWN_MATCHED[card_id]))
		check_true("known match has pronunciation: %s" % card_id, cards.has(card_id))

	# Cards with the same spoken Japanese should share one deduplicated clip.
	var wakaru_core := "core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-38"
	var wakaru_kaishi := "kaishi-15k-basic-japanese-vocabulary-69"
	var wakaru_common := "japanese-common-words-and-phrases-with-audio-kanji-romaji-107"
	check_true("all three sourced wakaru cards are mapped",
		cards.has(wakaru_core) and cards.has(wakaru_kaishi) and cards.has(wakaru_common))
	if cards.has(wakaru_core) and cards.has(wakaru_kaishi) and cards.has(wakaru_common):
		check_true("duplicate wakaru cards reuse one clip",
			cards[wakaru_core] == cards[wakaru_kaishi]
			and cards[wakaru_core] == cards[wakaru_common])

	for card_id: String in KNOWN_UNMATCHED:
		check_true("known intentional miss exists: %s" % card_id, _db.cards.has(card_id))
		if _db.cards.has(card_id):
			check_eq("known intentional miss prompt: %s" % card_id,
				String(_db.cards[card_id].get("prompt", "")),
				String(KNOWN_UNMATCHED[card_id]))
		check_true("known intentional miss has no pronunciation: %s" % card_id,
			not cards.has(card_id))

	# Kana is outside this word-level source and must not claim coverage.
	check_true("authored kana card remains intentionally silent", not cards.has("kana-a"))


func _validate_db_contract() -> void:
	check_eq("DB exposes pronunciation source",
		String(_db.pronunciation_source.get("provider", "")), EXPECTED_PROVIDER)
	check_eq("DB exposes pronunciation clips",
		_db.pronunciation_clips.size(), EXPECTED_CLIP_COUNT)
	check_eq("DB exposes pronunciation card mappings",
		_db.pronunciation_cards.size(), EXPECTED_CARD_COUNT)

	var matched_id := "core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-2"
	var pronunciation: Dictionary = _db.pronunciation_for_card(matched_id)
	check_true("DB lookup resolves a known card", not pronunciation.is_empty())
	check_eq("DB lookup returns the current prompt",
		String(pronunciation.get("prompt", "")), String(KNOWN_MATCHED[matched_id]))
	check_true("DB lookup returns an approved path",
		String(pronunciation.get("path", "")).begins_with(APPROVED_AUDIO_DIR))
	check_true("DB lookup leaves intentional mismatch empty",
		_db.pronunciation_for_card(
			"core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-142"
		).is_empty())


func _normalise_reading(raw: String) -> String:
	var value := raw.strip_edges()
	# Imported furigana uses forms such as 一[ひと]つ and 先生[せんせい].
	var furigana := RegEx.new()
	furigana.compile("[\u3400-\u9fff\u3005]+\\[([^\\]]+)\\]")
	value = furigana.sub(value, "$1", true)
	value = value.replace(" ", "").replace("\u3000", "")
	value = value.replace("\u3001", "\u30fb").replace("/", "\u30fb")
	value = value.replace(",", "\u30fb").replace("-", "")

	# Kanji Alive occasionally uses katakana in readings. Compare it as hiragana.
	var normalised := ""
	for character: String in value:
		var codepoint := character.unicode_at(0)
		if codepoint >= 0x30A1 and codepoint <= 0x30F6:
			normalised += String.chr(codepoint - 0x60)
		else:
			normalised += character
	return normalised


func _reading_variants(raw: String) -> Array[String]:
	var variants: Array[String] = []
	for part: String in _normalise_reading(raw).split("\u30fb", false):
		if not part.is_empty():
			variants.append(part)
	return variants


func _are_comparable_kana(values: Array[String]) -> bool:
	if values.is_empty():
		return false
	for value: String in values:
		if not _is_comparable_kana(value):
			return false
	return true


func _is_comparable_kana(value: String) -> bool:
	if value.is_empty():
		return false
	for character: String in value:
		var codepoint := character.unicode_at(0)
		if (codepoint >= 0x3041 and codepoint <= 0x3096) or codepoint == 0x30FC:
			continue
		return false
	return true


func _finish() -> void:
	print("")
	print(("PASS - sourced pronunciation bytes, mappings, and DB contract are valid."
		if failures == 0 else
		"FAIL - %d pronunciation audio check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


## Per-record checks only print failures; otherwise 825 valid assets/mappings
## would bury the suite result in thousands of lines.
func _require(label: String, ok: bool) -> void:
	if not ok:
		print("  FAIL " + label)
		failures += 1


func _require_eq(label: String, got: Variant, want: Variant) -> void:
	if got != want:
		print("  FAIL %s (got %s, want %s)" % [label, got, want])
		failures += 1


func check_eq(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("  ok   " if ok else "  FAIL ") + label
		+ ("" if ok else " (got %s, want %s)" % [got, want]))
	if not ok:
		failures += 1
