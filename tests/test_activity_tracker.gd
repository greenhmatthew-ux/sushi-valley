extends SceneTree
## Unified activity state and persistence across Quests, Raids, and Expeditions.

const Activities = preload("res://src/systems/activity_tracker.gd")

var failures := 0
var db: Node
var inv: Node


func _initialize() -> void:
	db = load("res://src/autoload/db.gd").new()
	db.load_all()
	inv = load("res://src/autoload/inv.gd").new()
	inv.reset()
	var profile := LearningProfile.new({}, db)

	check_true("a fresh profile has no actionable activity",
		Activities.actionable_entries(profile, db, inv).is_empty())
	check_true("old saves need no tracked-activity field",
		not profile.data.has(Activities.TRACKED_KEY))

	var quest_id := "stock_the_stall"
	profile.set_flag(QuestJournal.started_flag(quest_id))
	profile.set_flag("hana_first_lesson")
	var current := Activities.current(profile, db, inv)
	check_eq("an active quest beats an unstarted Raid as the automatic cue",
		current["key"], "quest:" + quest_id)
	check_true("ordinary quests expose typed HUD and summary copy",
		String(current["hud_detail"]).contains("0/")
		and String(current["summary_text"]).contains("In progress"))

	check_true("the player can explicitly track the available Raid",
		Activities.track(profile, db, inv, "raid:sushi_prep"))
	check_eq("the typed selection is persisted in profile data",
		profile.to_save_dict()[Activities.TRACKED_KEY], "raid:sushi_prep")
	profile = LearningProfile.new(profile.to_save_dict(), db)
	check_eq("the tracked key survives a real profile round trip",
		Activities.tracked_key(profile), "raid:sushi_prep")
	check_eq("the saved selection overrides automatic priority",
		Activities.current(profile, db, inv)["key"], "raid:sushi_prep")
	check_true("an invalid activity key is rejected",
		not Activities.track(profile, db, inv, "raid:not_real"))

	profile.data["raids"] = {
		"sushi_prep": {"stage": "recall-cleared", "completions": 0},
	}
	current = Activities.current(profile, db, inv)
	check_eq("Raid boss readiness is normalized", current["state"], "Boss ready")
	check_true("the HUD copy names the real Raid boss",
		String(current["hud_detail"]).contains("Pantry Oni"))

	profile.set_flag(QuestJournal.done_flag(quest_id))
	profile.set_flag("expedition_forest_unlocked")
	profile.data["raids"] = {
		"sushi_prep": {"stage": "complete", "completions": 1},
	}
	current = Activities.reconcile(profile, db, inv)
	check_eq("a completed tracked Raid falls forward to the unlocked Expedition",
		current["key"], "expedition:forest_lunchbox")
	check_eq("the replacement selection is persisted",
		profile.data[Activities.TRACKED_KEY], "expedition:forest_lunchbox")

	profile.data["expeditions"] = {
		"forest_lunchbox": {"stage": "objective-recovered", "completions": 0},
	}
	current = Activities.current(profile, db, inv)
	check_eq("Expedition objective recovery becomes the Recall state",
		current["state"], "Recall")
	check_true("its HUD copy gives the exact next action",
		String(current["hud_detail"]).contains("Complete recall"))

	profile.data["expeditions"] = {
		"forest_lunchbox": {"stage": "complete", "completions": 1},
	}
	current = Activities.current(profile, db, inv)
	check_true("a completed repeatable Expedition remains actionable",
		current["trackable"] and current["state"] == "Repeatable")
	check_true("clearing the selection removes only the optional field",
		Activities.clear(profile) and not profile.data.has(Activities.TRACKED_KEY))

	var checklist_profile := LearningProfile.new({}, db)
	checklist_profile.set_flag(QuestJournal.started_flag("tools_of_the_trail"))
	inv.add("copper_pick", 1)
	current = Activities.current(checklist_profile, db, inv)
	check_eq("the multi-objective commission is a trackable Quest",
		current["key"], "quest:tools_of_the_trail")
	check_true("the Journal shows the complete three-tool checklist",
		String(current["detail"]).contains("[x] Copper Pick 1/1")
		and String(current["detail"]).contains("[ ] Trail Hatchet 0/1")
		and String(current["detail"]).contains("[ ] Herb Sickle 0/1"))
	check_true("the compact HUD advances to the next unfinished tool",
		String(current["hud_detail"]).contains("Trail Hatchet  0/1"))
	check_true("returning-player copy summarizes checklist completion",
		String(current["summary_text"]).contains("1/3 objectives"))
	inv.reset()

	inv.free()
	db.free()
	_finish()


func _finish() -> void:
	print("")
	print(("PASS — unified activity tracking persists and falls forward safely."
		if failures == 0 else "FAIL — %d activity-tracker check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
