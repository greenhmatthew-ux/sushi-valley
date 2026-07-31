extends SceneTree
## Slice 2: LearningProfile + LearningProgression + SaveGame round-trip.
##
##   godot --headless --path . --script res://tests/test_learning.gd
##
## Uses the real content via a hand-instantiated DB (rather than the autoload) so
## the pure classes are exercised with no autoload coupling, against the actual
## 1392-card / 138-lesson pool. smoke_autoloads.gd covers the wired-up path.

var failures: int = 0
var db: Node


func _initialize() -> void:
	db = load("res://src/autoload/db.gd").new()
	db.load_all()

	_hydration()
	_flags()
	_unlock_and_answer()
	_build_defaults_and_migration()
	_save_round_trip()
	_lesson_auto_progression()
	_prompt_shape()
	_recall_eligibility()

	db.free()
	_finish()


func _hydration() -> void:
	var p := LearningProfile.new({}, db)
	check_eq("hydrates all cards", p.all_cards().size(), db.cards.size())
	var c := p.card("kana-a")
	check_true("card carries static def (prompt)", c.get("prompt", "") == "あ")
	check_true("card carries scheduling (ease)", c.get("ease", 0.0) == Srs.DEFAULT_EASE)
	check_true("fresh cards start locked", not c.get("unlocked", true))
	check_eq("nothing unlocked on a fresh profile", p.unlocked_cards().size(), 0)


func _flags() -> void:
	var p := LearningProfile.new({}, db)
	check_true("unknown flag is false", not p.get_flag("gate_x_cleared"))
	p.set_flag("gate_x_cleared")
	check_true("flag set", p.get_flag("gate_x_cleared"))
	p.set_flag("gate_x_cleared", false)
	check_true("flag cleared", not p.get_flag("gate_x_cleared"))


func _unlock_and_answer() -> void:
	var p := LearningProfile.new({}, db)
	var prog := LearningProgression.new(p, db)

	p.unlock_lesson("kana-vowels")
	var lesson: Dictionary = db.lesson("kana-vowels")
	check_true("unlocking a lesson unlocks its cards",
		p.unlocked_cards().size() == lesson["cardIds"].size())
	check_true("all unlocked cards are due", prog.due_count() == p.unlocked_cards().size())

	# Answer one correctly: stats move, xp lands, card reschedules out of "due now".
	var card: Dictionary = p.card("kana-a")
	var before_due := prog.due_count()
	var correct := prog.answer(card, "a")
	check_true("correct answer reports true", correct)
	check_eq("totalReviews incremented", p.data["stats"]["totalReviews"], 1)
	check_eq("totalCorrect incremented", p.data["stats"]["totalCorrect"], 1)
	check_eq("good grade awards 10 xp", p.data["stats"]["xp"], 10)
	check_eq("answered card no longer due now", prog.due_count(), before_due - 1)
	check_eq("correctCount on the card", p.card("kana-a")["correctCount"], 1)

	# A wrong answer: no xp, reschedules ~30s out (still not due 'now').
	var card2: Dictionary = p.card("kana-i")
	var wrong := prog.answer(card2, "totally-wrong")
	check_true("wrong answer reports false", not wrong)
	check_eq("wrong grade awards no xp", p.data["stats"]["xp"], 10)
	check_eq("wrong answer still counts a review", p.data["stats"]["totalReviews"], 2)
	check_eq("incorrectCount on the card", p.card("kana-i")["incorrectCount"], 1)

	# Answer comparison is trim + lowercase.
	var card3: Dictionary = p.card("kana-u")
	check_true("answer matching is case/space-insensitive", prog.answer(card3, "  U "))


func _build_defaults_and_migration() -> void:
	var fresh := LearningProfile.new({}, db)
	var b := fresh.build()
	check_true("fresh build has starter skills",
		b["skills"] == ["strike", "guard", "focus"])
	check_true("fresh build has zeroed allocations",
		b["allocations"] == {"vitality": 0, "power": 0, "agility": 0})

	# Legacy saves used `deck`; it must migrate to `skills` and be dropped.
	var legacy := LearningProfile.new({"build": {"deck": ["strike", "strike", "focus"]}}, db)
	var lb := legacy.build()
	check_true("legacy deck -> skills, de-duped", lb["skills"] == ["strike", "focus"])
	check_true("legacy deck field removed", not lb.has("deck"))


