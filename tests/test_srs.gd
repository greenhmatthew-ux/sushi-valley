extends SceneTree
## Slice 2: pin the SRS scheduler's interval math to the TS behavior.
##
##   godot --headless --path . --script res://tests/test_srs.gd
##
## Every `dueAt` here is asserted against a FIXED `now`, so these are exact,
## reproducible checks of the tuned intervals — not "looks about right". If a
## refactor shifts an interval, this fails loudly, which is the whole point: the
## early-interval pacing (30s / 10min / 1h / 4h) is what makes studying feel good
## and is the easiest thing to break silently.

const NOW := 1_000_000_000_000.0   # a fixed instant, epoch ms
const SEC := 1000.0
const MINUTE := 60 * SEC
const HOUR := 60 * MINUTE
const DAY := 24 * HOUR

var failures: int = 0


func _initialize() -> void:
	_new_card_defaults()
	_again_reschedules_in_30s()
	_good_ladder_within_session()
	_easy_ladder()
	_hard_from_fresh()
	_mature_intervals_scale_by_ease()
	_ease_falls_on_wrong_rises_on_easy()
	_due_filters_and_sorts()
	_grade_from_correct()
	_finish()


func _new_card_defaults() -> void:
	var d := Srs.new_card_defaults(NOW)
	check_eq("fresh dueAt = now", d["dueAt"], NOW)
	check_eq("fresh interval = 0", d["intervalDays"], 0.0)
	check_eq("fresh ease = 2.3", d["ease"], 2.3)
	check_true("fresh lastReviewedAt is null", d["lastReviewedAt"] == null)


func _again_reschedules_in_30s() -> void:
	var c := _card()
	Srs.review(c, "again", NOW)
	check_eq("again -> due in 30s", c["dueAt"], NOW + 30 * SEC)
	check_eq("again -> interval 0", c["intervalDays"], 0.0)
	check_eq("again -> incorrectCount 1", c["incorrectCount"], 1)
	check_eq("again -> correctCount 0", c["correctCount"], 0)


## A NON-OBVIOUS property, verified against the real TS review() (see the node
## parity run in scratchpad/srs_ref.mjs): consecutive "good" grades do NOT climb
## the 10min -> 1h -> 4h ladder. Each tier sets an interval still below the
## threshold that would advance it, so "good" holds a card at its current tier and
## recycles it within the session. In gameplay this is the whole behavior, because
## gradeFromCorrect() only ever returns "good" or "again". Tiers are reached by
## "easy"/"hard" or once an interval matures. This test pins that so the tuning
## can't drift silently — a refactor that made "good" climb would change the feel
## of studying and would be a design decision, not a bug fix.
func _good_ladder_within_session() -> void:
	var c := _card()
	Srs.review(c, "good", NOW)
	check_eq("1st good -> 10 min", c["dueAt"], NOW + 10 * MINUTE)
	check_eq("1st good -> interval 0.007", c["intervalDays"], 0.007)
	check_eq("1st good -> correctCount 1", c["correctCount"], 1)

	# Repeated goods stay at 10 min — they do not advance on their own.
	Srs.review(c, "good", NOW)
	check_eq("2nd good -> still 10 min", c["dueAt"], NOW + 10 * MINUTE)
	check_eq("2nd good -> still interval 0.007", c["intervalDays"], 0.007)
	Srs.review(c, "good", NOW)
	check_eq("3rd good -> still 10 min", c["dueAt"], NOW + 10 * MINUTE)

	# The 1h and 4h tiers ARE reachable — but only once the interval is already in
	# that band (e.g. put there by an "easy"/"hard" or a mature interval).
	var mid := _card()
	mid["intervalDays"] = 0.03   # in the [0.01, 0.05) band
	Srs.review(mid, "good", NOW)
	check_eq("good from 0.03 -> 1 hour", mid["dueAt"], NOW + HOUR)
	mid["intervalDays"] = 0.1    # in the [0.05, 0.2) band
	Srs.review(mid, "good", NOW)
	check_eq("good from 0.10 -> 4 hours", mid["dueAt"], NOW + 4 * HOUR)


