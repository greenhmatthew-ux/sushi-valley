extends SceneTree
## Input-copy contract: prompts follow the last meaningful device, use the real
## InputMap, and the controller's world actions do not also open Hub domains.

var failures := 0


func _initialize() -> void:
	await process_frame
	var hints: Node = root.get_node("InputHints")

	hints.set_input_method(hints.KEYBOARD_MOUSE)
	check_eq("keyboard interaction uses the authored E binding",
		hints.primary_label("interact"), "E")
	var keyboard_close: String = hints.joined_labels(["open_menu", "ui_cancel"])
	check_true("keyboard Hub copy names both toggle and Back",
		keyboard_close.contains("I") and keyboard_close.contains("Esc"))
	check_eq("keyboard meaning peek names Tab", hints.primary_label("peek_english"), "Tab")

	hints.set_input_method(hints.GAMEPAD)
	check_eq("controller interaction uses A", hints.primary_label("interact"), "A")
	check_eq("controller Hub toggle uses Menu", hints.primary_label("open_menu"), "Menu")
	check_eq("controller Back uses B", hints.primary_label("ui_cancel"), "B")
	check_eq("controller meaning peek uses LB", hints.primary_label("peek_english"), "LB")
	check_eq("previous Hub domain uses LB", hints.primary_label("tab_previous"), "LB")
	check_eq("next Hub domain uses RB", hints.primary_label("tab_next"), "RB")

	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_E
	hints.observe_event(key)
	check_eq("a pressed key returns prompts to keyboard", hints.input_method, hints.KEYBOARD_MOUSE)
	var stick := InputEventJoypadMotion.new()
	stick.axis_value = 0.7
	hints.observe_event(stick)
	check_eq("meaningful stick motion selects controller prompts", hints.input_method, hints.GAMEPAD)
	stick.axis_value = 0.1
	hints.set_input_method(hints.KEYBOARD_MOUSE)
	hints.observe_event(stick)
	check_eq("stick drift does not steal the prompt", hints.input_method, hints.KEYBOARD_MOUSE)

	check_true("Attack's X button no longer opens Journal",
		_has_joy_button("attack", 2) and not _has_any_joy_button("open_journal"))
	check_true("Menu no longer also opens Skills",
		_has_joy_button("open_menu", 6) and not _has_any_joy_button("open_skills"))
	check_true("Map no longer relies on the reserved Guide button",
		not _has_any_joy_button("open_map"))
	await _surface_copy_follows_device(hints)

	print("")
	print("PASS — visible input copy follows conflict-free keyboard and controller routes." \
		if failures == 0 else "FAIL — %d input-hint check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func _surface_copy_follows_device(hints: Node) -> void:
	hints.set_input_method(hints.GAMEPAD)
	var surfaces := [
		["res://src/ui/inventory_panel.gd", ["LB", "RB", "Menu", "B"]],
		["res://src/ui/shop_panel.gd", ["B"]],
		["res://src/ui/crafting_panel.gd", ["B"]],
		["res://src/ui/notebook_panel.gd", ["LB", "B"]],
	]
	for spec in surfaces:
		var panel := CanvasLayer.new()
		panel.set_script(load(String(spec[0])))
		root.add_child(panel)
		await process_frame
		var label: Label = panel.find_child("InputHint", true, false)
		var correct := label != null
		for expected in spec[1]:
			correct = correct and label.text.contains(String(expected))
		check_true("%s exposes controller-correct copy (%s)" % [
			String(spec[0]).get_file(), label.text if label != null else "missing"], correct)
		panel.queue_free()
		await process_frame

	var dialogue := CanvasLayer.new()
	dialogue.set_script(load("res://src/ui/dialogue_box.gd"))
	root.add_child(dialogue)
	await process_frame
	root.get_node("Bus").dialogue_open.emit("Hana", ["こんにちは|Hello"])
	await process_frame
	var dialogue_hint: Label = dialogue.find_child("InputHint", true, false)
	check_true("dialogue names the controller advance action",
		dialogue_hint != null and dialogue_hint.text.contains("[A]")
		and dialogue_hint.text.contains("close"))
	dialogue.call("_close")
	dialogue.queue_free()
	await process_frame

	hints.set_input_method(hints.KEYBOARD_MOUSE)
	var notebook := CanvasLayer.new()
	notebook.set_script(load("res://src/ui/notebook_panel.gd"))
	root.add_child(notebook)
	await process_frame
	var keyboard_hint: Label = notebook.find_child("InputHint", true, false)
	check_true("adopted copy returns to keyboard without rebuilding the surface",
		keyboard_hint != null and keyboard_hint.text.contains("Tab")
		and keyboard_hint.text.contains("Esc"))
	notebook.queue_free()
	await process_frame


func _has_any_joy_button(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return true
	return false


func _has_joy_button(action: String, index: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton \
				and (event as InputEventJoypadButton).button_index == index:
			return true
	return false


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
