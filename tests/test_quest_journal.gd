extends SceneTree
## The quest journal's pure state resolution.
##
##   godot --headless --path . --script res://tests/test_quest_journal.gd
##
## The only place a quest was once visible was the
## one-line objective HUD, which reads the giver standing in the current scene.
## Finish a quest and it vanished; walk to another map and it vanished. Nothing
## in the game could answer "what have I done" or "what am I carrying this for".
##
## The stages come from two persisted flags per quest plus what is in the bag
## right now, so this asserts the resolution rather than clicking dialogue.

var failures: int = 0
var db: Node
var inv: Node


func _initialize() -> void:
	db = load("res://src/autoload/db.gd").new()
	db.load_all()
	inv = load("res://src/autoload/inv.gd").new()
	inv.reset()

	_stages_follow_flags_and_bag()
	_multi_objective_checklist_advances()
	_activity_objectives_start_at_acceptance()
	_followup_chain_joins_study_craft_and_combat()
	_reading_order_puts_actionable_first()
	_unfound_quests_are_not_spoiled()

	inv.free()
	db.free()
	_finish()


func _stages_follow_flags_and_bag() -> void:
	var profile := LearningProfile.new({}, db)
	var quest_id := "stock_the_stall"
	var quest: Dictionary = db.quest(quest_id)
	var item := String(quest["goal"]["item"])
	var target := int(quest["goal"]["qty"])

	var e: Dictionary = QuestJournal.entry(profile, db, inv, quest_id)
	check_eq("an untouched quest is unmet", e["stage"], QuestJournal.Stage.UNMET)

	profile.set_flag(QuestJournal.started_flag(quest_id))
	e = QuestJournal.entry(profile, db, inv, quest_id)
	check_eq("accepting it makes it active", e["stage"], QuestJournal.Stage.ACTIVE)
	check_eq("an active quest reports nothing carried yet", e["progress"], 0)
	check_eq("an active quest reports its goal", e["goal"], target)

	inv.add(item, target - 1)
	e = QuestJournal.entry(profile, db, inv, quest_id)
	check_eq("partial progress is still active", e["stage"], QuestJournal.Stage.ACTIVE)
	check_eq("partial progress is counted", e["progress"], target - 1)

	inv.add(item, 1)
	e = QuestJournal.entry(profile, db, inv, quest_id)
	check_eq("meeting the goal marks it ready", e["stage"], QuestJournal.Stage.READY)
	check_true("a ready quest names who to return to", not String(e["giver"]).is_empty())

	# Turning in consumes the items, so "done" must not depend on still holding them.
	profile.set_flag(QuestJournal.done_flag(quest_id))
	inv.remove(item, target)
	e = QuestJournal.entry(profile, db, inv, quest_id)
	check_eq("a finished quest stays finished with an empty bag",
		e["stage"], QuestJournal.Stage.DONE)
	check_true("a finished quest keeps its description",
		not String(e["desc"]).is_empty())
	inv.reset()


func _multi_objective_checklist_advances() -> void:
	var profile := LearningProfile.new({}, db)
	var quest_id := "tools_of_the_trail"
	profile.set_flag(QuestJournal.started_flag(quest_id))
	var entry := QuestJournal.entry(profile, db, inv, quest_id)
	check_eq("the tool commission exposes all three objectives",
		(entry["objectives"] as Array).size(), 3)
	check_eq("the first missing tool leads the objective",
		entry["item"], "copper_pick")
	check_eq("a fresh checklist is active", entry["stage"], QuestJournal.Stage.ACTIVE)

	inv.add("copper_pick", 1)
	entry = QuestJournal.entry(profile, db, inv, quest_id)
	check_true("the completed Copper Pick row stays checked",
		bool((entry["objectives"] as Array)[0]["complete"]))
	check_eq("the next missing tool takes over the HUD",
		entry["item"], "trail_hatchet")
	check_eq("one of three tools is not ready to turn in",
		entry["stage"], QuestJournal.Stage.ACTIVE)

	inv.add("trail_hatchet", 1)
	inv.add("herb_sickle", 1)
	entry = QuestJournal.entry(profile, db, inv, quest_id)
	check_eq("all three permanent tools ready the commission",
		entry["stage"], QuestJournal.Stage.READY)
	check_true("every checklist row records non-consumption",
		(entry["objectives"] as Array).all(
			func(row): return not bool((row as Dictionary).get("consume", true))))
	inv.reset()


func _activity_objectives_start_at_acceptance() -> void:
	var profile := LearningProfile.new({}, db)
	var quest: Dictionary = db.quest("valley_morning")
	# Lifetime history exists, but a newly accepted teaching quest must ask for
	# three fresh actions rather than completing from old play.
	profile.record_activity(LearningProfile.ACTIVITY_FARM_HARVEST, 4)
	profile.record_activity(LearningProfile.ACTIVITY_RESOURCE_GATHER, 3)
	profile.record_activity(LearningProfile.ACTIVITY_FISH_CATCH, 2)
	check_true("accepting the activity quest snapshots its baselines",
		QuestJournal.begin(profile, quest))
	var entry := QuestJournal.entry(profile, db, inv, "valley_morning")
	check_eq("old activity never completes a newly accepted quest",
		(entry["objectives"] as Array).map(func(row): return row["progress"]), [0, 0, 0])
	check_eq("the first live action leads the compact HUD",
		entry["objective_label"], "Harvest a crop")

	profile.record_activity(LearningProfile.ACTIVITY_FARM_HARVEST)
	entry = QuestJournal.entry(profile, db, inv, "valley_morning")
	check_true("a post-acceptance harvest checks only its own row",
		bool((entry["objectives"] as Array)[0]["complete"])
		and not bool((entry["objectives"] as Array)[1]["complete"]))
	check_eq("the next activity advances into the HUD",
		entry["objective_label"], "Gather a resource node")

	var restored := LearningProfile.new(profile.to_save_dict(), db)
	entry = QuestJournal.entry(restored, db, inv, "valley_morning")
	check_eq("activity counts and acceptance baselines survive reload",
		(entry["objectives"] as Array).map(func(row): return row["progress"]), [1, 0, 0])
	restored.record_activity(LearningProfile.ACTIVITY_RESOURCE_GATHER)
	restored.record_activity(LearningProfile.ACTIVITY_FISH_CATCH)
	entry = QuestJournal.entry(restored, db, inv, "valley_morning")
	check_eq("all three daily actions ready the quest",
		entry["stage"], QuestJournal.Stage.READY)
	check_true("re-accepting cannot move the saved baseline",
		not QuestJournal.begin(restored, quest))


