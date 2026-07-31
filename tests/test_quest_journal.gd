extends SceneTree
## The quest journal's pure state resolution.
##
##   godot --headless --path . --script res://tests/test_quest_journal.gd
##
## 19 quests are authored, but the only place a quest was ever visible was the
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
