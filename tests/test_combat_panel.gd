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
	inv.add("bamboo_tonic", 1)
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
	var intent: Label = panel.find_child("EnemyIntent", true, false)
	var enemy_label: Label = panel.get("_enemy_label")
	var end_turn: Button = panel.find_child("EndTurn", true, false)
	var flee: Button = panel.find_child("Flee", true, false)
	check_true("combat opens", bool(panel.get("_active")))
	var viewport_rect := root.get_viewport().get_visible_rect()
	var shell_rect := shell.get_global_rect()
	check_true("combat shell stays inside the 640x360 viewport (%s)" % shell_rect,
		viewport_rect.encloses(shell_rect))
	check_eq("unarmed combat shows both supported item families", actions.get_child_count(), 5)
	check_eq("Basic Attack exposes its real Energy cost",
		(actions.get_child(0) as Button).text, "Basic · 1E")
	check_true("combat HUD shows Energy and Speed",
		energy.text.contains("Energy 5/5") and energy.text.contains("SPD"))
	check_eq("combat HUD exposes a bounded enemy attack intent", intent.text,
		"[!] Attack 4-6 HP")
	check_true("enemy intent explains when the hit will land",
		intent.tooltip_text.contains("after End Turn"))
	check_true("combat HUD names the selected weapon", energy.text.contains("Unarmed"))
	check_true("the player can explicitly end a full turn", end_turn.visible)
	check_true("the player can leave without pretending to win", flee.visible)
	check_true("weapon-gated Strike is not a fake action",
		_find_button_prefix(actions, "Strike") == null)
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
	var second_encounter: CombatEncounter = panel.get("_encounter")
	second_encounter.spend_and_resolve("mi", "mi")
	panel.call("_build_actions")
	var tonic_button := _find_button(actions, "Bamboo Breeze Tonic x1")
	check_true("Energy tonic becomes usable after Energy is spent",
		tonic_button != null and not tonic_button.disabled)
	tonic_button.pressed.emit()
	await process_frame
	check_eq("Energy tonic restores the turn budget", second_encounter.energy, 5)
	check_eq("Energy tonic consumes exactly one", inv.count("bamboo_tonic"), 0)
	check_true("Energy tonic feedback names its distinct effect",
		(panel.get("_feedback") as Label).text.contains("Energy"))
	second_encounter.player_hp = 5
	var focus: Dictionary = db.ability("focus")
	second_encounter.spend_and_resolve("mi", "mi", focus)
	panel.call("_build_actions")
	var focus_button := _find_button_prefix(actions, "Focus")
	check_true("used cooldown action is visibly unavailable",
		focus_button != null and focus_button.disabled and "CD 1" in focus_button.text)
	check_true("cooldown action tooltip exposes both cadence rules",
		focus_button.tooltip_text.contains("1 use per turn")
		and focus_button.tooltip_text.contains("Cooldown: 1 full turn"))
	second_encounter.energy = 5
	second_encounter.spend_and_resolve("mi", "mi", db.ability("riposte"))
	panel.call("_render_bars")
	check_true("combat HUD exposes an armed Counter", energy.text.contains("COUNTER RET8"))
	check_eq("Counter guard updates the visible enemy intent", intent.text,
		"[!] Attack 0-0 HP")
	second_encounter.full_parry_ready = true
	panel.call("_render_bars")
	check_true("full Parry intent explains the zero-damage preview",
		intent.tooltip_text.contains("Full Parry blocks this hit"))
	second_encounter.pending_counter_damage = 0
	second_encounter.full_parry_ready = false
	second_encounter.shield = 0
	second_encounter.timed_debuffs["atk"] = {"value": 5, "rounds": 3}
	panel.call("_render_bars")
	check_true("enemy HUD exposes active debuffs", enemy_label.text.contains("ATK-5/3r"))
	check_eq("ATK debuff updates the visible enemy intent", intent.text,
		"[!] Attack 1-1 HP")
	second_encounter.timed_debuffs.erase("atk")
	second_encounter.timed_buffs["def"] = {"value": 4, "rounds": 3}
	panel.call("_render_bars")
	check_true("combat HUD exposes active timed buffs", energy.text.contains("DEF+4/3r"))
	check_eq("timed DEF updates the visible enemy intent", intent.text,
		"[!] Attack 3-4 HP")
	second_encounter.timed_buffs.erase("def")
	second_encounter.shield = 5
	panel.call("_render_bars")
	check_eq("enemy intent updates for Guard instead of lying", intent.text,
		"[!] Attack 0-1 HP")

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


func _find_button_prefix(parent: Control, prefix: String) -> Button:
	for child in parent.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
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
