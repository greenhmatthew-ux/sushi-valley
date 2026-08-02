extends CanvasLayer
## The recall micro-review UI. Rebuild of LearnPrompt.ts as Godot Control nodes.
##
## A gentle multiple-choice review: no typing, no shame. A wrong answer reveals
## the reading/meaning as a hint, and repeated misses surface more scaffolding.
## Results feed the shared SRS through Learning.progression.
##
## Bus-driven so it is decoupled from whatever opened it (a gate, a bookshelf, a
## menu button): it listens for `learn_open` and answers with `learn_closed`.
## Sessions of size > 1 run a short Focus Session with a streak header and a
## perfect-run XP bonus.
##
## Built in code because the number of choice buttons varies per card, and because
## the whole panel is dynamic — authoring it as a static .tscn would fight that.

const PERFECT_BONUS := 15   # extra XP for clearing a whole session with no misses

# Palette carried over from the TS build so the feel is consistent.
const COL_DIM := UiTheme.SURFACE_BACKDROP
const COL_PANEL := UiTheme.SURFACE_BASE
const COL_BORDER := UiTheme.ACCENT_GOLD
const COL_HEADING := UiTheme.TEXT_MUTED
const COL_HINT := UiTheme.STATE_INFO
const COL_HINT_STRONG := UiTheme.ACCENT_GOLD
const COL_GOOD := UiTheme.STATE_SUCCESS
const COL_BTN := UiTheme.SURFACE_RAISED
const COL_BTN_BORDER := UiTheme.BORDER_STRONG
const COL_CORRECT := UiTheme.FILL_CORRECT
const COL_WRONG := UiTheme.FILL_WRONG

# --- session state (mirrors LearnPrompt fields) ---
var _active := false
var _total := 1
var _index := 0                # questions completed so far
var _correct_count := 0
var _streak := 0
var _consecutive_wrong := 0
var _seen := {}
var _focus_lesson := ""
var _allow_practice := false
var _answered := false
var _current: Dictionary = {}
## How often a card that has already been answered correctly is asked by ear
## instead of by sight. Kept well below half: the written form is still the
## primary thing being taught, and a session that is mostly audio would stop
## training recognition of the script.
const LISTENING_CHANCE := 0.35
var _listening := false
var _rng := RandomNumberGenerator.new()

var _root: Control
var _heading: Label
var _furigana: Label
var _question: Label
var _listen_spacer: Control
var _listen_btn: Button
var _hint: Label
var _feedback: Label
var _choices_box: GridContainer
var _continue_btn: Button


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep running while the world is paused
	_build_scaffold()
	_root.hide()
	Bus.learn_open.connect(_on_learn_open)


func _on_learn_open(focus_lesson: String, session_size: int, allow_practice: bool) -> void:
	if _active:
		return   # one session at a time
	_total = maxi(1, session_size)
	_index = 0
	_correct_count = 0
	_streak = 0
	_consecutive_wrong = 0
	_seen.clear()
	_focus_lesson = focus_lesson
	# Multi-card sessions fall back to practice once due cards run out, so the run
	# can still complete (matches LearnPrompt).
	_allow_practice = allow_practice or _total > 1
	_active = true
	get_tree().paused = true
	_run_next()


func _run_next() -> void:
	var prompt: Dictionary = Learning.progression.build_prompt({}, _allow_practice, _focus_lesson)
	# Stop early if nothing is left, or the pool is so small we'd just repeat a card.
	if prompt.is_empty() or (_index > 0 and _seen.has(prompt["card"].get("id", ""))):
		_finish()
		return
	_seen[prompt["card"].get("id", "")] = true
	_current = prompt
	_answered = false
	_render(prompt)
	_root.show()


