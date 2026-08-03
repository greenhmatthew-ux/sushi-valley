extends SceneTree
## The Sushi Prep Raid state machine, pinned against RaidSystem.ts.
##
##   godot --headless --path . --script res://tests/test_raid.gd
##
## The raid is ported logic, so these checks assert the TS behavior: flag
## gating, resume-not-restart, the recall-cleared gate in front of rewards,
## exact reward/unlock/discovery effects granted exactly once, and the
## persisted save shape (field names and stage strings must stay byte-
## compatible with TS saves).

const RaidLogic = preload("res://src/systems/raid_logic.gd")
const CraftRules = preload("res://src/systems/crafting_logic.gd")

var failures: int = 0


func _initialize() -> void:
	# Autoload _ready (where DB loads its tables) runs after _initialize begins.
	await process_frame
	var db: Node = root.get_node("DB")
	var inv: Node = root.get_node("Inv")
	var raid: Dictionary = db.raid("sushi_prep")
	var profile := LearningProfile.new({}, db)

	check_true("sushi_prep raid def loads", not raid.is_empty())

	# --- gating -------------------------------------------------------------
	check_true("locked before Hana's first lesson", not RaidLogic.can_start(profile, raid))
	check_true("a locked raid does not start",
		RaidLogic.start(profile, raid).is_empty())
	check_true("recall cannot clear before the raid exists",
		not RaidLogic.mark_recall_cleared(profile, "sushi_prep"))
	profile.set_flag("hana_first_lesson")
	check_true("the first-lesson flag unlocks it", RaidLogic.can_start(profile, raid))

	# --- start and resume ---------------------------------------------------
	var prog := RaidLogic.start(profile, raid)
	check_eq("starting enters the active stage", prog.get("stage"), "active")
	check_eq("a fresh raid has no completions", int(prog.get("completions", -1)), 0)
	check_true("startedAt is a real timestamp", float(prog.get("startedAt", 0)) > 0.0)
	prog["startedAt"] = 111.0
	var resumed := RaidLogic.start(profile, raid)
	check_eq("starting again resumes, never restarts",
		float(resumed.get("startedAt", 0)), 111.0)

	# --- the recall gate in front of the boss -------------------------------
	check_eq("boss victory pays nothing while the recall is uncleared",
		RaidLogic.complete_boss(profile, db, inv, raid), "")
	check_true("recall clears once active",
		RaidLogic.mark_recall_cleared(profile, "sushi_prep"))
	check_eq("and moves the stage", RaidLogic.progress(profile, "sushi_prep").get("stage"),
		"recall-cleared")

	# --- completion: rewards, flags, discovery, exactly once ----------------
	var coins_before: int = inv.coins
	var summary: String = RaidLogic.complete_boss(profile, db, inv, raid)
	check_true("completion returns the TS summary line", not summary.is_empty())
	check_true("summary names the raid and the recipe",
		summary.contains("Sushi Prep Raid complete") and summary.contains("recipe:"))
	check_eq("80 coins paid", inv.coins - coins_before, 80)
	check_eq("one Recipe Stamp granted", inv.count("recipe_stamp"), 1)
	check_eq("two rice balls granted", inv.count("rice_ball"), 2)
	check_true("completion flag set", profile.get_flag("raid_sushi_prep_done"))
	check_true("expedition unlock flag set", profile.get_flag("expedition_forest_unlocked"))
	check_true("Hana's platter recipe is discovered",
		CraftRules.is_known(db.recipe("cook_hanas_raid_platter"), profile.data))

	var done := RaidLogic.progress(profile, "sushi_prep")
	check_eq("stage is complete", done.get("stage"), "complete")
	check_eq("one completion recorded", int(done.get("completions", 0)), 1)
	check_true("completedAt recorded", float(done.get("completedAt", 0)) > 0.0)

	check_eq("a second boss kill pays nothing",
		RaidLogic.complete_boss(profile, db, inv, raid), "")
	check_eq("coins unchanged after the second kill", inv.coins - coins_before, 80)
	check_true("a finished non-repeatable raid cannot restart",
		not RaidLogic.can_start(profile, raid))
	check_true("and start() hands back the completed record, not a new run",
		RaidLogic.start(profile, raid).get("stage") == "complete")

	# --- persisted shape (TS-save compatible) -------------------------------
	var saved: Dictionary = profile.to_save_dict()
	check_true("raids table persists in the save", saved.has("raids"))
	var entry: Dictionary = saved.get("raids", {}).get("sushi_prep", {})
	check_eq("persisted keys match the TS shape",
		entry.keys().filter(func(k): return k in ["stage", "startedAt", "completedAt", "completions"]).size(),
		entry.keys().size())
	var reloaded := LearningProfile.new(saved, db)
	check_true("a reloaded profile still refuses to restart the raid",
		not RaidLogic.can_start(reloaded, raid))

	_finish()


func _finish() -> void:
	print("")
	print(("PASS — the Sushi Prep Raid gates, pays, and persists like the TS build."
		if failures == 0 else "FAIL — %d raid check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
