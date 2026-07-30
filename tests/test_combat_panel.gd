extends SceneTree
## Combat action-bar UX at the base 640x360 viewport: an unarmed fresh player keeps
## Basic Attack and the weapon-free starter skills without exposing unusable Strike.

var failures := 0


func _initialize() -> void:
	await process_frame
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
	var bus: Node = root.get_node("Bus")
	var inv: Node = root.get_node("Inv")
	inv.reset()
	inv.add("rice_ball", 1)
	learning.profile.unlock_card("kana-a")
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/combat_panel.gd"))
	root.add_child(panel)
	await process_frame
	bus.combat_started.emit(String(db.enemy_order[0]))
	await process_frame

	var shell: Control = panel.find_child("CombatShell", true, false)
	var actions: Control = panel.find_child("CombatActions", true, false)
	var energy: Label = panel.find_child("CombatEnergy", true, false)
	var end_turn: Button = panel.find_child("EndTurn", true, false)
	var flee: Button = panel.find_child("Flee", true, false)
	check_true("combat opens", bool(panel.get("_active")))
	var viewport_rect := root.get_viewport().get_visible_rect()
	var shell_rect := shell.get_global_rect()
	check_true("combat shell stays inside the 640x360 viewport (%s)" % shell_rect,
		viewport_rect.encloses(shell_rect))
	check_eq("unarmed combat also shows a held healing item", actions.get_child_count(), 4)
	check_eq("Basic Attack exposes its real Energy cost",
		(actions.get_child(0) as Button).text, "Basic · 1E")
	check_true("combat HUD shows Energy and Speed",
		energy.text.contains("Energy 5/5") and energy.text.contains("SPD"))
	check_true("combat HUD names the selected weapon", energy.text.contains("Unarmed"))
	check_true("the player can explicitly end a full turn", end_turn.visible)
	check_true("the player can leave without pretending to win", flee.visible)
	check_true("weapon-gated Strike is not a fake action",
		_find_button(actions, "Strike") == null)
	var encounter: CombatEncounter = panel.get("_encounter")
	encounter.player_hp = 5
	panel.call("_build_actions")
	var item_button := _find_button(actions, "Rice Ball x1")
	check_true("healing item becomes usable when hurt", item_button != null and not item_button.disabled)
	item_button.pressed.emit()
	await process_frame
	check_eq("combat item consumes exactly one", inv.count("rice_ball"), 0)
	check_true("combat item pauses for readable feedback", bool(panel.get("_answered")))
	check_true("combat item improves HP without an enemy interrupt", encounter.player_hp > 5)
	check_eq("combat item spends no Energy", encounter.energy, 5)
	var after_item := encounter.player_hp
	end_turn.pressed.emit()
	await process_frame
	check_true("enemy responds only after End Turn", encounter.player_hp < after_item)
	var outcomes: Array[bool] = []
	bus.combat_ended.connect(func(victory: bool): outcomes.append(victory), CONNECT_ONE_SHOT)
	flee.pressed.emit()
	await process_frame
	check_true("Flee closes combat and resumes the world",
		not bool(panel.get("_active")) and not paused)
	check_eq("Flee reports no victory rewards", outcomes, [false])
	inv.add("wooden_katana", 1)
	check_true("test weapon equips", inv.equip("wooden_katana"))
	bus.combat_started.emit(String(db.enemy_order[0]))
	await process_frame
	check_true("combat HUD uses the actual equipped weapon",
		energy.text.contains("Wooden Katana"))
	check_true("Flee returns on the next encounter", flee.visible)

	panel.call("_finish", false, "")
	inv.reset()
	panel.queue_free()
	await process_frame
	_finish()


func _find_button(parent: Control, label: String) -> Button:
	for child in parent.get_children():
		if child is Button and (child as Button).text == label:
			return child
	return null


func _finish() -> void:
	print("")
	print("PASS — combat actions are usable and viewport-safe." if failures == 0 \
		else "FAIL — %d combat-panel check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
