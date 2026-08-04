extends Node
## Session-wide input prompt authority.
##
## Prompts are derived from the real InputMap, not copied key names, and follow the
## last device that performed a meaningful action. Mouse motion is deliberately
## ignored so a resting cursor cannot replace controller prompts mid-session.

const KEYBOARD_MOUSE := "keyboard_mouse"
const GAMEPAD := "gamepad"

var input_method := KEYBOARD_MOUSE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	observe_event(event)


func observe_event(event: InputEvent) -> void:
	var next_method := ""
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		next_method = GAMEPAD
	elif event is InputEventJoypadMotion \
			and absf((event as InputEventJoypadMotion).axis_value) >= 0.5:
		next_method = GAMEPAD
	elif event is InputEventKey and (event as InputEventKey).pressed:
		next_method = KEYBOARD_MOUSE
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		next_method = KEYBOARD_MOUSE
	if not next_method.is_empty():
		set_input_method(next_method)


func set_input_method(value: String) -> void:
	var next := GAMEPAD if value == GAMEPAD else KEYBOARD_MOUSE
	if next == input_method:
		return
	input_method = next
	Bus.input_method_changed.emit(input_method)


func is_gamepad() -> bool:
	return input_method == GAMEPAD


## Primary visible label for one action on the active device.
func primary_label(action: String) -> String:
	var labels := labels_for_actions([action])
	return labels[0] if not labels.is_empty() else action.replace("_", " ").capitalize()


## All unique labels for several equivalent actions, such as Hub toggle + Back.
func joined_labels(actions: Array, separator: String = "/") -> String:
	return separator.join(labels_for_actions(actions))


func labels_for_actions(actions: Array) -> Array[String]:
	var labels: Array[String] = []
	for raw_action in actions:
		var action := String(raw_action)
		var found := false
		for event in InputMap.action_get_events(action):
			var label := _event_label(event)
			if not label.is_empty() and label not in labels:
				labels.append(label)
				found = true
		if not found:
			var fallback := _fallback_label(action)
			if not fallback.is_empty() and fallback not in labels:
				labels.append(fallback)
	return labels


## Godot's built-in UI actions are available at runtime but do not always expose
## their default events through InputMap in headless exports. Keep their standard
## accept/back copy explicit so a prompt never falls through to "Ui Cancel".
func _fallback_label(action: String) -> String:
	if action == "ui_cancel":
		return "B" if is_gamepad() else "Esc"
	if action == "ui_accept":
		return "A" if is_gamepad() else "Enter"
	return ""


func _event_label(event: InputEvent) -> String:
	if is_gamepad():
		if event is InputEventJoypadButton:
			return _joy_button_label((event as InputEventJoypadButton).button_index)
		return ""
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		var label := OS.get_keycode_string(code)
		return "Esc" if label == "Escape" else label
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
	return ""


## Godot's standard SDL-style button order. Plain labels stay readable with any
## controller skin; platform-specific art can replace this without changing callers.
func _joy_button_label(index: int) -> String:
	match index:
		0: return "A"
		1: return "B"
		2: return "X"
		3: return "Y"
		4: return "View"
		5: return "Guide"
		6: return "Menu"
		7: return "L3"
		8: return "R3"
		9: return "LB"
		10: return "RB"
		11: return "D-pad Up"
		12: return "D-pad Down"
		13: return "D-pad Left"
		14: return "D-pad Right"
	return "Button %d" % (index + 1)
