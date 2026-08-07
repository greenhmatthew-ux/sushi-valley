extends SceneTree
## The staged-content chain, walked end to end the way a player meets it.
##
##   godot --headless --path . --script res://tests/test_content_staging.gd
##
## Matthew's content model: "staged content being gates to new areas, unlocking raids and
## expeditions in an area, and random events."
##
## Every link in that chain already had its own unit coverage, and the chain itself had none
## — because until now there was one raid and one expedition, so there was nothing to chain
## TO. This walks it: a fresh player is locked out of everything downstream, and each piece
## opens only its own next step.
##
## The failure this exists to catch is the quiet one: an unlockFlag renamed on one side of a
## link, which no single-piece test would notice and which would strand the player with
## content they can see and never reach.

const RaidLogic = preload("res://src/systems/raid_logic.gd")
const ExpeditionLogic = preload("res://src/systems/expedition_logic.gd")

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var db: Node = root.get_node("DB")
	var profile = LearningProfile.new({}, db)

	var first: Dictionary = db.raid("sushi_prep")
	var second: Dictionary = db.raid("gate_trial")
	var expedition: Dictionary = db.expedition("forest_lunchbox")
	var summit: Dictionary = db.expedition("pass_summit")
	check_true("the chain's four pieces are authored",
		not first.is_empty() and not second.is_empty()
		and not expedition.is_empty() and not summit.is_empty())
	if first.is_empty() or second.is_empty() or expedition.is_empty() or summit.is_empty():
		_finish()
		return

	# --- a brand-new player is behind every gate ---
	check_true("a new player cannot start the first raid (needs its lesson flag)",
		not RaidLogic.can_start(profile, first))
	check_true("a new player cannot start the second raid",
		not RaidLogic.can_start(profile, second))
	check_true("a new player has not unlocked the expedition",
		not ExpeditionLogic.unlock_ready(profile, expedition))

	# --- the lesson flag opens raid one, and ONLY raid one ---
	for flag in first.get("requiredFlags", []):
		profile.set_flag(String(flag), true)
	check_true("clearing its lesson opens the first raid",
		RaidLogic.can_start(profile, first))
	check_true("the first raid's lesson does NOT open the second",
		not RaidLogic.can_start(profile, second))
	check_true("the first raid's lesson does NOT open the expedition",
		not ExpeditionLogic.unlock_ready(profile, expedition))

	# --- finishing raid one opens both the next raid and the expedition ---
	#
	# Actually run the raid to completion rather than just setting its unlock flags. The
	# expedition gate checks BOTH: the flag AND the raid's recorded stage (requiredRaidIds).
	# Setting flags alone left the stage unset and the gate shut, which is exactly the
	# half-satisfied state a player could never reach but a lazy test can.
	# The raid has a recall gate in front of its boss: start -> recall-cleared -> complete.
	# Skipping mark_recall_cleared leaves complete_boss a no-op, which is the raid correctly
	# refusing to pay out for a fight the player never earned. Walk the real sequence.
	var inv: Node = root.get_node("Inv")
	RaidLogic.start(profile, first)
	RaidLogic.mark_recall_cleared(profile, "sushi_prep")
	RaidLogic.complete_boss(profile, db, inv, first)
	check_true("the first raid records itself complete",
		String(RaidLogic.progress(profile, "sushi_prep").get("stage", "")) == "complete")
	check_true("finishing the first raid opens the second (%s)"
		% str(second.get("requiredFlags", [])),
		RaidLogic.can_start(profile, second))
	check_true("finishing the first raid arms the expedition gate",
		ExpeditionLogic.unlock_ready(profile, expedition))
	check_true("but NOT the summit expedition, which is two links further out",
		not ExpeditionLogic.unlock_ready(profile, summit))

	# --- finishing raid two opens the summit expedition ---
	#
	# This is the link the second raid was missing. `gate_trial` shipped with an
	# unlockFlag that nothing anywhere consumed, so the deepest node of the chain paid
	# out into nothing and the arc simply stopped. Walking it here is what keeps a
	# future raid from being authored the same way.
	RaidLogic.start(profile, second)
	RaidLogic.mark_recall_cleared(profile, "gate_trial")
	RaidLogic.complete_boss(profile, db, inv, second)
	check_true("the second raid records itself complete",
		String(RaidLogic.progress(profile, "gate_trial").get("stage", "")) == "complete")
	check_true("finishing the second raid arms the summit expedition (%s)"
		% str(summit.get("requiredFlags", [])),
		ExpeditionLogic.unlock_ready(profile, summit))

	# --- every flag a piece hands out is one some other piece asks for ---
	# A renamed flag on either side is invisible to the pieces themselves and strands the
	# player in front of content they can see and cannot reach.
	var handed: Dictionary = {}
	for raid_id in db.raids:
		for flag in (db.raids[raid_id] as Dictionary).get("unlockFlags", []):
			handed[String(flag)] = String(raid_id)
	var wanted: Dictionary = {}
	for raid_id in db.raids:
		for flag in (db.raids[raid_id] as Dictionary).get("requiredFlags", []):
			wanted[String(flag)] = String(raid_id)
	for exp_id in db.expeditions:
		for flag in (db.expeditions[exp_id] as Dictionary).get("requiredFlags", []):
			wanted[String(flag)] = String(exp_id)

	var orphans: Array[String] = []
	for flag in wanted:
		# A flag may legitimately come from a lesson rather than from a raid; those are the
		# "*_first_lesson" flags the teacher NPCs set. Anything else must have a source.
		if handed.has(flag) or String(flag).ends_with("_first_lesson"):
			continue
		orphans.append("%s (wanted by %s)" % [flag, wanted[flag]])
	check_true("every required flag has something that grants it (%s)"
		% ("none orphaned" if orphans.is_empty() else ", ".join(PackedStringArray(orphans))),
		orphans.is_empty())

	# --- raids that unlock an expedition must name one that exists ---
	var bad_links: Array[String] = []
	for raid_id in db.raids:
		for exp_id in (db.raids[raid_id] as Dictionary).get("unlockExpeditionIds", []):
			if db.expedition(String(exp_id)).is_empty():
				bad_links.append("%s -> %s" % [raid_id, exp_id])
	check_true("no raid unlocks an expedition that does not exist (%s)"
		% ("all links resolve" if bad_links.is_empty() else ", ".join(PackedStringArray(bad_links))),
		bad_links.is_empty())

	# --- and every authored expedition has a door into it ---
	#
	# The generic checks above only prove the DATA agrees with itself. An expedition can
	# still be perfectly wired and completely unreachable, because the thing that opens
	# one is a gate node placed in a region scene — and nothing in the data knows whether
	# that node exists. This walks the scenes and asks.
	var gated: Dictionary = {}
	for scene_path in _region_scenes():
		var text := FileAccess.get_file_as_string(scene_path)
		if not text.contains("expedition_gate.gd"):
			continue
		for line in text.split("
"):
			var trimmed := String(line).strip_edges()
			if trimmed.begins_with("expedition_id = \""):
				gated[trimmed.trim_prefix("expedition_id = \"").trim_suffix("\"")] = scene_path
	var unreachable: Array[String] = []
	for exp_id in db.expeditions:
		if not gated.has(String(exp_id)):
			unreachable.append(String(exp_id))
	check_true("every expedition has a gate placed in a region (%s)"
		% ("all reachable" if unreachable.is_empty()
			else "no way in: " + ", ".join(PackedStringArray(unreachable))),
		unreachable.is_empty())
	_finish()


func _region_scenes() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://src/scenes")
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			out.append("res://src/scenes/%s" % file)
	return out


func check_true(label: String, condition: bool) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)


func _finish() -> void:
	if failures == 0:
		print("PASS — the staged content chain holds from lesson to expedition.")
		quit(0)
	else:
		print("FAIL — %d check(s) failed." % failures)
		quit(1)
