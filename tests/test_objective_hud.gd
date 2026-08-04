extends SceneTree
## The world objective HUD follows the saved activity across activity types and
## does not depend on a matching QuestGiver existing in the current scene.

const Activities = preload("res://src/systems/activity_tracker.gd")

var failures := 0


func _initialize() -> void:
	await process_frame
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
	var inv: Node = root.get_node("Inv")
	var original_profile = learning.profile
	var original_inventory: Dictionary = inv.to_dict()
	learning.profile = LearningProfile.new({}, db)
	inv.reset()

	var quest_id := "stock_the_stall"
	learning.profile.set_flag(QuestJournal.started_flag(quest_id))
	var quest: Dictionary = db.quest(quest_id)
	inv.add(String(quest["goal"]["item"]), 1)

	var hud := CanvasLayer.new()
	hud.set_script(load("res://src/ui/objective_hud.gd"))
	root.add_child(hud)
	await process_frame
	await process_frame
	var title: Label = hud.find_child("ObjectiveTitle", true, false)
	var detail: Label = hud.find_child("ObjectiveDetail", true, false)
	check_true("the global HUD builds without a scene-local quest giver",
		title != null and detail != null)
	check_true("the automatic objective names the active Quest",
		title != null and title.text.contains("Quest · Stock the Stall"))
	check_true("the objective carries live bag progress",
		detail != null and detail.text.contains("1/"))

	learning.profile.set_flag(QuestJournal.done_flag(quest_id))
	QuestJournal.begin(learning.profile, db.quest("valley_morning"))
	learning.profile.record_activity(LearningProfile.ACTIVITY_FARM_HARVEST)
	Activities.track(learning.profile, db, inv, "quest:valley_morning")
	hud.call("_refresh")
	check_true("the HUD names a tracked typed activity Quest",
		title.text.contains("Quest · A Valley Morning"))
	check_true("the HUD shows the next world action rather than an empty item",
		detail.text.contains("Gather a resource node  0/1"))

	learning.profile.set_flag("hana_first_lesson")
	learning.profile.data["raids"] = {
		"sushi_prep": {"stage": "recall-cleared", "completions": 0},
	}
	Activities.track(learning.profile, db, inv, "raid:sushi_prep")
	hud.call("_refresh")
	check_true("a saved Raid selection replaces the Quest on the HUD",
		title.text.contains("Raid · Sushi Prep Raid"))
	check_true("the Raid objective names its real boss",
		detail.text.contains("Pantry Oni"))

	learning.profile.set_flag(QuestJournal.done_flag("valley_morning"))
	learning.profile.set_flag("expedition_forest_unlocked")
	learning.profile.data["raids"] = {
		"sushi_prep": {"stage": "complete", "completions": 1},
	}
	hud.call("_refresh")
	check_true("completion falls the live HUD forward to the Expedition",
		title.text.contains("Expedition · Lost Lunchbox Expedition"))
	check_eq("the fallback replaces the stale saved key",
		learning.profile.data[Activities.TRACKED_KEY], "expedition:forest_lunchbox")

	hud.queue_free()
	await process_frame
	learning.profile = original_profile
	inv.load_dict(original_inventory)
	_finish()


func _finish() -> void:
	print("")
	print(("PASS — the objective HUD follows saved activities across maps."
		if failures == 0 else "FAIL — %d objective-HUD check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
