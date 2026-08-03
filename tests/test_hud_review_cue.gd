extends SceneTree
## The HUD due cue starts a review session in one step, and knows when not to.
##
##   godot --headless --path . --script res://tests/test_hud_review_cue.gd
##
## UI_UX_GUIDE's depth table puts "review due Japanese" at one layer: the HUD
## cue/shortcut opens a prepared session directly, instead of menu -> Learning
## -> button. These checks pin that the cue is a real action (click and the
## open_review binding reach the same prepared session the Pause Hub starts)
## and that it stays inert while something else owns the screen.

var failures: int = 0
var _opened: Array = []   ## captured learn_open emissions


func _initialize() -> void:
	await process_frame
	var bus: Node = root.get_node("Bus")
	bus.learn_open.connect(func(lesson, size, practice): _opened.append([lesson, size, practice]))

	var hud := CanvasLayer.new()
	hud.set_script(load("res://src/ui/hud_layer.gd"))
	root.add_child(hud)
	await process_frame

	var cue: Button = null
	for child in _all_descendants(hud):
		if child is Button and child.name == "HudDueReview":
			cue = child
			break
	check_true("the due cue is a real button", cue != null)
	if cue == null:
		_finish()
		return
	check_true("it never joins the focus loop (arrows are movement)",
		cue.focus_mode == Control.FOCUS_NONE)

	cue.pressed.emit()
	check_eq("clicking the cue opens one session", _opened.size(), 1)
	check_true("a prepared mixed session, same as the Pause Hub's button",
		_opened[0][0] == "" and int(_opened[0][1]) > 1 and bool(_opened[0][2]))

	var press := InputEventAction.new()
	press.action = "open_review"
	press.pressed = true
	hud.call("_unhandled_input", press)
	check_eq("the open_review binding reaches the same session", _opened.size(), 2)

	paused = true
	hud.call("_unhandled_input", press)
	check_eq("while something that pauses owns the screen, the cue is inert",
		_opened.size(), 2)
	paused = false

	hud.hide()
	hud.call("_unhandled_input", press)
	check_eq("while combat hides the HUD, the cue is inert", _opened.size(), 2)
	hud.show()

	hud.queue_free()
	await process_frame
	_finish()


func _all_descendants(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_all_descendants(child))
	return out


func _finish() -> void:
	print("")
	print(("PASS — the HUD due cue opens a prepared review and respects modals."
		if failures == 0 else "FAIL — %d HUD review cue check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
