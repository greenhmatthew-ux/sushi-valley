extends CanvasLayer
## The Notebook: everything you have learned, and what the schedule wants next.
##
## SITE_WIDE_LEARNING_ARCHITECTURE.md lists the Notebook as one of the shared learning
## surfaces. It is read-only on purpose — reviewing happens out in the world with the
## people and places that taught you, not in a menu. This just answers "what do I know,
## and what's waiting?".
##
## Opened with `open_notebook`. Built in code like the other panels because the lesson and
## card counts are entirely data-driven.

const COL_DIM := Color(0.02, 0.03, 0.047, 0.6)
const COL_PANEL := Color(0.078, 0.106, 0.141, 0.98)
const COL_BORDER := Color(1.0, 0.824, 0.49)
const COL_HEADING := Color(0.624, 0.69, 0.765)
const COL_TEXT := Color(0.93, 0.95, 0.96)
const COL_JA := Color(1.0, 1.0, 1.0)
const COL_EN := Color(0.624, 0.839, 1.0)
const COL_DUE := Color(1.0, 0.824, 0.49)
const COL_GOOD := Color(0.608, 0.906, 0.639)
const COL_LOCKED := Color(0.42, 0.47, 0.55)

var _open := false
var _root: Control
var _summary: Label
var _list: VBoxContainer


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	# Re-render live so peeking English (TAB) reveals the meanings in here too.
	Bus.language_changed.connect(func(_v): if _open: _refresh())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_notebook"):
		_set_open(not _open)
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_open = open
	if open:
		_refresh()
		_root.show()
		get_tree().paused = true
	else:
		_root.hide()
		get_tree().paused = false


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	var known := 0
	var due := 0
	var show_en: bool = Settings.english_visible()

	for lesson_id in DB.lesson_order:
		var lesson: Dictionary = DB.lessons[lesson_id]
		var card_ids: Array = lesson.get("cardIds", [])
		if card_ids.is_empty():
			continue

		var unlocked_cards: Array = []
		for cid in card_ids:
			var c: Dictionary = Learning.profile.card(cid)
			if not c.is_empty() and c.get("unlocked", false):
				unlocked_cards.append(c)
		if unlocked_cards.is_empty():
			continue   # nothing learned here yet — don't spoil what's ahead

		known += unlocked_cards.size()
		var lesson_due: int = Srs.due(unlocked_cards).size()
		due += lesson_due

		_list.add_child(_lesson_header(lesson, unlocked_cards.size(), card_ids.size(), lesson_due))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 4)
		for c in unlocked_cards:
			grid.add_child(_card_chip(c, show_en))
		_list.add_child(grid)
		_list.add_child(_spacer(10))

	# Deliberately NOT "x of <every card in the database>". The imported travel decks push
	# that total past a thousand, which reads as hopeless rather than motivating. What the
	# player wants to know is what they know and what's waiting.
	_summary.text = "%d words learned   ·   %d due for review" % [known, due]
	if known == 0:
		var empty := _label(15, COL_HEADING)
		empty.text = "Nothing learned yet. Talk to the villagers — they will teach you."
		_list.add_child(empty)


func _lesson_header(lesson: Dictionary, learned: int, total: int, due: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var title := _label(15, COL_BORDER)
	title.text = String(lesson.get("title", lesson.get("id", "")))
	row.add_child(title)

	var count := _label(12, COL_HEADING)
	count.text = "%d/%d" % [learned, total]
	row.add_child(count)

	if due > 0:
		var due_label := _label(12, COL_DUE)
		due_label.text = "· %d due" % due
		row.add_child(due_label)
	elif learned == total:
		var done := _label(12, COL_GOOD)
		done.text = "· all learned"
		row.add_child(done)
	return row


## One word: the Japanese, plus its meaning when English is showing. A card the schedule
## wants back is tinted so "what should I go practise" is answerable at a glance.
func _card_chip(card: Dictionary, show_en: bool) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(150, 0)

	var ja := _label(17, COL_DUE if Srs.is_due(card) else COL_JA)
	ja.text = String(card.get("prompt", ""))
	box.add_child(ja)

	if show_en:
		var en := _label(11, COL_EN)
		var meaning := String(card.get("meaning", ""))
		en.text = meaning if not meaning.is_empty() else String(card.get("answer", ""))
		en.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(en)
	return box


# --- scaffold ---------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	# Inset from the screen edges rather than sized to content: the word list grows without
	# bound as the player learns, and a content-sized panel would run off the viewport.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.anchor_left = 0.10; panel.anchor_right = 0.90
	panel.anchor_top = 0.06; panel.anchor_bottom = 0.94
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := _label(20, COL_BORDER)
	title.text = "Notebook  ·  ノート"
	vbox.add_child(title)

	_summary = _label(13, COL_HEADING)
	vbox.add_child(_summary)

	var hint := _label(11, COL_EN)
	hint.text = "Hold TAB to show meanings.  Highlighted words are due for review."
	vbox.add_child(hint)

	# Only the word list scrolls — the header stays put (UX rule: avoid long page scrolls).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.set_corner_radius_all(16)
	s.set_border_width_all(3)
	s.border_color = COL_BORDER
	return s
