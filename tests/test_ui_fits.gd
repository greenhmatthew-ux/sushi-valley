extends SceneTree
## GUARD: nothing the player has to read is cut off.
##
##   godot --headless --path . --script res://tests/test_ui_fits.gd
##
## Every panel is built in code against a 640x360 viewport, so a long item name,
## a nine-word answer, or an enemy with three active effects can quietly overflow
## its control. Two of those surfaces used to hide it deliberately by clipping —
## which is the worst version, because the player is asked to choose between
## answers they can only half read.
##
## This measures the real thing: it lays each panel out, then asks the control's
## own font how much room its text actually needs, wrapped to the width it was
## given, and fails when the control is smaller than that. It also fails on any
## control that truncates, and on anything pushed outside the viewport.

var failures: int = 0
var _checked := 0


func _initialize() -> void:
	await process_frame
	var db: Node = root.get_node("DB")
	var bus: Node = root.get_node("Bus")
	var learning: Node = root.get_node("Learning")
	var inv: Node = root.get_node("Inv")

	# Content that is realistically long, so the panels are measured under load
	# rather than against the shortest thing they could be showing.
	learning.profile.unlock_lesson("travel-vocab-1")
	learning.profile.unlock_lesson("common-words-1")
	inv.reset()
	for item_id in ["rice_ball", "bamboo_tonic", "stone_soup", "straw_hat"]:
		inv.add(item_id, 2)
	# Measuring the panels means answering questions, which earns XP and writes it
	# to the shared profile. This is a layout test; it should not move progress.
	var xp_before: int = int(learning.profile.data["stats"]["xp"])

	await _check_combat(bus, db)
	await _check_recall(bus)
	await _check_menu()
	await _check_notebook()

	print("")
	print("  ..   measured %d text controls across four panels" % _checked)
	inv.reset()
	learning.profile.data["stats"]["xp"] = xp_before
	learning.profile.save()
	_finish()


func _check_combat(bus: Node, db: Node) -> void:
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/combat_panel.gd"))
	root.add_child(panel)
	await process_frame
	# A starter enemy: with no player node in this harness the base 12 HP applies,
	# and a late-game enemy simply one-shots it before any rune round is drawn.
	bus.combat_started.emit(String(db.enemy_order[0]))
	await process_frame
	await process_frame
	_audit(panel, "combat")
	_choices_are_all_on_screen(panel, "combat")

	# The name row still has to survive the wordiest enemy in the game plus a full
	# status suffix, so drive it there directly rather than hoping a fight picks it.
	var enemy_label: Label = panel.get("_enemy_label")
	enemy_label.text = "%s · ATK -3, DEF -2 for 3 rounds" % _longest_enemy_name(db)
	await process_frame
	_audit(panel, "combat long enemy name")

	# And again after an answer, when the feedback line is at its longest.
	var choices: Control = panel.get("_choices_box")
	check_true("combat offers runes to measure the reveal with",
		choices != null and choices.get_child_count() > 0)
	if choices != null and choices.get_child_count() > 0:
		(choices.get_child(0) as Button).pressed.emit()
		await process_frame
		await process_frame
		_audit(panel, "combat reveal")
	panel.queue_free()
	await process_frame


func _check_recall(bus: Node) -> void:
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/recall_panel.gd"))
	root.add_child(panel)
	await process_frame
	bus.learn_open.emit("common-words-1", 1, true)
	await process_frame
	await process_frame
	_audit(panel, "recall")
	_choices_are_all_on_screen(panel, "recall")
	var choices: Control = panel.get("_choices_box")
	if choices != null and choices.get_child_count() > 0:
		(choices.get_child(0) as Button).pressed.emit()
		await process_frame
		_audit(panel, "recall reveal")
	panel.queue_free()
	await process_frame


func _check_menu() -> void:
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/inventory_panel.gd"))
	root.add_child(panel)
	await process_frame
	for tab in ["character", "skills", "bag", "quests"]:
		panel.call("_set_tab", tab)
		panel.call("_refresh")
		await process_frame
		_audit(panel, "menu/" + tab)
	panel.queue_free()
	await process_frame


func _check_notebook() -> void:
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/notebook_panel.gd"))
	root.add_child(panel)
	await process_frame
	panel.call("_set_open", true)
	await process_frame
	_audit(panel, "notebook")
	panel.call("_set_open", false)
	panel.queue_free()
	await process_frame


func _longest_enemy_name(db: Node) -> String:
	var best := ""
	for id in db.enemy_order:
		var enemy_name := String(db.enemy(String(id)).get("name", ""))
		if enemy_name.length() > best.length():
			best = enemy_name
	return best


