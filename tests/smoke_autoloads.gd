extends SceneTree
## Boots the real project (autoloads installed) and confirms the learning stack
## wired up: DB loaded, Learning built a profile + progression against it, and
## SaveGame round-trips through user://.
##
##   godot --headless --path . --script res://tests/smoke_autoloads.gd
##
## Unlike the pure-logic tests, this one runs WITH autoloads, so it catches wiring
## bugs the --script tests can't: a wrong autoload order, a bad DB reference in
## Learning, or a saver that isn't hooked to SaveGame.

const PROFILE_PATH := "user://profile.json"

var failures: int = 0
var _backup_text: String = ""
var _had_backup: bool = false


func _initialize() -> void:
	_stash_real_save()
	# Autoloads are children of root once the SceneTree main loop starts.
	await process_frame

	var db := root.get_node_or_null("DB")
	var save := root.get_node_or_null("SaveGame")
	var learning := root.get_node_or_null("Learning")
	var audio := root.get_node_or_null("Audio")
	check_true("DB autoload present", db != null)
	check_true("SaveGame autoload present", save != null)
	check_true("Learning autoload present", learning != null)
	check_true("Audio autoload present", audio != null)
	if audio != null:
		check_true("Audio exposes has_pronunciation",
			audio.has_method("has_pronunciation"))
		check_true("Audio exposes play_pronunciation",
			audio.has_method("play_pronunciation"))
		check_true("Audio exposes stop_pronunciation",
			audio.has_method("stop_pronunciation"))
		if audio.has_method("has_pronunciation"):
			check_true("Audio reports a known pronunciation",
				audio.has_pronunciation(
					"core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-2"))
			# Kana is voiced now that the imported kana decks supply a recording of
			# the same character; it was only ever silent because the licensed
			# word-level source has no entry for a bare あ.
			check_true("Audio reports kana as playable",
				audio.has_pronunciation("kana-a"))
			check_true("Audio reports a card with no recording anywhere as silent",
				not audio.has_pronunciation("no-such-card-id"))

	if learning == null:
		_restore_real_save(save)
		_finish()
		return

	check_true("Learning built a profile", learning.profile != null)
	check_true("Learning built a progression", learning.progression != null)
	check_true("profile hydrated from DB",
		learning.profile.all_cards().size() == db.cards.size())
	check_true("profile saver is wired to SaveGame", learning.profile.saver.is_valid())

	# End-to-end persistence through the real autoloads.
	save.clear()
	# Clearing the file does not clear the profile already in memory, and the exact
	# XP total below only means anything from a known start. This used to pass only
	# because whichever suite ran before happened to leave XP at zero.
	learning.profile.data["stats"]["xp"] = 0
	learning.profile.unlock_lesson("kana-vowels")
	learning.set_flag("autoload_smoke_flag")
	learning.progression.answer(learning.profile.card("kana-a"), "a")
	learning.profile.save()
	check_true("SaveGame wrote a file", save.has_save())

	# Reload from disk and confirm state survived.
	learning.reload()
	check_true("flag survived a reload", learning.get_flag("autoload_smoke_flag"))
	check_true("unlock survived a reload",
		learning.profile.card("kana-a").get("unlocked", false))
	check_true("xp survived a reload", learning.profile.data["stats"]["xp"] == 10)

	save.clear()
	_restore_real_save(save)
	_finish()


func _stash_real_save() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		_backup_text = FileAccess.get_file_as_string(PROFILE_PATH)
		_had_backup = true


func _restore_real_save(save: Node) -> void:
	if _had_backup:
		var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_backup_text)
			f.close()
	elif save != null:
		save.clear()


func _finish() -> void:
	print("")
	print(("PASS — autoloads boot and the learning stack persists."
		if failures == 0 else "FAIL — %d autoload check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