func _easy_ladder() -> void:
	var c := _card()
	Srs.review(c, "easy", NOW)
	check_eq("1st easy -> 30 min", c["dueAt"], NOW + 30 * MINUTE)
	check_eq("1st easy -> interval 0.02", c["intervalDays"], 0.02)
	check_close("1st easy -> ease 2.4", c["ease"], 2.4)

	# 0.02 is in the [0.01, 0.1) band, not < 0.01, so 2nd easy jumps to 4h/0.17.
	Srs.review(c, "easy", NOW)
	check_eq("2nd easy -> 4 hours", c["dueAt"], NOW + 4 * HOUR)
	check_eq("2nd easy -> interval 0.17", c["intervalDays"], 0.17)

	# 3rd easy is mature: ease rises to 2.6 FIRST, then interval *= ease * 1.3 uses
	# the NEW ease (0.17 * 2.6 * 1.3), matching the TS ordering.
	Srs.review(c, "easy", NOW)
	check_close("3rd easy -> interval 0.17*2.6*1.3", c["intervalDays"], 0.17 * 2.6 * 1.3)
	check_close("3rd easy -> ease 2.6", c["ease"], 2.6)


func _hard_from_fresh() -> void:
	var c := _card()
	Srs.review(c, "hard", NOW)
	check_eq("hard from fresh -> 1 hour", c["dueAt"], NOW + HOUR)
	check_eq("hard from fresh -> interval 0.04", c["intervalDays"], 0.04)
	check_eq("hard counts as correct", c["correctCount"], 1)
	check_close("hard -> ease 2.15", c["ease"], 2.15)


func _mature_intervals_scale_by_ease() -> void:
	# A card already matured to a multi-day interval: good multiplies by ease.
	var c := _card()
	c["intervalDays"] = 5.0
	c["ease"] = 2.0
	Srs.review(c, "good", NOW)
	check_eq("mature good -> interval 5*2", c["intervalDays"], 10.0)
	check_eq("mature good -> due 10 days out", c["dueAt"], NOW + 10 * DAY)

	# Mature hard multiplies by 1.2, not ease.
	var h := _card()
	h["intervalDays"] = 5.0
	Srs.review(h, "hard", NOW)
	check_close("mature hard -> interval 5*1.2", h["intervalDays"], 6.0)


func _ease_falls_on_wrong_rises_on_easy() -> void:
	var c := _card()
	check_eq("start ease 2.3", c["ease"], 2.3)
	Srs.review(c, "again", NOW)
	check_close("again -> ease -0.2", c["ease"], 2.1)
	Srs.review(c, "hard", NOW)
	check_close("hard -> ease -0.15", c["ease"], 1.95)

	# Ease has a floor of 1.3 no matter how many misses.
	for i in 20:
		Srs.review(c, "again", NOW)
	check_eq("ease floored at 1.3", c["ease"], 1.3)


func _due_filters_and_sorts() -> void:
	var soon := _card(); soon["unlocked"] = true; soon["dueAt"] = NOW - 100.0
	var sooner := _card(); sooner["unlocked"] = true; sooner["dueAt"] = NOW - 500.0
	var future := _card(); future["unlocked"] = true; future["dueAt"] = NOW + 10000.0
	var locked := _card(); locked["unlocked"] = false; locked["dueAt"] = NOW - 9999.0

	var result := Srs.due([soon, future, sooner, locked], NOW)
	check_eq("only 2 unlocked+due", result.size(), 2)
	check_true("soonest-due first", result[0] == sooner)
	check_true("locked card excluded even when overdue", not (locked in result))


func _grade_from_correct() -> void:
	check_true("correct -> good", Srs.grade_from_correct(true) == "good")
	check_true("wrong -> again", Srs.grade_from_correct(false) == "again")


# --- helpers ---------------------------------------------------------------

func _card() -> Dictionary:
	var c := {"id": "t", "unlocked": true}
	c.merge(Srs.new_card_defaults(NOW), true)
	return c


func _finish() -> void:
	print("")
	print(("PASS — SRS intervals match the TS." if failures == 0
		else "FAIL — %d SRS check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s)" % [label, got], got == want)


func check_close(label: String, got: float, want: float) -> void:
	check_true("%s (got %f, want %f)" % [label, got, want], absf(got - want) < 0.0001)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