func _save_round_trip() -> void:
	var path := "user://test_profile.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# Set up a profile, mutate it, and persist through a SaveGame-style saver.
	var save: Node = load("res://src/autoload/save_game.gd").new()
	var p := LearningProfile.new({}, db)
	p.saver = func(d: Dictionary): _write(save, path, d)
	p.unlock_lesson("kana-vowels")
	var prog := LearningProgression.new(p, db)
	prog.answer(p.card("kana-a"), "a")
	prog.answer(p.card("kana-a"), "a")   # correctCount now 2
	p.set_flag("saw_the_gate")
	p.save()

	check_true("save file was written", FileAccess.file_exists(path))

	# The persisted card must be SLIM: scheduling only, no static def fields.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check_true("saved card omits static def (no prompt)",
		not (raw["cards"]["kana-a"] as Dictionary).has("prompt"))
	check_true("saved card keeps scheduling (correctCount)",
		raw["cards"]["kana-a"]["correctCount"] == 2)

	# Reload: static def rehydrates, saved scheduling + flag survive.
	var reloaded := LearningProfile.new(_read(save, path), db)
	check_true("reloaded card rehydrates its prompt",
		reloaded.card("kana-a").get("prompt", "") == "あ")
	check_true("reloaded card keeps correctCount",
		reloaded.card("kana-a")["correctCount"] == 2)
	check_true("reloaded card stays unlocked", reloaded.card("kana-a")["unlocked"])
	check_true("reloaded flag survives", reloaded.get_flag("saw_the_gate"))
	check_true("reloaded xp survives", reloaded.data["stats"]["xp"] == 20)

	save.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _lesson_auto_progression() -> void:
	# Find a category with at least two lessons so "master one, unlock the next"
	# has somewhere to go.
	var pair := _first_category_pair()
	if pair.is_empty():
		check_true("(skipped) no multi-lesson category found", true)
		return
	var first: Dictionary = pair[0]
	var second: Dictionary = pair[1]

	var p := LearningProfile.new({}, db)
	var prog := LearningProgression.new(p, db)
	p.unlock_lesson(first["id"])

	check_true("next lesson starts locked",
		not p.card(second["cardIds"][0]).get("unlocked", false))

	# Master the first lesson: answer every card correctly (>=1 correct, >=60% acc).
	for cid in first["cardIds"]:
		prog.grade(p.card(cid), "good")

	check_true("mastering a lesson unlocks the next in its category",
		p.card(second["cardIds"][0]).get("unlocked", false))


func _prompt_shape() -> void:
	var p := LearningProfile.new({}, db)
	var prog := LearningProgression.new(p, db)

	check_true("no prompt when nothing is unlocked", prog.build_prompt().is_empty())

	p.unlock_lesson("kana-vowels")
	var prompt := prog.build_prompt()
	check_true("prompt built once cards are due", not prompt.is_empty())
	check_true("prompt question is the card's prompt", String(prompt["question"]) != "")
	check_true("choices include the correct answer",
		prompt["answer"] in prompt["choices"])
	check_true("choices are de-duplicated",
		prompt["choices"].size() == _unique(prompt["choices"]).size())
	check_true("due prompt is tagged 'due'", prompt["mode"] == "due")

	# focus_lesson narrows to that lesson's cards.
	var focused := prog.build_prompt({}, false, "kana-vowels")
	check_true("focused prompt draws from the focus lesson",
		focused.is_empty() or focused["card"]["lessonId"] == "kana-vowels")


