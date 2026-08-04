extends SceneTree
## Combat action-bar UX: an unarmed fresh player keeps Basic Attack and the
## weapon-free starter skills without exposing unusable Strike.

var failures := 0


func _logical_ui_rect() -> Rect2:
	var settings: Node = root.get_node("Settings")
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 640)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 360)))
	return Rect2(Vector2.ZERO, (base / maxf(settings.ui_scale, 0.1)).floor())


func _initialize() -> void:
	await process_frame
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
	var bus: Node = root.get_node("Bus")
	var inv: Node = root.get_node("Inv")
	inv.reset()
	inv.add("rice_ball", 1)
	inv.add("bamboo_tonic", 1)
	inv.add("stone_soup", 1)
	learning.profile.unlock_card("kana-a")
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/combat_panel.gd"))
	root.add_child(panel)
	await process_frame
	# The always-on HUD layers must get out of the fight panel's way: they sit under its
	# dim backdrop and read as overlap when hearts/coins/objectives bleed through.
	var hud := CanvasLayer.new()
	hud.set_script(load("res://src/ui/hud_layer.gd"))
	root.add_child(hud)
	var objective := CanvasLayer.new()
	objective.set_script(load("res://src/ui/objective_hud.gd"))
	root.add_child(objective)
	var prompt := CanvasLayer.new()
	prompt.set_script(load("res://src/ui/context_prompt.gd"))
	root.add_child(prompt)
	await process_frame
	check_true("world HUD layers start visible",
		hud.visible and objective.visible and prompt.visible)
	bus.combat_started.emit(String(db.enemy_order[0]))
	await process_frame
	check_true("world HUD steps out of combat",
		not hud.visible and not objective.visible and not prompt.visible)

	var shell: Control = panel.find_child("CombatShell", true, false)
	var actions: Control = panel.find_child("CombatActions", true, false)
	var energy: Label = panel.find_child("CombatEnergy", true, false)
	var intent: Label = panel.find_child("EnemyIntent", true, false)
	var enemy_label: Label = panel.get("_enemy_label")
	var end_turn: Button = panel.find_child("EndTurn", true, false)
	var continue_btn: Button = panel.get("_continue_btn")
	var flee: Button = panel.find_child("Flee", true, false)
	check_true("combat opens", bool(panel.get("_active")))
	var viewport_rect := _logical_ui_rect()
	var shell_rect := shell.get_global_rect()
	check_true("combat shell stays inside the scaled UI canvas (%s)" % shell_rect,
		viewport_rect.encloses(shell_rect))
	# The reported cut-off: the green HP bar and turn buttons must be pinned below
	# the scroll area, fully on screen — never scrolled below the fold.
	var hp_bar: ProgressBar = panel.get("_player_hp_bar")
	var end_turn_control: Button = end_turn
	check_true("player HP bar is pinned outside the scroll area",
		hp_bar != null and not _inside_scroll(hp_bar))
	check_true("player HP bar is fully visible (%s)" % hp_bar.get_global_rect(),
		viewport_rect.encloses(hp_bar.get_global_rect()))
	check_true("turn controls are fully visible",
		viewport_rect.encloses(end_turn_control.get_global_rect()))
	check_eq("combat groups item stacks behind one compact action", actions.get_child_count(), 4)
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
	var item_button := _find_button(actions, "Items (3)") as MenuButton
	var item_popup := item_button.get_popup()
	var rice_id := _popup_item_id(item_popup, "Rice Ball x1")
	check_true("healing item becomes usable inside the Items menu",
		item_button != null and rice_id >= 0
		and not item_popup.is_item_disabled(item_popup.get_item_index(rice_id)))
	item_popup.id_pressed.emit(rice_id)
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
	check_true("world HUD returns after combat",
		hud.visible and objective.visible and prompt.visible)
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
	var second_items := _find_button(actions, "Items (2)") as MenuButton
	var second_popup := second_items.get_popup()
	var tonic_id := _popup_item_id(second_popup, "Bamboo Breeze Tonic x1")
	check_true("Energy tonic becomes usable after Energy is spent",
		second_items != null and tonic_id >= 0
		and not second_popup.is_item_disabled(second_popup.get_item_index(tonic_id)))
	second_popup.id_pressed.emit(tonic_id)
	await process_frame
	check_eq("Energy tonic restores the turn budget", second_encounter.energy, 5)
	check_eq("Energy tonic consumes exactly one", inv.count("bamboo_tonic"), 0)
	check_true("Energy tonic feedback names its distinct effect",
		(panel.get("_feedback") as Label).text.contains("Energy"))
	continue_btn.pressed.emit()
	await process_frame
	end_turn.pressed.emit()
	await process_frame
	continue_btn.pressed.emit()
	await process_frame
	var soup_menu := _find_button(actions, "Items (1)") as MenuButton
	var soup_popup := soup_menu.get_popup()
	var soup_id := _popup_item_id(soup_popup, "Stone Soup x1")
	var soup_index := soup_popup.get_item_index(soup_id)
	check_true("hybrid meal is exposed with both effects",
		soup_menu != null and soup_id >= 0
		and soup_popup.get_item_tooltip(soup_index).contains("Restores 15 HP")
		and soup_popup.get_item_tooltip(soup_index).contains("+4 DEF for 4 rounds"))
	soup_popup.id_pressed.emit(soup_id)
	await process_frame
	check_eq("hybrid meal consumes exactly one", inv.count("stone_soup"), 0)
	check_eq("hybrid meal updates visible defense", second_encounter.effective_def(), 6)
	check_true("hybrid feedback names its applied status",
		(panel.get("_feedback") as Label).text.contains("DEF"))
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
	inv.add("fire_oil", 1)
	bus.combat_started.emit(String(db.enemy_order[0]))
	await process_frame
	var item_encounter: CombatEncounter = panel.get("_encounter")
	item_encounter.enemy_hp = 20
	panel.call("_render_bars")
	panel.call("_build_actions")
	var attack_menu := _find_button(actions, "Items (1)") as MenuButton
	var attack_popup := attack_menu.get_popup()
	var oil_id := _popup_item_id(attack_popup, "Fire Oil Flask x1")
	var oil_index := attack_popup.get_item_index(oil_id)
	check_true("damage item is exposed with its honest effect",
		attack_menu != null and oil_id >= 0
		and attack_popup.get_item_tooltip(oil_index).contains("Deals 25 damage"))
	attack_popup.id_pressed.emit(oil_id)
	await process_frame
	check_eq("damage item consumes exactly one", inv.count("fire_oil"), 0)
	check_eq("damage item can reduce enemy HP to zero", item_encounter.enemy_hp, 0)
	check_true("damage item feedback reports actual damage",
		(panel.get("_feedback") as Label).text.contains("dealt 20 damage"))
	check_true("killing item exposes the normal continue path",
		continue_btn.visible and continue_btn.text == "Continue")
	continue_btn.pressed.emit()
	await process_frame
	check_true("continuing a damage-item victory closes combat", not bool(panel.get("_active")))

	# Fighting IS the review session, so a missed rune has to teach: say the word
	# out loud and show how it is read. Combat was silent even after 1,311 cards
	# gained native audio, and a miss only showed the glyph the player just failed
	# to recognise.
	# Unlock a lesson whose cards all shipped with deck audio, then draw until one
	# of them comes up, so the playback assertion below actually runs instead of
	# quietly skipping on a silent authored kana card.
	learning.profile.unlock_lesson("travel-vocab-1")
	bus.combat_started.emit(String(db.enemy_order[0]))
	await process_frame
	var audio_node: Node = root.get_node("Audio")
	for attempt in 50:
		var drawn := String((panel.get("_current_card") as Dictionary).get("id", ""))
		if bool(audio_node.call("has_pronunciation", drawn)):
			break
		panel.call("_next_round")
		await process_frame
	var missed_card: Dictionary = panel.get("_current_card")
	var answer := String((panel.get("_challenge") as Dictionary).get("answer", ""))
	var wrong_btn: Button = null
	for child in (panel.get("_choices_box") as Control).get_children():
		if child is Button and (child as Button).text != answer:
			wrong_btn = child
			break
	check_true("a wrong rune is available to press", wrong_btn != null)
	if wrong_btn != null:
		wrong_btn.pressed.emit()
		await process_frame
		var feedback := (panel.get("_feedback") as Label).text
		check_true("a missed rune reveals the right answer", feedback.contains(answer))
		var reading := String(missed_card.get("reading", "")).strip_edges()
		if not reading.is_empty():
			check_true("a missed rune also shows how it is read (%s)" % reading,
				feedback.contains(reading))
		var card_id := String(missed_card.get("id", ""))
		check_true("a card with a recording was drawn to test playback (%s)" % card_id,
			bool(audio_node.call("has_pronunciation", card_id)))
		check_true("combat plays the card's recording on the reveal",
			(audio_node.get("_player") as AudioStreamPlayer).stream != null)
		# Once heard is rarely enough, and the replay must not exist before the
		# answer is shown or it would simply read the answer out.
		var listen: Button = panel.find_child("Listen", true, false)
		check_true("a voiced card offers a replay after the reveal",
			listen != null and listen.visible)
		check_true("replay is reachable by keyboard and controller",
			listen != null and listen.focus_mode == Control.FOCUS_ALL)
		listen.pressed.emit()
		await process_frame
		check_true("replay plays the recording again",
			(audio_node.get("_player") as AudioStreamPlayer).stream != null)
		panel.call("_next_round")
		await process_frame
		check_true("replay disappears once the next answer is hidden", not listen.visible)
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


func _popup_item_id(popup: PopupMenu, label: String) -> int:
	for index in popup.item_count:
		if popup.get_item_text(index) == label:
			return popup.get_item_id(index)
	return -1


func _inside_scroll(c: Control) -> bool:
	var n := c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


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
