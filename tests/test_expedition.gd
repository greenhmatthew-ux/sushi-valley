extends SceneTree
## The Lost Lunchbox Expedition state machine, pinned against ExpeditionSystem.ts.
##
##   godot --headless --path . --script res://tests/test_expedition.gd
##
## Five saved stages with a strict order, gated behind the completed Sushi Prep
## Raid. These checks assert the TS behavior: the unlock contract (flags AND
## raid completion), no stage skipping in either direction, retreat-and-resume,
## rewards granted exactly once, and a repeatable rerun that keeps its count.

const RaidLogic = preload("res://src/systems/raid_logic.gd")
const ExpeditionLogic = preload("res://src/systems/expedition_logic.gd")
const CraftRules = preload("res://src/systems/crafting_logic.gd")

var failures: int = 0


func _initialize() -> void:
	await process_frame
	var db: Node = root.get_node("DB")
	var inv: Node = root.get_node("Inv")
	var exp: Dictionary = db.expedition("forest_lunchbox")
	var raid: Dictionary = db.raid("sushi_prep")
	var profile := LearningProfile.new({}, db)

	check_true("forest_lunchbox expedition def loads", not exp.is_empty())
	check_eq("it ships as playable", exp.get("status"), "playable")

	# --- unlock contract: flag AND completed raid, not either alone ---------
	check_true("locked at the start", not ExpeditionLogic.can_enter(profile, exp))
	profile.set_flag("expedition_forest_unlocked")
	check_true("the flag alone is not enough — the raid must be COMPLETE",
		not ExpeditionLogic.can_enter(profile, exp))
	check_true("a locked expedition does not start",
		ExpeditionLogic.start(profile, exp).is_empty())

	# Complete the raid for real, through its own machine.
	profile.set_flag("hana_first_lesson")
	RaidLogic.start(profile, raid)
	RaidLogic.mark_recall_cleared(profile, "sushi_prep")
	RaidLogic.complete_boss(profile, db, inv, raid)
	check_true("the finished raid opens the gate", ExpeditionLogic.can_enter(profile, exp))
	check_true("unlock_ready agrees", ExpeditionLogic.unlock_ready(profile, exp))

	# --- the staged chain: guard -> lunchbox -> recall -> boss --------------
	var prog := ExpeditionLogic.start(profile, exp)
	check_eq("entering starts the run", prog.get("stage"), "active")
	check_true("the lunchbox cannot be taken past the guard",
		not ExpeditionLogic.recover_objective(profile, "forest_lunchbox"))
	check_true("the recall cannot clear before the lunchbox",
		not ExpeditionLogic.mark_recall_cleared(profile, "forest_lunchbox"))
	check_eq("the boss pays nothing early",
		ExpeditionLogic.complete_boss(profile, db, inv, exp), "")

	check_true("the guard falls", ExpeditionLogic.mark_encounter_cleared(profile, "forest_lunchbox"))
	check_true("a beaten guard stays beaten",
		not ExpeditionLogic.mark_encounter_cleared(profile, "forest_lunchbox"))

	# Retreat here: leaving and re-entering must resume, not restart.
	var resumed := ExpeditionLogic.start(profile, exp)
	check_eq("a retreat resumes the saved stage", resumed.get("stage"), "encounter-cleared")

	check_true("the lunchbox is recovered", ExpeditionLogic.recover_objective(profile, "forest_lunchbox"))
	check_true("the recall clears", ExpeditionLogic.mark_recall_cleared(profile, "forest_lunchbox"))

	# --- completion: rewards, flags, discovery, exactly once ----------------
	var coins_before: int = inv.coins
	var stamps_before: int = inv.count("recipe_stamp")
	var summary: String = ExpeditionLogic.complete_boss(profile, db, inv, exp)
	check_true("the boss pays out with the TS summary", not summary.is_empty())
	check_true("summary names the run and the recipe",
		summary.contains("Lost Lunchbox Expedition complete") and summary.contains("recipe:"))
	check_eq("80 coins paid", inv.coins - coins_before, 80)
	check_eq("one more Recipe Stamp", inv.count("recipe_stamp") - stamps_before, 1)
	check_eq("three Moonwood granted", inv.count("moonwood"), 3)
	check_true("completion flag set", profile.get_flag("expedition_forest_done"))
	check_true("the Forest Lunchbox recipe is discovered",
		CraftRules.is_known(db.recipe("cook_forest_lunchbox"), profile.data))
	check_eq("a second boss kill pays nothing",
		ExpeditionLogic.complete_boss(profile, db, inv, exp), "")

	# --- repeatable rerun keeps its history ---------------------------------
	check_true("a finished repeatable run can be entered again",
		ExpeditionLogic.can_enter(profile, exp))
	var rerun := ExpeditionLogic.start(profile, exp)
	check_eq("the rerun starts fresh", rerun.get("stage"), "active")
	check_eq("but keeps the completion count", int(rerun.get("completions", 0)), 1)

	# --- persisted shape (TS-save compatible) -------------------------------
	var saved: Dictionary = profile.to_save_dict()
	check_true("expeditions table persists in the save", saved.has("expeditions"))
	var reloaded := LearningProfile.new(saved, db)
	check_eq("a reloaded profile resumes the rerun mid-flight",
		ExpeditionLogic.progress(reloaded, "forest_lunchbox").get("stage"), "active")

	_finish()


func _finish() -> void:
	print("")
	print(("PASS — the Lost Lunchbox Expedition gates, stages, and persists like the TS build."
		if failures == 0 else "FAIL — %d expedition check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
