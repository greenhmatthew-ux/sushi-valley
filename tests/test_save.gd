extends SceneTree
## Persistence slice: SaveGame versioned full-snapshot save/load.
##
##   godot --headless --path . --script res://tests/test_save.gd
##
## Pure-logic test in the test_learning.gd style: it hand-instantiates DB,
## LearningProfile/Progression, and a bare SaveGame.new() (not the autoload), so
## nothing leans on add_child()/_ready(). It proves a reviewed card's SRS schedule
## and the player's position+facing survive a save -> load round-trip, that the
## snapshot carries version == SAVE_SCHEMA_VERSION, that a mid-session learning
## save does not clobber the world section, and that a legacy flat profile migrates
## into the wrapped shape.
##
## The real user://profile.json (if any) is stashed before and restored after, so
## running this test never eats a real playthrough's save.

const PROFILE_PATH := "user://profile.json"

var failures: int = 0
var db: Node
var save: Node
var _backup_text: String = ""
var _had_backup: bool = false


func _initialize() -> void:
	db = load("res://src/autoload/db.gd").new()
	db.load_all()
	save = load("res://src/autoload/save_game.gd").new()
	_stash_real_save()

	_snapshot_shape_and_version()
	_in_memory_round_trip()
	_disk_round_trip_and_world_preservation()
	_legacy_migration()

	_restore_real_save()
	save.free()
	db.free()
	_finish()


# --- tests -----------------------------------------------------------------

func _snapshot_shape_and_version() -> void:
	var p := _seed()
	var snap: Dictionary = save.build_snapshot(p.to_save_dict(), Vector2(304, 384), "left")

	check_eq("snapshot carries the schema version", snap["version"], save.SAVE_SCHEMA_VERSION)
	check_true("snapshot has a learning section", snap.has("learning"))
	check_true("snapshot has a world.player section", (snap["world"] as Dictionary).has("player"))
	check_eq("snapshot stores player x", float(snap["world"]["player"]["x"]), 304.0)
	check_eq("snapshot stores player y", float(snap["world"]["player"]["y"]), 384.0)
	check_eq("snapshot stores player facing", String(snap["world"]["player"]["facing"]), "left")


func _in_memory_round_trip() -> void:
	var p := _seed()
	var due_before: float = p.card("kana-a")["dueAt"]
	var correct_before: int = p.card("kana-a")["correctCount"]
	check_true("seeded card rescheduled into the future", not Srs.is_due(p.card("kana-a")))

	var snap: Dictionary = save.build_snapshot(p.to_save_dict(), Vector2(304, 384), "up")
	var restored: Dictionary = save.apply_snapshot(snap)

	# world round-trips
	check_true("apply reports a stored player", restored["has_player"])
	check_true("player position round-trips", restored["position"] == Vector2(304, 384))
	check_eq("player facing round-trips", String(restored["facing"]), "up")

	# learning round-trips: rebuild a profile from the restored learning dict
	var reloaded := LearningProfile.new(restored["learning"], db)
	check_eq("reviewed card keeps its due schedule", reloaded.card("kana-a")["dueAt"], due_before)
	check_eq("reviewed card keeps its correctCount", reloaded.card("kana-a")["correctCount"], correct_before)
	check_true("reviewed card stays unlocked", reloaded.card("kana-a")["unlocked"])
	check_true("reviewed card is still not due after a restart", not Srs.is_due(reloaded.card("kana-a")))
	check_true("flag survives", reloaded.get_flag("saw_the_gate"))
	check_eq("xp survives", int(reloaded.data["stats"]["xp"]), 10)


