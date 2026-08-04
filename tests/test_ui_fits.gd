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
## Appended to every check name so a failure says which UI scale broke it.
var _scale_label := ""


## The canvas panels actually lay out in. UI scale shrinks it (the layer is scaled
## up by the same factor), and a Control's rect is in that unscaled layer space —
## so this, not the raw 640x360 viewport, is what "on screen" means here.
func _logical_rect() -> Rect2:
	var settings: Node = root.get_node("Settings")
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 640)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 360)))
	return Rect2(Vector2.ZERO, (base / maxf(settings.ui_scale, 0.1)).floor())


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
	for item_id in ["rice_ball", "bamboo_tonic", "stone_soup", "straw_hat", "herb_seed"]:
		inv.add(item_id, 2)
	inv.add("copper_pick", 1)
	var farm: Node = root.get_node("Farm")
	farm.reset(false)
	# Worst honest sleep preview: one mature crop waits, one becomes ready,
	# another keeps growing, and one dry crop pauses.
	farm.logic.plots = {
		"layout_ready": {"cropId": "herb", "plantedDay": 0, "watered": false},
		"layout_soon": {"cropId": "herb", "plantedDay": 1, "watered": true},
		"layout_growing": {"cropId": "cucumber", "plantedDay": 1, "watered": true},
		"layout_dry": {"cropId": "cucumber", "plantedDay": 1, "watered": false},
	}
	var gathering: Node = root.get_node("Gathering")
	gathering.reset(false)
	gathering.logic.mark_gathered("layout_common", root.get_node("Farm").day(), 1)
	gathering.logic.mark_gathered("layout_rare", root.get_node("Farm").day(), 3)
	var fishing: Node = root.get_node("Fishing")
	fishing.register_site("layout_pond", "Long-Named Village Fishing Pond", 120,
		["spring", "summer", "autumn"])
	if not learning.profile.data.has("resourceNodes"):
		learning.profile.data["resourceNodes"] = {}
	learning.profile.data["resourceNodes"]["layout_pond"] = Time.get_unix_time_from_system()
	# Journal: one ordinary request plus both structured mission card shapes, all
	# actionable, so Track buttons and reward rows are measured at every scale.
	var layout_quest_id := "tools_of_the_trail"
	learning.profile.set_flag(QuestJournal.started_flag(layout_quest_id))
	learning.profile.set_flag("hana_first_lesson")
	learning.profile.data["raids"] = {
		"sushi_prep": {"stage": "recall-cleared", "completions": 0},
	}
	learning.profile.data["expeditions"] = {
		"forest_lunchbox": {"stage": "objective-recovered", "completions": 0},
	}
	learning.profile.data.erase("trackedActivity")
	# Bestiary: defeat the worst-case enemy (longest name, most drops to list) and
	# merely encounter a second, so both card branches render under real load.
	var worst_enemy_id := _worst_case_enemy_id(db)
	learning.profile.record_enemy_seen(worst_enemy_id)
	learning.profile.record_enemy_defeated(worst_enemy_id)
	if db.enemy_order.size() > 1:
		learning.profile.record_enemy_seen(String(db.enemy_order[1]))

	# Measuring the panels means answering questions, which earns XP and writes it
	# to the shared profile. This is a layout test; it should not move progress.
	var xp_before: int = int(learning.profile.data["stats"]["xp"])

	# Every UI scale, not just 100%. Turning the scale up shrinks the logical
	# canvas panels lay out in, so a panel that fits at 100% can genuinely
	# overflow at 160% — which is exactly the regression this suite exists to
	# catch, and the reason the setting cannot ship untested.
	var settings: Node = root.get_node("Settings")
	var original_scale: float = settings.ui_scale
	for scale in settings.UI_SCALES:
		settings.ui_scale = scale
		_scale_label = " @%d%%" % int(round(scale * 100.0))
		await _check_hud()
		await _check_welcome()
		await _check_combat(bus, db)
		await _check_recall(bus)
		await _check_menu()
		await _check_notebook()
		await _check_farm(bus)
		await _check_shop(bus)
		await _check_fishing(bus)
	settings.ui_scale = original_scale
	_scale_label = ""

	print("")
	print("  ..   measured %d text controls across ten surfaces at %d UI scales"
		% [_checked, settings.UI_SCALES.size()])
	inv.reset()
	farm.reset(false)
	gathering.reset(false)
	learning.profile.data["resourceNodes"].erase("layout_pond")
	learning.profile.data["stats"]["xp"] = xp_before
	learning.profile.data.erase("bestiary")
	learning.profile.set_flag(QuestJournal.started_flag(layout_quest_id), false)
	learning.profile.set_flag("hana_first_lesson", false)
	learning.profile.data.erase("raids")
	learning.profile.data.erase("expeditions")
	learning.profile.data.erase("trackedActivity")
	learning.profile.save()
	_finish()


func _check_hud() -> void:
	var hud := CanvasLayer.new()
	hud.set_script(load("res://src/ui/hud_layer.gd"))
	root.add_child(hud)
	await process_frame
	_audit(hud, "hud/weather")
	hud.queue_free()
	await process_frame