func _render(prompt: Dictionary) -> void:
	var is_session := _total > 1
	if is_session:
		_heading.text = "Focus session — %d/%d%s" % [
			_index + 1, _total, ("     Streak %d" % _streak) if _streak > 1 else ""]
	else:
		_heading.text = "Quick recall" if prompt["mode"] == "due" else "Notebook practice"
	_heading.add_theme_color_override("font_color", COL_HEADING)

	_hint.text = ""
	_feedback.text = ""
	_continue_btn.hide()
	var card_id := String(prompt["card"].get("id", ""))
	var has_audio := Audio.has_pronunciation(card_id)
	_listen_spacer.visible = has_audio
	_listen_btn.visible = has_audio
	Audio.stop_pronunciation()
	if has_audio:
		Audio.play_pronunciation(card_id)

	# Listening round: the written form is withheld and only the recording is given.
	# Reading a word and catching it spoken are different skills, and the game only
	# ever trained the first. Withheld only after the card has been answered
	# correctly at least once, so a word is always seen before it is heard blind.
	_listening = has_audio \
		and int(prompt["card"].get("correctCount", 0)) >= 1 \
		and _rng.randf() < LISTENING_CHANCE
	_question.text = "Listen" if _listening else String(prompt["question"])

	# Furigana: the reading printed above the Japanese, per UI_UX_GUIDE section 15.
	# Withheld during a listening round — the whole point there is to identify the
	# word by ear, and spelling it out on screen would answer the question.
	var reading := String(prompt.get("reading", "")).strip_edges()
	var correct_count := int(prompt["card"].get("correctCount", 0))
	# A kana card's reading is its own prompt, so printing it above would just repeat
	# the same characters — the aid is only an aid when it says something new.
	var show_reading := not _listening and not reading.is_empty() \
		and reading != String(prompt["question"]) \
		and Settings.furigana_visible(correct_count)
	_furigana.text = reading if show_reading else ""
	_furigana.visible = show_reading
	if _listening:
		_hint.text = "Which word did you hear?"
		_hint.add_theme_color_override("font_color", COL_HINT)

	# Adaptive scaffolding: struggling players get more context up front.
	var scaffold := _scaffold_level()
	if scaffold == 2 and prompt.get("reading", "") != "" and prompt.get("meaning", "") != "":
		_hint.text = "%s — %s" % [prompt["reading"], prompt["meaning"]]
		_hint.add_theme_color_override("font_color", COL_HINT_STRONG)
	elif scaffold >= 1 and prompt.get("reading", "") != "":
		_hint.text = String(prompt["reading"])
		_hint.add_theme_color_override("font_color", COL_HINT)

	for child in _choices_box.get_children():
		child.queue_free()
	var first_choice: Button = null
	for choice in prompt["choices"]:
		var choice_btn := _make_choice_button(String(choice))
		_choices_box.add_child(choice_btn)
		if first_choice == null:
			first_choice = choice_btn
	# Keyboard/controller: focus the first answer once the panel is shown, so arrows /
	# d-pad can move between choices right away. Deferred so it runs after _root.show().
	if first_choice != null:
		first_choice.grab_focus.call_deferred()


func _make_choice_button(choice: String) -> Button:
	var btn := Button.new()
	btn.text = choice
	# Never clip an answer: the player cannot choose between options they can only
	# half read. Long choices wrap and step down a size instead.
	btn.clip_text = false
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.custom_minimum_size = Vector2(200, 42)
	# Focusable so arrows / d-pad move between answers and ui_accept selects — the panel
	# is no longer mouse-only (the project requires keyboard AND controller to work).
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_stylebox_override("normal", _button_style(COL_BTN, COL_BTN_BORDER))
	btn.add_theme_stylebox_override("hover", _button_style(COL_BTN.lightened(0.08), COL_BORDER))
	btn.add_theme_stylebox_override("pressed", _button_style(COL_BTN, COL_BORDER))
	btn.add_theme_font_size_override("font_size", UiTheme.fit_font_size(choice, 18))
	# 42, down from 46: the furigana row above needs the height, and the button is
	# still taller than the text it holds — wrapped_height keeps long answers whole.
	btn.custom_minimum_size.y = maxf(42.0, UiTheme.wrapped_height(btn, choice, 200.0))
	btn.pressed.connect(_on_choice.bind(choice, btn))
	return btn


func _on_choice(choice: String, btn: Button) -> void:
	if _answered:
		return
	_answered = true
	var card: Dictionary = _current["card"]
	var correct: bool = Learning.progression.answer(card, choice)

	_index += 1
	if correct:
		_correct_count += 1
		_streak += 1
		_consecutive_wrong = 0
	else:
		_streak = 0
		_consecutive_wrong += 1

	Bus.card_reviewed.emit(String(card.get("id", "")), Srs.grade_from_correct(correct), correct)

	# Colour the chosen button, and on a miss also light up the right answer.
	btn.add_theme_stylebox_override("normal", _button_style(COL_CORRECT if correct else COL_WRONG, COL_BORDER))
	btn.add_theme_stylebox_override("hover", _button_style(COL_CORRECT if correct else COL_WRONG, COL_BORDER))
	if not correct:
		for other in _choices_box.get_children():
			if other is Button and (other as Button).text == String(_current["answer"]):
				other.add_theme_stylebox_override("normal", _button_style(COL_CORRECT, COL_BORDER))

	# A listening round withheld the writing; show it now, while the sound is still
	# in the player's head. That pairing is the whole point of asking by ear.
	if _listening:
		_question.text = String(card.get("prompt", ""))

	var reading := String(card.get("reading", ""))
	var answer_txt := reading if reading != "" else String(card.get("answer", ""))
	var meaning := String(card.get("meaning", ""))
	if correct:
		_feedback.add_theme_color_override("font_color", COL_GOOD)
		_feedback.text = "Correct!   %s = %s" % [card.get("prompt", ""), answer_txt]
	else:
		_feedback.add_theme_color_override("font_color", COL_HINT_STRONG)
		_feedback.text = "%s = %s%s" % [card.get("prompt", ""), answer_txt,
			("   (%s)" % meaning) if meaning != "" else ""]
	# Imported decks glue their usage notes onto the end of the answer, where they
	# are too long to sit on a rune button. Normalization moves them to `note`, and
	# the reveal is the one moment the player has room to read them.
	var note := String(card.get("note", ""))
	if not note.is_empty():
		_feedback.text += "\n%s" % note

	# Replay the card's sourced recording after any answer, win or miss.
	Audio.play_pronunciation(String(card.get("id", "")))

	_continue_btn.show()
	_continue_btn.grab_focus()