## Imported decks contain remark/page-number cards (answer "14", essay-long
## choices). They must never reach a rune button, the due count, or block mastery.
func _recall_eligibility() -> void:
	var junk_id := "japanese-course-based-on-tae-kims-grammar-guide-anime-7"
	check_eq("the imported remark card is real test data",
		String(db.card(junk_id).get("answer", "")), "14")
	check_true("page-number answers are not recallable",
		not LearningProgression.recall_eligible(db.card(junk_id)))
	check_true("essay answers are not recallable",
		not LearningProgression.choice_plausible("x".repeat(61)))
	check_true("short Japanese answers stay recallable",
		LearningProgression.recall_eligible(db.card("kana-a")))

	# The junk card never becomes a prompt, even when it is the only unlocked card.
	var p := LearningProfile.new({}, db)
	var prog := LearningProgression.new(p, db)
	p.unlock_card(junk_id)
	check_true("junk-only pool builds no prompt", prog.build_prompt().is_empty())
	check_true("junk-only pool offers no practice either",
		prog.build_prompt({}, true).is_empty())
	check_eq("junk cards do not count as due", prog.due_count(), 0)

	# With real cards unlocked too, choices stay plausible on every draw.
	p.unlock_lesson("kana-vowels")
	var saw_prompt := false
	for i in 12:
		var prompt := prog.build_prompt({}, true)
		if prompt.is_empty():
			continue
		saw_prompt = true
		for choice in prompt["choices"]:
			check_true("choice fits a rune button: '%s'" %
				String(choice).substr(0, 24),
				LearningProgression.choice_plausible(String(choice)))
	check_true("mixed pool still builds prompts", saw_prompt)

	# The imported deck drives the same auto-progression chain as native lessons.
	check_eq("imported cards resolve to their curriculum lesson",
		String(db.card("japanese-course-based-on-tae-kims-grammar-guide-anime-1")
			.get("lessonId", "")), "tae-kim-1")
	var p2 := LearningProfile.new({}, db)
	var prog2 := LearningProgression.new(p2, db)
	var first: Dictionary = db.lesson("tae-kim-1")
	var second: Dictionary = db.lesson("tae-kim-2")
	check_true("grammar chain exists for the mastery check",
		not first.is_empty() and not second.is_empty())
	prog2.profile.unlock_lesson("tae-kim-1")
	for cid in first["cardIds"]:
		prog2.grade(p2.card(cid), "good")
	check_true("mastering an imported lesson unlocks the next one",
		p2.card(second["cardIds"][0]).get("unlocked", false))

	# Mastery must still complete from the real cards alone when a lesson mixes
	# them with junk. Built as a fixture rather than pinned to whichever imported
	# deck is currently broken — the decks get repaired, the rule has to hold.
	var mixed := _inject_mixed_lesson("fixture-mixed")
	var p3 := LearningProfile.new({}, db)
	var prog3 := LearningProgression.new(p3, db)
	p3.unlock_lesson("fixture-mixed")
	var graded := 0
	for cid in mixed["cardIds"]:
		var c: Dictionary = p3.card(cid)
		if LearningProgression.recall_eligible(c):
			graded += 1
			prog3.grade(c, "good")
	check_true("the fixture really does mix real and junk cards",
		graded > 0 and graded < mixed["cardIds"].size())
	check_true("junk cards do not block lesson mastery",
		bool(prog3.call("_is_lesson_mastered", mixed)))


# --- helpers ---------------------------------------------------------------

## A lesson holding two reviewable cards and two imported page-number remarks,
## added to the loaded content so the eligibility rules can be tested without
## depending on a real deck staying broken. Prompts stay ASCII: authored Japanese
## is not allowed anywhere in this project, fixtures included.
func _inject_mixed_lesson(lesson_id: String) -> Dictionary:
	var ids: Array = []
	for i in 4:
		var cid := "%s-card-%d" % [lesson_id, i]
		var junk := i >= 2
		db.cards[cid] = {
			"id": cid, "lessonId": lesson_id, "type": "vocab",
			"prompt": "fixture prompt %d" % i,
			"answer": "14" if junk else "fixture answer %d" % i,
			"meaning": "fixture", "reading": "fixture", "choices": [],
		}
		db.card_order.append(cid)
		ids.append(cid)
	var lesson := {
		"id": lesson_id, "title": "Mixed fixture",
		"category": "fixture", "cardIds": ids,
	}
	db.lessons[lesson_id] = lesson
	db.lesson_order.append(lesson_id)
	return lesson


func _first_category_pair() -> Array:
	var by_category := {}
	for lid in db.lesson_order:
		var l: Dictionary = db.lessons[lid]
		if (l.get("cardIds", []) as Array).is_empty():
			continue
		var cat := String(l.get("category", ""))
		if not by_category.has(cat):
			by_category[cat] = []
		by_category[cat].append(l)
	for cat in by_category:
		if by_category[cat].size() >= 2:
			return [by_category[cat][0], by_category[cat][1]]
	return []


func _unique(arr: Array) -> Array:
	var seen := {}
	var out: Array = []
	for x in arr:
		if not seen.has(x):
			seen[x] = true
			out.append(x)
	return out


func _write(save: Node, path: String, data: Dictionary) -> void:
	# SaveGame writes a fixed path; here we target a test path via the same JSON path.
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _read(_save: Node, path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _finish() -> void:
	print("")
	print(("PASS — learning profile, progression, and save round-trip hold."
		if failures == 0 else "FAIL — %d learning check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