func _check_welcome() -> void:
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/welcome_back_panel.gd"))
	root.add_child(panel)
	await process_frame
	panel.call("_show_model", {"show": true, "lines": [
		{"kind": "ready", "text": "Ready to turn in: Tools of the Trail - see Kaji"},
		{"kind": "active", "text": "In progress: Whispering Woods - 2/3 objectives"},
		{"kind": "mission", "text": "Expedition: Forest Lunchbox - Complete recall at the objective"},
		{"kind": "more", "text": "…and 2 more in the Journal"},
		{"kind": "farm", "text": "Farm: 2 crops ready to harvest"},
		{"kind": "review", "text": "138 words due for review"},
		{"kind": "points", "text": "Points to spend: 12 Talent · 9 Attribute"},
	]})
	await process_frame
	_audit(panel, "welcome/daily briefing")
	panel.call("_close")
	panel.queue_free()
	await process_frame


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
	for tab in ["character", "skills", "bag", "quests", "map", "learning", "system", "bestiary"]:
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


func _check_farm(bus: Node) -> void:
	var picker := CanvasLayer.new()
	picker.set_script(load("res://src/ui/crop_picker_panel.gd"))
	root.add_child(picker)
	await process_frame
	bus.farm_plot_open.emit("layout_plot")
	await process_frame
	_audit(picker, "farm/seed picker")
	picker.call("_close")
	picker.queue_free()
	await process_frame

	var day_end := CanvasLayer.new()
	day_end.set_script(load("res://src/ui/day_end_panel.gd"))
	root.add_child(day_end)
	await process_frame
	bus.sleep_requested.emit()
	await process_frame
	_audit(day_end, "farm/day end")
	day_end.call("_close")
	day_end.queue_free()
	await process_frame


func _check_shop(bus: Node) -> void:
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/shop_panel.gd"))
	root.add_child(panel)
	await process_frame
	bus.shop_open.emit("mako_stall")
	await process_frame
	_audit(panel, "shop/starter stall")
	panel.call("_close")
	panel.queue_free()
	await process_frame


func _check_fishing(bus: Node) -> void:
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/fishing_panel.gd"))
	root.add_child(panel)
	await process_frame
	bus.fishing_open.emit("layout_pond", "Long-Named Village Fishing Pond", 2, 120, 0.1)
	await process_frame
	_audit(panel, "fishing/minigame")
	panel.call("_cancel")
	panel.queue_free()
	await process_frame


## The enemy whose Bestiary card has the most text to fit: name length plus drop
## count, since a defeated card prints both the full name/level header and the
## complete drop table.
func _worst_case_enemy_id(db: Node) -> String:
	var best_id := String(db.enemy_order[0])
	var best_score := -1
	for id in db.enemy_order:
		var enemy: Dictionary = db.enemy(String(id))
		var score := String(enemy.get("name", "")).length() \
			+ int(enemy.get("drops", []).size()) * 8
		if score > best_score:
			best_score = score
			best_id = String(id)
	return best_id


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
		check_true("%s%s: has choices to check" % [where, _scale_label], false)
		return
	var viewport := _logical_rect()
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
	check_true("%s%s: every answer is fully visible without scrolling (%s)"
		% [where, _scale_label, _sample(hidden)], hidden.is_empty())


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
	var viewport := _logical_rect()
	var clipped: Array[String] = []
	var cramped: Array[String] = []
	var outside: Array[String] = []
	_walk(node, viewport, clipped, cramped, outside)

	check_true("%s%s: no control truncates its text (%s)" % [where, _scale_label, _sample(clipped)],
		clipped.is_empty())
	check_true("%s%s: every label and button is tall enough for its text (%s)"
		% [where, _scale_label, _sample(cramped)], cramped.is_empty())
	check_true("%s%s: nothing is pushed outside the %s canvas (%s)"
		% [where, _scale_label, viewport.size, _sample(outside)], outside.is_empty())


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
	# Panel shells carry no text, so the text checks below skip them — but a shell
	# that outgrows the canvas takes its whole panel off screen, which is exactly
	# what a screenshot caught after UI scale shrank the canvas under a fixed-width
	# tab row.
	#
	# Full rect, width AND height. This used to be width-only, because it also
	# surfaced that the recall panel's reveal state had always been taller than the
	# canvas (a 395px frame in 360px at 100%, 403 worst case): the text stayed on
	# screen, so the only symptom was a gold border clipped off the top and bottom,
	# and nobody noticed for months. recall_panel.gd now steps its own layout
	# density down until the frame fits, and this check is what holds that — a
	# clipped frame is a real defect, not an acceptable cost of a dense panel.
	if control is PanelContainer and not _inside_scroll(control):
		var frame := control.get_global_rect()
		if frame.size.x > 0.0 and frame.size.y > 0.0 \
				and not viewport.grow(1.0).encloses(frame):
			outside.append("%s (frame) %s" % [control.name, frame])

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