func _on_continue() -> void:
	_root.hide()
	if _total > 1 and _index < _total:
		_run_next()
	else:
		_finish()


func _finish() -> void:
	_root.hide()
	if _total > 1:
		var perfect := _correct_count == _index and _index > 0
		if perfect:
			Learning.progression.award_xp(PERFECT_BONUS)
		var summary: String
		if _index == 0:
			summary = "Nothing to review right now."
		elif perfect:
			summary = "Perfect focus! %d/%d  +%d XP" % [_correct_count, _index, PERFECT_BONUS]
		else:
			summary = "Focus session: %d/%d correct" % [_correct_count, _index]
		Bus.toast.emit(summary)
	_close(false)


func _close(cancelled: bool) -> void:
	var attempted := _index
	var correct := _correct_count
	Audio.stop_pronunciation()
	_active = false
	_current = {}
	get_tree().paused = false
	Bus.learn_closed.emit(attempted, correct, cancelled)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("ui_cancel"):
		# ESC cancels; a settled prompt (already answered) shouldn't be abandoned
		# mid-feedback, so require an unanswered prompt — matching LearnPrompt.
		if not _answered:
			_root.hide()
			_close(true)
			get_viewport().set_input_as_handled()
		return
	# Number-key quick-answer (1..N), mirroring the on-screen choice order — a fast path
	# alongside focus navigation. Guard on echo so a held key fires once.
	if not _answered and event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		var n := (event as InputEventKey).keycode - KEY_1
		if n >= 0 and n < _choices_box.get_child_count():
			var choice_btn := _choices_box.get_child(n) as Button
			_on_choice(choice_btn.text, choice_btn)
			get_viewport().set_input_as_handled()


## reading only after 2 consecutive misses; reading + meaning after 3.
func _scaffold_level() -> int:
	if _consecutive_wrong >= 3:
		return 2
	if _consecutive_wrong >= 2:
		return 1
	return 0


# --- static scaffold, built once ------------------------------------------

func _build_scaffold() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 0)
	_root.add_child(panel)
	# Center it.
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	# 10 rather than 12: the furigana row costs height, and six gaps at two pixels
	# each is exactly what keeps the reveal state inside a 360px viewport.
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var heading_row := HBoxContainer.new()
	vbox.add_child(heading_row)

	_listen_spacer = Control.new()
	_listen_spacer.custom_minimum_size = Vector2(96, 0)
	heading_row.add_child(_listen_spacer)

	_heading = _label(14, COL_HEADING)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading_row.add_child(_heading)

	_listen_btn = Button.new()
	_listen_btn.text = "Listen"
	_listen_btn.tooltip_text = "Play the sourced Japanese recording"
	_listen_btn.custom_minimum_size = Vector2(96, 26)
	_listen_btn.focus_mode = Control.FOCUS_ALL
	_listen_btn.add_theme_font_size_override("font_size", 12)
	_listen_btn.add_theme_stylebox_override("normal", _compact_button_style(COL_BTN, COL_BTN_BORDER))
	_listen_btn.add_theme_stylebox_override("hover", _compact_button_style(COL_BTN.lightened(0.08), COL_BORDER))
	_listen_btn.add_theme_stylebox_override("pressed", _compact_button_style(COL_BTN, COL_BORDER))
	_listen_btn.pressed.connect(_on_listen_pressed)
	heading_row.add_child(_listen_btn)

	# Above the prompt, small and quiet: it is a reading aid, not the question.
	_furigana = _label(13, COL_HINT)
	_furigana.name = "Furigana"
	_furigana.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_furigana.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_furigana)

	# 40 rather than 48: the furigana row above needs the height, and the prompt is
	# still far larger than body text, which is what section 16 asks for.
	_question = _label(40, Color.WHITE)
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_question)

	_hint = _label(13, COL_HINT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint)

	_feedback = _label(14, COL_GOOD)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_feedback)

	_choices_box = GridContainer.new()
	_choices_box.columns = 2
	_choices_box.add_theme_constant_override("h_separation", 16)
	_choices_box.add_theme_constant_override("v_separation", 10)
	vbox.add_child(_choices_box)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.custom_minimum_size = Vector2(0, 32)
	_continue_btn.add_theme_stylebox_override("normal", _button_style(COL_CORRECT, COL_CORRECT))
	_continue_btn.add_theme_stylebox_override("hover", _button_style(COL_CORRECT.lightened(0.1), COL_BORDER))
	_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_continue_btn)


func _on_listen_pressed() -> void:
	if _current.is_empty():
		return
	var card: Dictionary = _current.get("card", {})
	Audio.play_pronunciation(String(card.get("id", "")))


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


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _compact_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := _button_style(bg, border)
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s
