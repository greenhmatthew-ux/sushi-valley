extends SceneTree
## Combat action-bar UX at the base 640x360 viewport: an unarmed fresh player keeps
## Basic Attack and the weapon-free starter skills without exposing unusable Strike.

var failures := 0


func _initialize() -> void:
	await process_frame
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
	var bus: Node = root.get_node("Bus")
	learning.profile.unlock_card("kana-a")
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/combat_panel.gd"))
	root.add_child(panel)
	await process_frame
	bus.combat_started.emit(String(db.enemy_order[0]))
	await process_frame

	var shell: Control = panel.find_child("CombatShell", true, false)
	var actions: Control = panel.find_child("CombatActions", true, false)
	check_true("combat opens", bool(panel.get("_active")))
	var viewport_rect := root.get_viewport().get_visible_rect()
	var shell_rect := shell.get_global_rect()
	check_true("combat shell stays inside the 640x360 viewport (%s)" % shell_rect,
		viewport_rect.encloses(shell_rect))
	check_eq("unarmed combat offers Basic, Guard, and Focus", actions.get_child_count(), 3)
	check_eq("Basic Attack is the safe default", (actions.get_child(0) as Button).text, "Basic")
	check_true("weapon-gated Strike is not a fake action",
		_find_button(actions, "Strike") == null)

	panel.call("_finish", false, "")
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
