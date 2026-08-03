extends SceneTree
## Notification bursts: nothing is lost, repeats aggregate, dialogue is respected.
##
##   godot --headless --path . --script res://tests/test_toast_feed.gd
##
## The old toast layer overwrote the visible message the instant another
## arrived, so a loot + XP + quest burst kept only its last line. These checks
## pin the feed policy (queue distinct, fold repeats into ×N, drain faster
## under a backlog) and that the layer renders the feed's answer and slides out
## of the bottom band while dialogue or combat own it.

const Feed = preload("res://src/systems/toast_feed.gd")

var failures: int = 0


func _initialize() -> void:
	_burst_keeps_everything()
	_repeats_fold()
	_backlog_drains_faster()
	await _layer_behavior()
	_finish()


func _burst_keeps_everything() -> void:
	var feed = Feed.new()
	check_true("first message shows immediately", feed.push("Picked up Bamboo", 0.0))
	check_eq("and reads verbatim", feed.display_text(), "Picked up Bamboo")
	check_true("a different message waits its turn instead of replacing",
		not feed.push("+6 XP", 0.1))
	check_eq("so the first is still up", feed.display_text(), "Picked up Bamboo")
	check_eq("with one waiting", feed.backlog(), 1)

	check_true("nothing changes before the hold elapses", not feed.tick(0.5))
	check_true("after the hold the next comes up", feed.tick(2.0))
	check_eq("in arrival order", feed.display_text(), "+6 XP")
	check_true("the last message expires on the full hold", feed.tick(5.0))
	check_true("and the strip goes quiet", not feed.is_showing())
	check_true("a quiet feed has nothing to advance", not feed.tick(9.0))


func _repeats_fold() -> void:
	var feed = Feed.new()
	feed.push("Picked up Bamboo", 0.0)
	check_true("a repeat of the visible message redraws it", feed.push("Picked up Bamboo", 0.4))
	check_eq("as a count, not a duplicate", feed.display_text(), "Picked up Bamboo  ×2")
	check_eq("and queues nothing", feed.backlog(), 0)
	check_true("the count keeps it on screen past the original hold", not feed.tick(2.3))

	feed.push("+6 XP", 0.5)
	feed.push("+6 XP", 0.6)
	check_eq("repeats of a waiting message fold into it too", feed.backlog(), 1)
	feed.tick(3.0)
	check_eq("and surface with their count", feed.display_text(), "+6 XP  ×2")


func _backlog_drains_faster() -> void:
	var feed = Feed.new()
	feed.push("one", 0.0)
	feed.push("two", 0.1)
	check_true("with a backlog the visible message yields early", feed.tick(1.1))
	check_eq("to the next in line", feed.display_text(), "two")
	check_true("alone again, the short hold no longer applies", not feed.tick(2.0))


func _layer_behavior() -> void:
	await process_frame
	var bus: Node = root.get_node("Bus")
	var layer := CanvasLayer.new()
	layer.set_script(load("res://src/ui/toast_layer.gd"))
	root.add_child(layer)
	await process_frame

	# Found by type, not by index: the layer's first child is the scaling root that
	# UI scale hangs everything off, and the strip lives inside it.
	var panel: PanelContainer = null
	for node in _all_descendants(layer):
		if node is PanelContainer:
			panel = node
			break
	check_true("the toast strip exists", panel != null)
	if panel == null:
		return
	var label := panel.get_child(0) as Label
	check_true("strip starts hidden", not panel.visible)

	bus.toast.emit("Picked up Bamboo")
	check_true("a toast shows the strip", panel.visible)
	bus.toast.emit("Picked up Bamboo")
	check_eq("repeat renders the folded count", label.text, "Picked up Bamboo  ×2")
	bus.toast.emit("+6 XP")
	check_eq("a burst does not overwrite the visible message", label.text, "Picked up Bamboo  ×2")

	var normal_anchor: float = panel.anchor_top
	bus.dialogue_open.emit("Mako", ["Fresh fish today."])
	check_true("dialogue lifts the strip out of the bottom band",
		panel.anchor_top < normal_anchor)
	bus.combat_started.emit("mushroom")
	bus.dialogue_closed.emit()
	check_true("closing dialogue mid-combat keeps it lifted",
		panel.anchor_top < normal_anchor)
	bus.combat_ended.emit(true)
	check_eq("with the band free it returns home", panel.anchor_top, normal_anchor)

	# The dialogue box pauses the tree while it is up; toasts must keep draining.
	check_true("layer keeps processing while the game is paused",
		layer.process_mode == Node.PROCESS_MODE_ALWAYS)

	layer.queue_free()
	await process_frame


func _all_descendants(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_all_descendants(child))
	return out


func _finish() -> void:
	print("")
	print(("PASS — toast bursts queue, fold, and stay clear of dialogue."
		if failures == 0 else "FAIL — %d toast feed check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
