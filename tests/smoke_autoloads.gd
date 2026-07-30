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
	check_true("DB autoload present", db != null)
	check_true("SaveGame autoload present", save != null)
	check_true("Learning autoload present", learning != null)

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