func _disk_round_trip_and_world_preservation() -> void:
	save.clear()
	var p := _seed()
	var due_before: float = p.card("kana-a")["dueAt"]

	save.save_snapshot(p.to_save_dict(), Vector2(120, 250), "right")
	check_true("save file was written", save.has_save())

	# raw file carries the wrapped shape
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	check_eq("on-disk version is stamped", int(raw["version"]), save.SAVE_SCHEMA_VERSION)
	check_true("on-disk doc has a learning section", raw.has("learning"))
	check_true("on-disk doc has world.player", (raw["world"] as Dictionary).has("player"))
	check_true("on-disk learning stays slim (no static prompt)",
		not (raw["learning"]["cards"]["kana-a"] as Dictionary).has("prompt"))

	# load_profile returns ONLY the learning section, ready for LearningProfile
	var loaded_learning: Dictionary = save.load_profile()
	check_true("load_profile unwraps the learning section (has cards)", loaded_learning.has("cards"))
	check_true("load_profile does not leak the wrapper (no world key)", not loaded_learning.has("world"))
	var reloaded := LearningProfile.new(loaded_learning, db)
	# JSON re-parses the epoch-ms float; allow sub-ms drift but require the schedule held.
	check_true("disk round-trip keeps the due schedule",
		absf(float(reloaded.card("kana-a")["dueAt"]) - due_before) < 1.0)
	check_eq("disk round-trip keeps correctCount", int(reloaded.card("kana-a")["correctCount"]), 1)
	check_true("disk-reloaded card is still not due", not Srs.is_due(reloaded.card("kana-a")))

	# apply_snapshot straight from disk restores the placement
	var placement: Dictionary = save.apply_snapshot(save.load_snapshot())
	check_true("disk placement present", placement["has_player"])
	check_true("disk player position round-trips", placement["position"] == Vector2(120, 250))
	check_eq("disk player facing round-trips", String(placement["facing"]), "right")

	# a mid-session learning save (save_profile) must PRESERVE the world section
	reloaded.set_flag("mid_session")
	save.save_profile(reloaded.to_save_dict())
	var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	check_true("save_profile preserves the world section", (after["world"] as Dictionary).has("player"))
	check_eq("save_profile preserves player x", float(after["world"]["player"]["x"]), 120.0)
	check_true("save_profile updated learning (flag persisted)", after["learning"]["flags"]["mid_session"])
	save.clear()


func _legacy_migration() -> void:
	save.clear()

	# Simulate a pre-wrap flat profile: the learning dict written at the top level,
	# with no "learning"/"world"/wrapper keys.
	var legacy_p := _seed()
	var flat := legacy_p.to_save_dict()
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(flat))
	f.close()

	# load_profile treats a doc with no "learning" key as the learning data itself.
	var loaded: Dictionary = save.load_profile()
	check_true("legacy flat profile loads as learning (has cards)", loaded.has("cards"))
	check_true("legacy card scheduling survives the migration read", loaded["cards"].has("kana-a"))
	var reloaded := LearningProfile.new(loaded, db)
	check_true("legacy flag survives migration", reloaded.get_flag("saw_the_gate"))

	# apply_snapshot on a legacy doc: learning falls through, no player placement.
	var placement: Dictionary = save.apply_snapshot(save.load_snapshot())
	check_true("legacy doc still exposes learning", not (placement["learning"] as Dictionary).is_empty())
	check_true("legacy doc reports no stored player", not placement["has_player"])

	# The first save upgrades the flat file to the wrapped shape.
	save.save_profile(reloaded.to_save_dict())
	var upgraded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	check_true("save upgrades a legacy file to the wrapped shape", upgraded.has("learning"))
	check_eq("upgraded file is stamped with the schema version",
		int(upgraded["version"]), save.SAVE_SCHEMA_VERSION)
	check_true("upgraded file has a world section", upgraded.has("world"))
	save.clear()


# --- helpers ---------------------------------------------------------------

## A profile with kana-vowels unlocked, kana-a reviewed once (good), and a flag set.
func _seed() -> LearningProfile:
	var p := LearningProfile.new({}, db)
	p.unlock_lesson("kana-vowels")
	var prog := LearningProgression.new(p, db)
	prog.answer(p.card("kana-a"), "a")   # correct -> "good": reschedules ~10min out, correctCount 1
	p.set_flag("saw_the_gate")
	return p


func _stash_real_save() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		_backup_text = FileAccess.get_file_as_string(PROFILE_PATH)
		_had_backup = true


func _restore_real_save() -> void:
	if _had_backup:
		var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_backup_text)
			f.close()
	else:
		save.clear()


func _finish() -> void:
	print("")
	print(("PASS — versioned snapshot save/load holds for learning + player position."
		if failures == 0 else "FAIL — %d save check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
