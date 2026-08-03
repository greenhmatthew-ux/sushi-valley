extends "res://src/entities/teacher_npc.gd"
## A teacher who also runs a Raid — Hana's role in the TS build (ValleyScene's
## talkToHana + beginSushiPrepRaid, ported).
##
## Until the player clears this teacher's first lesson they are just a teacher.
## After that, talking to them offers the Raid briefing instead: focused recall,
## then the boss encounter, then rewards — all decided by the pure RaidLogic.
## Once the (non-repeatable) Raid completes, they go back to being a teacher, so
## reviews never disappear behind finished content.

const RaidLogic = preload("res://src/systems/raid_logic.gd")

## Raid id from data/game/raids.json that this NPC offers.
@export var raid_id: String = ""
## Flag set the first time a session with this teacher ends with a correct
## answer. Bridges the TS 'hana_first_lesson' gate (set on the first correct
## recall with Hana) into the ported teacher flow, keeping raids.json's
## requiredFlags and existing TS saves valid as-is.
@export var first_lesson_flag: String = ""


func _run_interaction() -> void:
	var raid: Dictionary = DB.raid(raid_id) if not raid_id.is_empty() else {}
	if not raid.is_empty() and RaidLogic.can_start(Learning.profile, raid):
		Bus.npc_talked.emit(npc_id)
		await _run_raid(raid)
		Bus.hud_refresh.emit()
		return
	await super._run_interaction()


func _run_session(lesson: String) -> Array:
	var res: Array = await super._run_session(lesson)
	# TS set the gate on the first correct recall with Hana, not on meeting her —
	# the raid asks for proven words, not a handshake.
	if not first_lesson_flag.is_empty() and int(res[1]) > 0 \
			and not Learning.get_flag(first_lesson_flag):
		Learning.set_flag(first_lesson_flag)
	return res


## Briefing -> focused recall -> boss -> rewards. Stage order and every message
## is the TS flow; RaidLogic owns the transitions so a quit at any point resumes
## exactly where the save says.
func _run_raid(raid: Dictionary) -> void:
	var prog := RaidLogic.progress(Learning.profile, raid_id)
	var briefing: Array[String] = []
	if String(prog.get("stage", "")) == "recall-cleared":
		briefing.append("The food words are set. The Pantry Oni is still in the trial kitchen.")
		briefing.append("Ready to finish the Sushi Prep Raid?")
	else:
		briefing.append("I have a real kitchen trial for you: the Sushi Prep Raid.")
		briefing.append("Clear a focused food-word recall, then protect the prepared rice from a Pantry Oni.")
	Bus.dialogue_open.emit(speaker, briefing)
	await Bus.dialogue_closed

	var started := RaidLogic.start(Learning.profile, raid)
	if started.is_empty():
		Bus.toast.emit("Complete %s's first lesson before entering this Raid." % speaker)
		return

	if String(started.get("stage", "")) != "recall-cleared":
		# Focused recall: 3 prompts from the raid's lesson, practice allowed. The TS
		# clear bar is at least one correct answer, not a perfect run — the raid
		# wants the words touched under pressure, not gated behind mastery.
		Bus.learn_open.emit(String(raid.get("learningFocus", "")), 3, true)
		var res: Array = await Bus.learn_closed   # [attempted, correct, cancelled]
		if bool(res[2]):
			return
		if int(res[0]) == 0 or int(res[1]) == 0:
			Bus.toast.emit("Raid recall not cleared. Review Food & Drink, then ask %s again." % speaker)
			return
		RaidLogic.mark_recall_cleared(Learning.profile, raid_id)
		Bus.toast.emit("Food recall cleared — Pantry Oni encounter started.")

	await _launch_boss(raid)


func _launch_boss(raid: Dictionary) -> void:
	Bus.combat_started.emit(String(raid.get("encounterId", "")))
	var victory: bool = await Bus.combat_ended
	if not victory:
		# Progress stays at recall-cleared: ask again and go straight back in.
		return
	var summary := RaidLogic.complete_boss(Learning.profile, DB, Inv, raid)
	if not summary.is_empty():
		Bus.toast.emit(summary)
