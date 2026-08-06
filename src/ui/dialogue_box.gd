extends CanvasLayer
## Minimal dialogue box. Rebuild of DialogueBox.ts, pared to what the recall loop
## needs: a speaker name and one or more lines, advanced with the interact key or
## a click, closing with `dialogue_closed` so callers (the gate) can await it.
##
## Bus-driven: listens for `dialogue_open`, replies with `dialogue_closed`.
##
## BILINGUAL. The valley speaks Japanese; English is a translation you can reveal. A line
## carries both halves separated by `|`. The Japanese is what's displayed; the English sits
## underneath, shown only while Settings says so (pinned in settings, or held via TAB) — and
## it re-renders live when that changes, so peeking mid-line works.
##
## No audio. NPCs are silent by design: the project has no recorded Japanese (every source
## deck is mediaPolicy=excluded) and synthesised speech is not an acceptable stand-in for a
## real voice in a language-teaching game, so there is nothing honest to play.
##
## A line with no `|` is shown as-is. That keeps system messages ("The way is already
## open.") and any not-yet-translated content working unchanged.

const LANG_SEP := "|"

const COL_PANEL := UiTheme.SURFACE_BASE
const COL_BORDER := UiTheme.ACCENT_GOLD
const COL_NAME := UiTheme.ACCENT_GOLD
const COL_EN := UiTheme.STATE_INFO

var _active := false
var _lines: Array = []
var _line_index := 0

var _root: Control
var _name_label: Label
var _line_label: Label
var _en_label: Label
var _hint_label: Label


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_scaffold()
	_root.hide()
	Bus.dialogue_open.connect(_on_dialogue_open)
	# Re-render in place when English is pinned/unpinned or peeked mid-sentence.
	Bus.language_changed.connect(func(_visible): if _active: _refresh_english())
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))
	Bus.input_method_changed.connect(func(_method): if _active: _show_line())


func _on_dialogue_open(speaker: String, lines: Array) -> void:
	if _active:
		return
	_lines = lines.duplicate()
	if _lines.is_empty():
		Bus.dialogue_closed.emit()
		return
	_line_index = 0
	_active = true
	get_tree().paused = true
	_name_label.text = speaker
	_name_label.visible = speaker != ""
	_show_line()
	_root.show()


func _show_line() -> void:
	_line_label.text = _japanese_of(_line_index)
	_refresh_english()
	_hint_label.text = "[%s] %s" % [InputHints.primary_label("interact"),
		"next" if _line_index < _lines.size() - 1 else "close"]


## Japanese half of the current line (or the whole line when it carries no translation).
func _japanese_of(index: int) -> String:
	var raw := String(_lines[index])
	return raw.split(LANG_SEP)[0].strip_edges() if raw.contains(LANG_SEP) else raw


## English half, or "" when this line has no translation attached.
func _english_of(index: int) -> String:
	var raw := String(_lines[index])
	if not raw.contains(LANG_SEP):
		return ""
	var parts := raw.split(LANG_SEP)
	return parts[1].strip_edges() if parts.size() > 1 else ""


func _refresh_english() -> void:
	var en := _english_of(_line_index)
	_en_label.text = en
	_en_label.visible = not en.is_empty() and Settings.english_visible()


func _advance() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_close()
	else:
		_show_line()


func _close() -> void:
	_active = false
	_root.hide()
	get_tree().paused = false
	Bus.dialogue_closed.emit()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton and event.pressed):
		_advance()
		get_viewport().set_input_as_handled()


func _build_scaffold() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.fit_layer(self, _root)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	# Pinned to the bottom and grown UPWARD to fit its contents, so revealing the English
	# translation makes the box taller instead of pushing text off the screen edge.
	panel.anchor_left = 0.08; panel.anchor_right = 0.92
	panel.anchor_top = 1.0; panel.anchor_bottom = 1.0
	panel.offset_top = -190.0
	panel.offset_bottom = -24.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
	_name_label.add_theme_color_override("font_color", COL_NAME)
	vbox.add_child(_name_label)

	_line_label = Label.new()
	_line_label.add_theme_font_size_override("font_size", UiTheme.FONT_SECTION)
	_line_label.add_theme_color_override("font_color", Color.WHITE)
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_line_label)

	# Translation, tucked under the Japanese and tinted so it reads as a hint rather than
	# the primary text. Hidden unless the player asks for it.
	_en_label = Label.new()
	_en_label.add_theme_font_size_override("font_size", UiTheme.FONT_META)
	_en_label.add_theme_color_override("font_color", COL_EN)
	_en_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_en_label.hide()
	vbox.add_child(_en_label)

	_hint_label = Label.new()
	_hint_label.name = "InputHint"
	_hint_label.add_theme_font_size_override("font_size", UiTheme.FONT_META)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_hint_label)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.set_corner_radius_all(12)
	s.set_border_width_all(3)
	s.border_color = COL_BORDER
	return s
