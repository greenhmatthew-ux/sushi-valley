extends SceneTree
## Player-menu UX contract: real Character/Bag domains, honest stats, modal safety,
## and controller routes through the InputMap.

var failures: int = 0


func _initialize() -> void:
	await process_frame
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/inventory_panel.gd"))
	root.add_child(panel)
	await process_frame

	var menu: Control = panel.find_child("PlayerMenuRoot", true, false)
	var shell: Control = panel.find_child("PlayerMenuShell", true, false)
	var character: Control = panel.find_child("CharacterView", true, false)
	var skills: Control = panel.find_child("SkillsView", true, false)
	var bag: Control = panel.find_child("BagView", true, false)
	var stats: Label = panel.find_child("StatsSummary", true, false)
	var slots: Control = panel.find_child("EquipmentSlots", true, false)
	check_true("player menu builds", menu != null)
	check_true("menu starts closed", menu != null and not menu.visible)

	panel.call("_set_open", true)
	await process_frame
	check_true("opening pauses the world", paused)
	check_true("menu opens to a real domain", bag.visible and not character.visible)
	check_true("character, skills, and bag tabs exist",
		panel.find_child("CharacterTab", true, false) != null
		and panel.find_child("SkillsTab", true, false) != null
		and panel.find_child("BagTab", true, false) != null)
	var viewport_rect := root.get_viewport().get_visible_rect()
	check_true("menu shell stays inside the 640x360 viewport",
		viewport_rect.encloses(shell.get_global_rect()))

	panel.call("_set_tab", "character")
	check_true("character tab replaces bag content", character.visible and not bag.visible)
	check_true("character explains learning-derived stats",
		stats.text.contains("Japanese study raises your base stats"))
	check_eq("all authored equipment slots are visible",
		slots.get_child_count(), InventoryLogic.EQUIPMENT_SLOTS.size())

	panel.call("_set_tab", "skills")
	check_true("skills tab replaces character content", skills.visible and not character.visible)
	var summary: Label = panel.find_child("SkillsSummary", true, false)
	var skill_cards: Control = panel.find_child("SkillCards", true, false)
	check_true("skills tab states the six-slot loadout", summary.text.contains("/ 6"))
	check_eq("fresh profile exposes the three real starter skills", skill_cards.get_child_count(), 3)

	panel.call("_set_open", false)
	paused = true
	var blocked_event := InputEventAction.new()
	blocked_event.action = "open_menu"
	blocked_event.pressed = true
	panel.call("_unhandled_input", blocked_event)
	check_true("menu cannot stack over another paused modal", not menu.visible)
	paused = false

	check_true("controller can interact", _has_joy_button("interact", 0))
	check_true("controller can open settings", _has_joy_button("open_settings", 4))
	check_true("controller can open the player menu", _has_joy_button("open_menu", 6))
	check_true("controller can open the notebook", _has_joy_button("open_notebook", 3))

	panel.queue_free()
	await process_frame
	check_true("Notebook also rejects paused modal stacking",
		await _panel_rejects_paused_open(
			"res://src/ui/notebook_panel.gd", "open_notebook"))
	check_true("Settings also rejects paused modal stacking",
		await _panel_rejects_paused_open(
			"res://src/ui/settings_panel.gd", "open_settings"))
	_finish()


func _has_joy_button(action: String, button_index: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton \
				and (event as InputEventJoypadButton).button_index == button_index:
			return true
	return false


func _panel_rejects_paused_open(script_path: String, action: String) -> bool:
	var modal := CanvasLayer.new()
	modal.set_script(load(script_path))
	root.add_child(modal)
	await process_frame
	paused = true
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	modal.call("_unhandled_input", event)
	var rejected := not bool(modal.get("_open"))
	paused = false
	modal.queue_free()
	await process_frame
	return rejected


func _finish() -> void:
	print("")
	print(("PASS — Player menu domains, modal safety, and controller routes hold."
		if failures == 0 else "FAIL — %d player-menu check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