func _followup_chain_joins_study_craft_and_combat() -> void:
	var profile := LearningProfile.new({}, db)
	var current := QuestJournal.current_in_chain(profile, db, "valley_morning")
	check_eq("a fresh Aiko chain starts with the morning lesson",
		current.get("id", ""), "valley_morning")
	profile.set_flag(QuestJournal.done_flag("valley_morning"))
	current = QuestJournal.current_in_chain(profile, db, "valley_morning")
	check_eq("turning in the morning lesson reveals its authored follow-up",
		current.get("id", ""), "ready_for_the_road")

	for activity_id in [LearningProfile.ACTIVITY_REVIEW_CORRECT,
			LearningProfile.ACTIVITY_CRAFT_COMPLETE,
			LearningProfile.ACTIVITY_ENEMY_DEFEAT]:
		profile.record_activity(String(activity_id), 4)
	check_true("accepting the follow-up snapshots all three new baselines",
		QuestJournal.begin(profile, current))
	var entry := QuestJournal.entry(profile, db, inv, "ready_for_the_road")
	check_eq("old study, craft, and combat history is excluded",
		(entry["objectives"] as Array).map(func(row): return row["progress"]), [0, 0, 0])

	profile.record_activity(LearningProfile.ACTIVITY_REVIEW_CORRECT, 3)
	profile.record_activity(LearningProfile.ACTIVITY_CRAFT_COMPLETE)
	entry = QuestJournal.entry(profile, db, inv, "ready_for_the_road")
	check_eq("the final missing proof leads the compact HUD",
		entry["objective_label"], "Defeat an enemy")
	check_eq("partial follow-up progress survives as a mixed checklist",
		(entry["objectives"] as Array).map(func(row): return row["progress"]), [3, 1, 0])

	profile.record_activity(LearningProfile.ACTIVITY_ENEMY_DEFEAT)
	var restored := LearningProfile.new(profile.to_save_dict(), db)
	entry = QuestJournal.entry(restored, db, inv, "ready_for_the_road")
	check_eq("all three preparation proofs survive reload and ready the quest",
		entry["stage"], QuestJournal.Stage.READY)
	restored.set_flag(QuestJournal.done_flag("ready_for_the_road"))
	check_eq("a fully completed chain rests on its final authored quest",
		QuestJournal.current_in_chain(restored, db, "valley_morning").get("id", ""),
		"ready_for_the_road")


func _reading_order_puts_actionable_first() -> void:
	var profile := LearningProfile.new({}, db)
	# One of each stage, from three different quests.
	profile.set_flag(QuestJournal.started_flag("river_guard"))
	profile.set_flag(QuestJournal.started_flag("smiths_first_order"))
	profile.set_flag(QuestJournal.done_flag("smiths_first_order"))
	var ready_id := "stock_the_stall"
	profile.set_flag(QuestJournal.started_flag(ready_id))
	inv.add(String(db.quest(ready_id)["goal"]["item"]),
		int(db.quest(ready_id)["goal"]["qty"]))

	var entries: Array = QuestJournal.all_entries(profile, db, inv)
	check_eq("every authored quest is accounted for", entries.size(), db.quest_order.size())

	var stages: Array = []
	for e in entries:
		stages.append(int(e["stage"]))
	var first_done: int = stages.find(QuestJournal.Stage.DONE)
	var first_unmet: int = stages.find(QuestJournal.Stage.UNMET)
	check_eq("what can be turned in reads first",
		int(entries[0]["stage"]), QuestJournal.Stage.READY)
	check_true("work in progress comes before finished work",
		stages.find(QuestJournal.Stage.ACTIVE) < first_done)
	check_true("undiscovered quests come last", first_done < first_unmet)

	var counts: Dictionary = QuestJournal.counts(entries)
	check_eq("one quest is ready", counts["ready"], 1)
	check_eq("one quest is in progress", counts["active"], 1)
	check_eq("one quest is completed", counts["done"], 1)
	check_eq("the rest are still out there",
		counts["unmet"], db.quest_order.size() - 3)
	inv.reset()


func _unfound_quests_are_not_spoiled() -> void:
	var profile := LearningProfile.new({}, db)
	profile.set_flag(QuestJournal.started_flag("river_guard"))
	for e in QuestJournal.all_entries(profile, db, inv):
		if String(e["id"]) == "river_guard":
			check_true("a quest the player has met is shown by name",
				not QuestJournal.is_spoiler(e))
		elif int(e["stage"]) == QuestJournal.Stage.UNMET:
			check_true("a quest never met is withheld", QuestJournal.is_spoiler(e))
			return


func _finish() -> void:
	print("")
	print(("PASS — the journal remembers what the objective line forgets."
		if failures == 0 else "FAIL — %d quest-journal check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
