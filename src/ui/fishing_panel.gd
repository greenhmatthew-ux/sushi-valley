extends CanvasLayer
## Screen-space fishing challenge. Hold Interact to lift the green catch bar,
## release to let it fall, and keep the fish inside until progress reaches 100.

const Rules = preload("res://src/systems/fishing_logic.gd")
const MeterView = preload("res://src/ui/fishing_meter.gd")

var _open := false
var _resolving := false
var _pointer_reeling := false
var _site_id := ""
var _base_qty := 1
var _cooldown_seconds := 120
var _difficulty := 1.0
var _logic: RefCounted = null
var _root: Control
var _shell: PanelContainer
var _title: Label
var _status: Label
var _hint: Label
var _meter: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	Bus.fishing_open.connect(_on_open)
	Bus.input_method_changed.connect(func(_method): _refresh_hint())
	Bus.ui_scale_changed.connect(func(_scale): _fit())


func _process(delta: float) -> void:
	if not _open or _logic == null or _resolving:
		return
	var reeling := Input.is_action_pressed("interact") or _pointer_reeling
	var state: Dictionary = _logic.step(delta, reeling)
	_meter.queue_redraw()
	if bool(state.get("in_grace", true)):
		_status.text = "Cast! Get ready..."
	else:
		_status.text = "%d%% - %s" % [roundi(float(state.get("progress", 0.0))),
			"On the line" if bool(state.get("overlap", false)) else "Move the green bar"]
	if bool(state.get("finished", false)):
		_resolving = true
		_resolve_result.call_deferred()


func _on_open(site_id: String, display_name: String, base_qty: int,
		cooldown_seconds: int, difficulty: float) -> void:
	if _open or get_tree().paused:
		return
	_site_id = site_id
	_base_qty = maxi(1, base_qty)
	_cooldown_seconds = maxi(1, cooldown_seconds)
	_difficulty = maxf(0.1, difficulty)
	_logic = Rules.new(_difficulty)
	_meter.set_logic(_logic)
	_title.text = "Fishing - %s" % display_name
	_status.text = "Cast! Get ready..."
	_pointer_reeling = false
	_resolving = false
	_open = true
	_refresh_hint()
	_root.show()
	get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_pointer_reeling = (event as InputEventMouseButton).pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_pointer_reeling = (event as InputEventScreenTouch).pressed
		get_viewport().set_input_as_handled()


func _resolve_result() -> void:
	if not _open or _logic == null:
		return
	if not _logic.success:
		_close()
		Bus.toast.emit("It got away...")
		return
	var result := Fishing.complete(_site_id, _base_qty, _logic.quality(),
		_cooldown_seconds, _difficulty)
	_close()
	if bool(result.get("ok", false)):
		var praise := "Perfect catch!" if result.get("quality") == "gold" \
			else ("Nice catch!" if result.get("quality") == "silver" else "Caught it!")
		Bus.toast.emit("%s River Fish x%d - +%d Kitchen XP" % [
			praise, int(result.get("qty", 1)), int(result.get("xp", 0))])
	else:
		Bus.toast.emit(String(result.get("reason", "The catch slipped away.")))


func _cancel() -> void:
	if not _open:
		return
	_close()
	Bus.toast.emit("Line reeled in. The fishing spot stays ready.")


func _close() -> void:
	_open = false
	_resolving = false
	_pointer_reeling = false
	_logic = null
	_meter.set_logic(null)
	_root.hide()
	get_tree().paused = false


func _refresh_hint() -> void:
	if _hint == null:
		return
	_hint.text = "Hold %s or press/touch to lift the green bar. Release to lower it. %s cancels." % [
		InputHints.joined_labels(["interact"]), InputHints.primary_label("ui_cancel")]


func _fit() -> void:
	UiTheme.fit_layer(self, _root)
	UiTheme.fit_modal_shell(_shell, 0.32, 0.05)


func _build() -> void:
	_root = Control.new()
	_root.name = "FishingRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := UiTheme.backdrop()
	_root.add_child(dim)
	_shell = PanelContainer.new()
	_shell.name = "FishingShell"
	_shell.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.ACCENT_GOLD))
	_root.add_child(_shell)
	_fit()

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	_shell.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	_title = UiTheme.label("Fishing", UiTheme.FONT_SECTION, UiTheme.ACCENT_GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_status = UiTheme.label("Cast! Get ready...", UiTheme.FONT_META, UiTheme.TEXT_PRIMARY)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	_meter = MeterView.new()
	_meter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_meter)
	_hint = UiTheme.label("", UiTheme.FONT_META, UiTheme.TEXT_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)
	var cancel := Button.new()
	cancel.name = "CancelFishing"
	cancel.text = "Reel in and leave"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_cancel)
	box.add_child(cancel)