## An answer you cannot see is one you cannot pick. `_audit` deliberately excuses
## anything inside a ScrollContainer, since scrolled content legitimately extends
## past its viewport — but that excuse must not cover the choices themselves. This
## caught the combat rune grid, whose bottom row sat below the scroll fold.
func _choices_are_all_on_screen(panel: Node, where: String) -> void:
	var box := panel.get("_choices_box") as Control
	if box == null or box.get_child_count() == 0:
		check_true("%s: has choices to check" % where, false)
		return
	var viewport := root.get_viewport().get_visible_rect()
	var hidden: Array[String] = []
	for child in box.get_children():
		var button := child as Button
		if button == null:
			continue
		var rect := button.get_global_rect()
		# Clipped by a scroll region, or off the screen entirely.
		var scroll := _scroll_ancestor(button)
		var clipped_away := scroll != null and not scroll.get_global_rect().encloses(rect)
		if clipped_away or not viewport.encloses(rect):
			hidden.append("%s %s" % [button.text.substr(0, 12), rect])
	check_true("%s: every answer is fully visible without scrolling (%s)"
		% [where, _sample(hidden)], hidden.is_empty())


## The nearest scroll ancestor, whose visible window is what actually clips a
## button, or null when nothing scrolls above it.
func _scroll_ancestor(control: Control) -> ScrollContainer:
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return node as ScrollContainer
		node = node.get_parent()
	return null


## Walk everything currently on screen and measure it.
func _audit(node: Node, where: String) -> void:
	var viewport := root.get_viewport().get_visible_rect()
	var clipped: Array[String] = []
	var cramped: Array[String] = []
	var outside: Array[String] = []
	_walk(node, viewport, clipped, cramped, outside)

	check_true("%s: no control truncates its text (%s)" % [where, _sample(clipped)],
		clipped.is_empty())
	check_true("%s: every label and button is tall enough for its text (%s)"
		% [where, _sample(cramped)], cramped.is_empty())
	check_true("%s: nothing is pushed outside the 640x360 viewport (%s)"
		% [where, _sample(outside)], outside.is_empty())


func _walk(node: Node, viewport: Rect2, clipped: Array[String],
		cramped: Array[String], outside: Array[String]) -> void:
	for child in node.get_children():
		var control := child as Control
		if control != null and control.visible:
			_measure(control, viewport, clipped, cramped, outside)
		if control == null or control.visible:
			_walk(child, viewport, clipped, cramped, outside)


func _measure(control: Control, viewport: Rect2, clipped: Array[String],
		cramped: Array[String], outside: Array[String]) -> void:
	var text := ""
	if control is Label:
		text = (control as Label).text
	elif control is Button:
		text = (control as Button).text
	else:
		return
	if text.strip_edges().is_empty():
		return
	_checked += 1

	if control is Button and (control as Button).clip_text:
		clipped.append(control.name)
	if control is Label and (control as Label).clip_text:
		clipped.append(control.name)

	var rect := control.get_global_rect()
	# Scrollable regions legitimately extend past their container; the scroll area
	# itself is what has to stay on screen, and it is checked as its own control.
	if not _inside_scroll(control) and not viewport.encloses(rect) \
			and rect.size.x > 0.0 and rect.size.y > 0.0:
		outside.append("%s %s" % [control.name, rect])

	var font := control.get_theme_font("font")
	if font == null:
		return
	var font_size := control.get_theme_font_size("font_size")
	var wraps := false
	if control is Label:
		wraps = (control as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
	elif control is Button:
		wraps = (control as Button).autowrap_mode != TextServer.AUTOWRAP_OFF

	# Measure against the control's real inner width: a Button loses its stylebox
	# margins to padding, a Label loses nothing. Guessing a flat padding here made
	# the test demand a second line for text that genuinely fits on one.
	var pad := Vector2.ZERO
	var box := control.get_theme_stylebox("normal")
	if box != null:
		pad = Vector2(box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT),
			box.get_margin(SIDE_TOP) + box.get_margin(SIDE_BOTTOM))
	var needed: Vector2
	if wraps:
		needed = font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, maxf(rect.size.x - pad.x, 1.0), font_size)
	else:
		needed = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	needed += pad
	# One pixel of slack: these are float sizes settled by container maths.
	if needed.y > rect.size.y + 1.0 or (not wraps and needed.x > rect.size.x + 1.0):
		cramped.append("%s needs %s has %s: '%s'" % [
			control.name, needed.round(), rect.size.round(), text.substr(0, 24)])


func _inside_scroll(control: Control) -> bool:
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return true
		node = node.get_parent()
	return false


func _sample(items: Array[String]) -> String:
	if items.is_empty():
		return "none"
	return ", ".join(items.slice(0, 3)) + ("" if items.size() <= 3 else " …")


func _finish() -> void:
	print("")
	print(("PASS — every prompt, answer, name, and item is fully readable."
		if failures == 0 else "FAIL — %d layout check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
