extends SceneTree
## The Bestiary: what the player has fought and beaten.
##
##   godot --headless --path . --script res://tests/test_bestiary.gd
##
## PORT_NOTES.md and COMBAT_DESIGN.md both mention a Compendium tab and
## "bestiary flags" from the legacy TS build, but neither the tracking nor the
## tab ever made it into this port — there was no way to answer "what have I
## fought" at all. This pins the resolution logic and the two write points
## (Bus.combat_started, Bus.enemy_died) that feed it.

var failures: int = 0
var db: Node


func _initialize() -> void:
	await process_frame
	db = root.get_node("DB")

	_pure_stage_resolution()
	_every_authored_enemy_resolves()
	_unfought_enemies_are_not_spoiled()
	_bus_wiring_records_real_fights()

	_finish()


func _pure_stage_resolution() -> void:
	var profile := LearningProfile.new({}, db)
	var enemy_id := "mushroom"

	var e: Dictionary = Bestiary.entry(profile, db, enemy_id)
	check_eq("an unfought enemy is unseen", e["stage"], Bestiary.Stage.UNSEEN)
	check_eq("and has no kills", e["kills"], 0)

	profile.record_enemy_seen(enemy_id)
	e = Bestiary.entry(profile, db, enemy_id)
	check_eq("fighting it marks it seen", e["stage"], Bestiary.Stage.SEEN)
	check_eq("seen alone is not a kill", e["kills"], 0)

	profile.record_enemy_defeated(enemy_id)
	e = Bestiary.entry(profile, db, enemy_id)
	check_eq("winning marks it defeated", e["stage"], Bestiary.Stage.DEFEATED)
	check_eq("the first win counts as one kill", e["kills"], 1)

	profile.record_enemy_defeated(enemy_id)
	e = Bestiary.entry(profile, db, enemy_id)
	check_eq("a second win adds to the count, not a flag", e["kills"], 2)
	check_eq("still just defeated, not some higher stage", e["stage"], Bestiary.Stage.DEFEATED)

	# Real data, not placeholders: what shows for a defeated enemy has to be the
	# actual authored numbers, or the card would be lying about the fight.
	var real: Dictionary = db.enemy(enemy_id)
	check_eq("stats come from the real enemy row", e["max_hp"], int(real["maxHp"]))
	check_true("drops come from the real enemy row",
		e["drops"] == real.get("drops", []))


func _every_authored_enemy_resolves() -> void:
	var profile := LearningProfile.new({}, db)
	var entries: Array = Bestiary.all_entries(profile, db)
	check_eq("every authored enemy has a bestiary entry",
		entries.size(), db.enemy_order.size())
	var counts: Dictionary = Bestiary.counts(entries)
	check_eq("a fresh profile has fought nothing", counts["defeated"], 0)
	check_eq("all of them start unseen", counts["unseen"], entries.size())


func _unfought_enemies_are_not_spoiled() -> void:
	var profile := LearningProfile.new({}, db)
	profile.record_enemy_seen("mushroom")
	var wrongly_spoiled: Array[String] = []
	var wrongly_hidden: Array[String] = []
	for e in Bestiary.all_entries(profile, db):
		var should_hide := String(e["id"]) != "mushroom"
		if should_hide != Bestiary.is_spoiler(e):
			(wrongly_hidden if should_hide else wrongly_spoiled).append(String(e["id"]))
	check_true("the one fought enemy is not treated as a spoiler (%s)" % str(wrongly_spoiled),
		wrongly_spoiled.is_empty())
	check_true("every other enemy is withheld (%s)" % str(wrongly_hidden),
		wrongly_hidden.is_empty())


## Combat never calls into the bestiary directly — it only announces on the Bus,
## per the project's "systems communicate through signals" rule — so this is the
## thing that actually has to hold: emitting the real signals updates the real
## profile the Learning autoload owns.
func _bus_wiring_records_real_fights() -> void:
	var learning: Node = root.get_node("Learning")
	var bus: Node = root.get_node("Bus")
	var enemy_id := "kappa"

	# Clean slate: earlier suites in a shared run may have already fought this one.
	learning.profile.data.erase("bestiary")

	check_true("starts unfought for this check",
		not learning.profile.bestiary_entry(enemy_id).get("seen", false))

	bus.combat_started.emit(enemy_id)
	check_true("combat_started records it as seen",
		learning.profile.bestiary_entry(enemy_id).get("seen", false))
	check_true("but not yet defeated",
		not learning.profile.bestiary_entry(enemy_id).get("defeated", false))

	var defeats_before: int = learning.profile.activity_count(
		LearningProfile.ACTIVITY_ENEMY_DEFEAT)
	bus.enemy_died.emit(enemy_id)
	check_true("enemy_died records the win",
		learning.profile.bestiary_entry(enemy_id).get("defeated", false))
	check_eq("and counts the kill",
		int(learning.profile.bestiary_entry(enemy_id).get("kills", 0)), 1)
	check_eq("a real victory records one authored defeat activity",
		learning.profile.activity_count(LearningProfile.ACTIVITY_ENEMY_DEFEAT),
		defeats_before + 1)

	learning.profile.data.erase("bestiary")
	learning.profile.save()


func _finish() -> void:
	print("")
	print(("PASS — the bestiary remembers every real fight, honestly."
		if failures == 0 else "FAIL — %d bestiary check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
